import Foundation
@preconcurrency import Markdown

/// Feature flags for a Markdown block node, computed during parsing.
struct MarkdownBlockFeatures: OptionSet, Sendable {
    let rawValue: UInt8
    static let hasLinks = MarkdownBlockFeatures(rawValue: 1 << 0)
    static let hasImages = MarkdownBlockFeatures(rawValue: 1 << 1)
    static let hasLaTeX = MarkdownBlockFeatures(rawValue: 1 << 2)
    static let hasMCodeReferences = MarkdownBlockFeatures(rawValue: 1 << 3)
}

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]
    let codeHighlights: [ObjectIdentifier: [[Token]]]
    let latexSegments: [ObjectIdentifier: [LaTeXPreprocessor.Segment]]
    let featuresMap: [ObjectIdentifier: MarkdownBlockFeatures]

    static let empty = MarkdownRenderSnapshot(blocks: [], codeHighlights: [:], latexSegments: [:], featuresMap: [:])

    // MARK: - Async parse

    static func parse(_ content: String, previousBlocks: [MarkdownBlockNode] = []) async -> Self {
        let children = await parsedChildren(for: content)
        let (blocks, featuresMap, latexSegments) = buildBlockNodes(children: children, reusingFrom: previousBlocks)
        let codeHighlights = await precomputeCodeHighlights(blocks: blocks)
        return MarkdownRenderSnapshot(blocks: blocks, codeHighlights: codeHighlights, latexSegments: latexSegments, featuresMap: featuresMap)
    }

    // MARK: - Async parse (compatibility — width/theme no longer used)

    static func parse(
        _ content: String,
        width: CGFloat,
        theme: MarkdownTheme,
        previousBlocks: [MarkdownBlockNode] = []
    ) async -> Self {
        return await Self.parse(content, previousBlocks: previousBlocks)
    }

    // MARK: - Sync parse (initial render, main actor)

    @MainActor
    static func parse(_ content: String, previousBlocks: [MarkdownBlockNode] = []) -> Self {
        let children = parsedChildrenSync(for: content)
        let (blocks, featuresMap, latexSegments) = buildBlockNodes(children: children, reusingFrom: previousBlocks)
        return MarkdownRenderSnapshot(blocks: blocks, codeHighlights: [:], latexSegments: latexSegments, featuresMap: featuresMap)
    }

    // MARK: - Block node building with feature extraction

    private static func buildBlockNodes(
        children: [any Markup],
        reusingFrom previous: [MarkdownBlockNode]
    ) -> (blocks: [MarkdownBlockNode], featuresMap: [ObjectIdentifier: MarkdownBlockFeatures], latexSegments: [ObjectIdentifier: [LaTeXPreprocessor.Segment]]) {
        var featuresMap: [ObjectIdentifier: MarkdownBlockFeatures] = [:]
        var latexSegments: [ObjectIdentifier: [LaTeXPreprocessor.Segment]] = [:]

        let blocks = children.enumerated().map { index, child in
            let kind = String(describing: type(of: child))
            let id: UUID
            if index < previous.count, previous[index].kind == kind {
                id = previous[index].id
            } else {
                id = UUID()
            }
            let features = computeFeaturesRecursively(child, featuresMap: &featuresMap, latexSegments: &latexSegments)
            return MarkdownBlockNode(id: id, kind: kind, markup: child, features: features)
        }

        return (blocks, featuresMap, latexSegments)
    }

    /// Recursively computes feature flags for a markup node and all descendants.
    @discardableResult
    private static func computeFeaturesRecursively(
        _ markup: any Markup,
        featuresMap: inout [ObjectIdentifier: MarkdownBlockFeatures],
        latexSegments: inout [ObjectIdentifier: [LaTeXPreprocessor.Segment]]
    ) -> MarkdownBlockFeatures {
        var features: MarkdownBlockFeatures = []
        let oid = ObjectIdentifier(markup as AnyObject)

        if markup is Markdown.Link {
            features.insert(.hasLinks)
        }
        if markup is Markdown.Image {
            features.insert(.hasImages)
        }
        if let code = markup as? InlineCode, let refs = parseMCodeReferences(from: code.code), !refs.isEmpty {
            features.insert(.hasMCodeReferences)
        }
        if let plainTextConvertible = markup as? (any PlainTextConvertibleMarkup) {
            let text = plainTextConvertible.plainText
            if LaTeXPreprocessor.containsLaTeX(text) {
                features.insert(.hasLaTeX)
                latexSegments[oid] = LaTeXPreprocessor.extractSegments(from: text)
            }
        }

        for child in markup.children {
            let childFeatures = computeFeaturesRecursively(child, featuresMap: &featuresMap, latexSegments: &latexSegments)
            features.formUnion(childFeatures)
        }

        featuresMap[oid] = features
        return features
    }

    // MARK: - Code highlighting precomputation

    private static func precomputeCodeHighlights(blocks: [MarkdownBlockNode]) async -> [ObjectIdentifier: [[Token]]] {
        await withTaskGroup(of: (ObjectIdentifier, [[Token]]).self) { group in
            for block in blocks {
                if let codeBlock = block.markup as? CodeBlock, codeBlock.language != "mermaid" {
                    group.addTask {
                        let tokens = SyntaxHighlighter().tokenize(codeBlock.code, language: codeBlock.language)
                        let lines = HighlightedCodeView.splitIntoLines(tokens)
                        return (ObjectIdentifier(codeBlock as AnyObject), lines)
                    }
                }
            }
            var result: [ObjectIdentifier: [[Token]]] = [:]
            for await (id, lines) in group {
                result[id] = lines
            }
            return result
        }
    }

    // MARK: - Parsed children cache (content → [any Markup])

    private static func parsedChildren(for content: String) async -> [any Markup] {
        if let cached = await MainActor.run(resultType: [any Markup]?.self, body: {
            MarkdownParsedChildrenCache.shared.object(forKey: content as NSString)?.children
        }) {
            return cached
        }

        nonisolated(unsafe) let children = preprocessedChildren(for: content)

        await MainActor.run {
            MarkdownParsedChildrenCache.shared.setObject(
                MarkdownParsedChildrenBox(children: children),
                forKey: content as NSString
            )
        }

        return children
    }

    @MainActor
    private static func parsedChildrenSync(for content: String) -> [any Markup] {
        if let cached = MarkdownParsedChildrenCache.shared.object(forKey: content as NSString)?.children {
            return cached
        }

        let children = preprocessedChildren(for: content)

        MarkdownParsedChildrenCache.shared.setObject(
            MarkdownParsedChildrenBox(children: children),
            forKey: content as NSString
        )

        return children
    }

    // MARK: - Preprocessing

    private static func preprocessedChildren(for content: String) -> [any Markup] {
        let processedContent = LaTeXPreprocessor.process(content)
        let document = Document(parsing: processedContent)
        return Array(document.children)
    }
}

// MARK: - Block Node

struct MarkdownBlockNode: Identifiable, @unchecked Sendable {
    let id: UUID
    let kind: String
    let markup: any Markup
    var features: MarkdownBlockFeatures = []
}

// MARK: - Caches

@MainActor
private final class MarkdownParsedChildrenCache {
    static let shared: NSCache<NSString, MarkdownParsedChildrenBox> = {
        let cache = NSCache<NSString, MarkdownParsedChildrenBox>()
        cache.countLimit = 128
        return cache
    }()
}

private final class MarkdownParsedChildrenBox: NSObject, @unchecked Sendable {
    let children: [any Markup]

    init(children: [any Markup]) {
        self.children = children
    }
}
