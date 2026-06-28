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

func computeFeaturesRecursively(_ markup: any Markup) -> MarkdownBlockFeatures {
    var features: MarkdownBlockFeatures = []
    
    switch markup {
    case _ as Markdown.Link:
        features.insert(.hasLinks)
    case _ as Markdown.Image:
        features.insert(.hasImages)
    case let code as InlineCode:
        if code.code.contains("$") {
            features.insert(.hasLaTeX)
        }
        if let refs = parseMCodeReferences(from: code.code), !refs.isEmpty {
            features.insert(.hasMCodeReferences)
        }
    case let text as Markdown.Text:
        if text.string.contains("$") {
            features.insert(.hasLaTeX)
        }
    default:
        break
    }
    
    for child in markup.children {
        features.formUnion(computeFeaturesRecursively(child))
    }
    return features
}

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]

    static let empty = MarkdownRenderSnapshot(blocks: [])

    // MARK: - Async parse

    static func parse(_ content: String, previousBlocks: [MarkdownBlockNode] = []) async -> Self {
        let children = await parsedChildren(for: content)
        let blocks = await buildBlockNodes(children: children, reusingFrom: previousBlocks)
        let snapshot = MarkdownRenderSnapshot(blocks: blocks)
        
        await MainActor.run {
            cacheSnapshot(snapshot, for: content)
        }
        
        Task.detached(priority: .background) {
            await precomputeCodeHighlights(blocks: blocks)
        }
        
        return snapshot
    }

    // MARK: - Sync parse

    @MainActor
    static func parseSynchronously(_ content: String, previousBlocks: [MarkdownBlockNode] = []) -> Self {
        let children: [any Markup]
        if let cached = MarkdownParsedChildrenCache.shared.object(forKey: content as NSString)?.children {
            children = cached
        } else {
            children = preprocessedChildren(for: content)
            MarkdownParsedChildrenCache.shared.setObject(
                MarkdownParsedChildrenBox(children: children),
                forKey: content as NSString
            )
        }

        var blocks: [MarkdownBlockNode] = []
        for (index, child) in children.enumerated() {
            let kind = String(describing: type(of: child))
            let id: UUID
            if index < previousBlocks.count, previousBlocks[index].kind == kind {
                id = previousBlocks[index].id
            } else {
                id = UUID()
            }
            let features = computeFeaturesRecursively(child)
            let node = MarkdownBlockNode(id: id, kind: kind, markup: child, features: features)
            blocks.append(node)
        }
        
        let snapshot = MarkdownRenderSnapshot(blocks: blocks)
        cacheSnapshot(snapshot, for: content)
        
        let blocksForHighlight = blocks
        Task.detached(priority: .background) {
            await precomputeCodeHighlights(blocks: blocksForHighlight)
        }
        
        return snapshot
    }

    // MARK: - Block node building with feature extraction

    private static func buildBlockNodes(
        children: [any Markup],
        reusingFrom previous: [MarkdownBlockNode]
    ) async -> [MarkdownBlockNode] {
        await withTaskGroup(of: (Int, MarkdownBlockNode).self) { group in
            for (index, child) in children.enumerated() {
                let kind = String(describing: type(of: child))
                let id: UUID
                if index < previous.count, previous[index].kind == kind {
                    id = previous[index].id
                } else {
                    id = UUID()
                }
                
                group.addTask {
                    let features = computeFeaturesRecursively(child)
                    let node = MarkdownBlockNode(id: id, kind: kind, markup: child, features: features)
                    return (index, node)
                }
            }
            
            var results: [Int: MarkdownBlockNode] = [:]
            for await (index, node) in group {
                results[index] = node
            }
            
            return (0..<children.count).compactMap { results[$0] }
        }
    }

    // MARK: - Code highlighting precomputation

    private static func precomputeCodeHighlights(blocks: [MarkdownBlockNode]) async -> [UUID: [[Token]]] {
        await withTaskGroup(of: (UUID, [[Token]]).self) { group in
            for block in blocks {
                if let codeBlock = block.markup as? CodeBlock, codeBlock.language != "mermaid" {
                    let blockID = block.id
                    group.addTask {
                        let tokens = SyntaxHighlighter().tokenize(codeBlock.code, language: codeBlock.language)
                        let lines = HighlightedCodeView.splitIntoLines(tokens)
                        return (blockID, lines)
                    }
                }
            }
            var result: [UUID: [[Token]]] = [:]
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

    // MARK: - Snapshot cache

    @MainActor
    static func cachedSnapshot(for content: String) -> MarkdownRenderSnapshot? {
        MarkdownSnapshotCache.shared.object(forKey: content as NSString)?.snapshot
    }

    @MainActor
    static func cacheSnapshot(_ snapshot: MarkdownRenderSnapshot, for content: String) {
        MarkdownSnapshotCache.shared.setObject(
            MarkdownSnapshotBox(snapshot: snapshot),
            forKey: content as NSString
        )
    }

    // MARK: - Preprocessing

    private static func preprocessedChildren(for content: String) -> [any Markup] {
        let processedContent = LaTeXPreprocessor.process(content)
        let document = Document(parsing: processedContent)
        return Array(document.children)
    }
}

// MARK: - Block Node

struct MarkdownBlockNode: Identifiable {
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

private final class MarkdownParsedChildrenBox: NSObject {
    let children: [any Markup]

    init(children: [any Markup]) {
        self.children = children
    }
}

@MainActor
private final class MarkdownSnapshotCache {
    static let shared: NSCache<NSString, MarkdownSnapshotBox> = {
        let cache = NSCache<NSString, MarkdownSnapshotBox>()
        cache.countLimit = 128
        return cache
    }()
}

private final class MarkdownSnapshotBox: NSObject {
    let snapshot: MarkdownRenderSnapshot

    init(snapshot: MarkdownRenderSnapshot) {
        self.snapshot = snapshot
    }
}
