import Foundation
@preconcurrency import Markdown

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]
    let estimatedHeight: CGFloat?

    static let empty = MarkdownRenderSnapshot(blocks: [], estimatedHeight: nil)

    // MARK: - Async parse (no layout)

    static func parse(_ content: String, previousBlocks: [MarkdownBlockNode] = []) async -> Self {
        let children = await parsedChildren(for: content)
        let blocks = assignBlockIDs(children: children, reusingFrom: previousBlocks)
        return MarkdownRenderSnapshot(blocks: blocks, estimatedHeight: nil)
    }

    // MARK: - Async parse (with layout)

    static func parse(
        _ content: String,
        width: CGFloat,
        theme: MarkdownTheme,
        previousBlocks: [MarkdownBlockNode] = []
    ) async -> Self {
        let roundedWidth = roundedWidth(width)
        guard roundedWidth > 0 else {
            return await Self.parse(content, previousBlocks: previousBlocks)
        }

        let children = await parsedChildren(for: content)
        let blocks = assignBlockIDs(children: children, reusingFrom: previousBlocks)

        let heightKey = heightCacheKey(content: content, width: roundedWidth, theme: theme)
        let estimatedHeight: CGFloat = await MainActor.run {
            if let cached = MarkdownHeightCache.shared.object(forKey: heightKey as NSString) {
                return CGFloat(cached.floatValue)
            }
            let h = MarkdownHeightEstimator.estimate(blocks: blocks, width: roundedWidth, theme: theme)
            MarkdownHeightCache.shared.setObject(NSNumber(value: Double(h)), forKey: heightKey as NSString)
            return h
        }

        return MarkdownRenderSnapshot(blocks: blocks, estimatedHeight: estimatedHeight)
    }

    // MARK: - Sync parse (initial render, main actor)

    @MainActor
    static func parse(_ content: String, previousBlocks: [MarkdownBlockNode] = []) -> Self {
        let children = parsedChildrenSync(for: content)
        let blocks = assignBlockIDs(children: children, reusingFrom: previousBlocks)
        return MarkdownRenderSnapshot(blocks: blocks, estimatedHeight: nil)
    }

    static func roundedWidth(_ width: CGFloat) -> CGFloat {
        max((width * 2).rounded(.toNearestOrEven) / 2, 0)
    }

    // MARK: - ID assignment with reuse

    private static func assignBlockIDs(
        children: [any Markup],
        reusingFrom previous: [MarkdownBlockNode]
    ) -> [MarkdownBlockNode] {
        children.enumerated().map { index, child in
            let kind = String(describing: type(of: child))
            // Reuse UUID if previous block at same index has same kind
            let id: UUID
            if index < previous.count, previous[index].kind == kind {
                id = previous[index].id
            } else {
                id = UUID()
            }
            return MarkdownBlockNode(id: id, kind: kind, markup: child)
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

    // MARK: - Cache keys

    private static func heightCacheKey(content: String, width: CGFloat, theme: MarkdownTheme) -> String {
        "height|\(width)|\(theme.layoutSignature)|\(content)"
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

@MainActor
private final class MarkdownHeightCache {
    static let shared: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 256
        return cache
    }()
}

private final class MarkdownParsedChildrenBox: NSObject, @unchecked Sendable {
    let children: [any Markup]

    init(children: [any Markup]) {
        self.children = children
    }
}
