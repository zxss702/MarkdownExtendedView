import Foundation
import Markdown

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]
    let estimatedHeight: CGFloat?

    static let empty = MarkdownRenderSnapshot(blocks: [], estimatedHeight: nil)

    static func parse(_ content: String) async -> Self {
        let cacheKey = contentOnlyCacheKey(content)
        if let cached = await MainActor.run(resultType: MarkdownRenderSnapshot?.self, body: {
            MarkdownRenderSnapshotCache.shared.object(forKey: cacheKey as NSString)?.snapshot
        }) {
            return cached
        }

        let snapshot = MarkdownRenderSnapshot(
            blocks: await parsedBlocks(for: content),
            estimatedHeight: nil
        )

        await MainActor.run {
            MarkdownRenderSnapshotCache.shared.setObject(
                MarkdownRenderSnapshotBox(snapshot: snapshot),
                forKey: cacheKey as NSString
            )
        }

        return snapshot
    }

    static func parse(_ content: String, width: CGFloat, theme: MarkdownTheme) async -> Self {
        let roundedWidth = roundedWidth(width)
        guard roundedWidth > 0 else {
            return await Self.parse(content)
        }

        let cacheKey = snapshotCacheKey(content: content, width: roundedWidth, theme: theme)
        if let cached = await MainActor.run(resultType: MarkdownRenderSnapshot?.self, body: {
            MarkdownRenderSnapshotCache.shared.object(forKey: cacheKey as NSString)?.snapshot
        }) {
            return cached
        }

        let blocks = await parsedBlocks(for: content)
        let estimatedHeight = await MainActor.run {
            MarkdownHeightEstimator.estimate(blocks: blocks, width: roundedWidth, theme: theme)
        }
        let snapshot = MarkdownRenderSnapshot(
            blocks: blocks,
            estimatedHeight: estimatedHeight
        )

        await MainActor.run {
            MarkdownRenderSnapshotCache.shared.setObject(
                MarkdownRenderSnapshotBox(snapshot: snapshot),
                forKey: cacheKey as NSString
            )
        }

        return snapshot
    }

    @MainActor
    static func parse(_ content: String) -> Self {
        let cacheKey = contentOnlyCacheKey(content)
        if let cached = MarkdownRenderSnapshotCache.shared.object(forKey: cacheKey as NSString)?.snapshot {
            return cached
        }

        let snapshot = MarkdownRenderSnapshot(
            blocks: parsedBlocksSync(for: content),
            estimatedHeight: nil
        )

        MarkdownRenderSnapshotCache.shared.setObject(
            MarkdownRenderSnapshotBox(snapshot: snapshot),
            forKey: cacheKey as NSString
        )

        return snapshot
    }

    static func roundedWidth(_ width: CGFloat) -> CGFloat {
        max((width * 2).rounded(.toNearestOrEven) / 2, 0)
    }

    private static func parsedBlocks(for content: String) async -> [MarkdownBlockNode] {
        if let cached = await MainActor.run(resultType: [MarkdownBlockNode]?.self, body: {
            MarkdownParsedBlocksCache.shared.object(forKey: content as NSString)?.blocks
        }) {
            return cached
        }

        let blocks = makeBlocks(from: preprocessedChildren(for: content))

        await MainActor.run {
            MarkdownParsedBlocksCache.shared.setObject(
                MarkdownParsedBlocksBox(blocks: blocks),
                forKey: content as NSString
            )
        }

        return blocks
    }

    @MainActor
    private static func parsedBlocksSync(for content: String) -> [MarkdownBlockNode] {
        if let cached = MarkdownParsedBlocksCache.shared.object(forKey: content as NSString)?.blocks {
            return cached
        }

        let blocks = makeBlocks(from: preprocessedChildren(for: content))

        MarkdownParsedBlocksCache.shared.setObject(
            MarkdownParsedBlocksBox(blocks: blocks),
            forKey: content as NSString
        )

        return blocks
    }

    private static func makeBlocks(from children: [any Markup]) -> [MarkdownBlockNode] {
        var kindCounts: [String: Int] = [:]
        return children.map { child in
            let kind = String(describing: type(of: child))
            let occurrence = kindCounts[kind, default: 0]
            kindCounts[kind] = occurrence + 1
            return MarkdownBlockNode(
                id: .init(kind: kind, occurrence: occurrence),
                markup: child
            )
        }
    }

    private static func contentOnlyCacheKey(_ content: String) -> String {
        "content|\(content)"
    }

    private static func snapshotCacheKey(content: String, width: CGFloat, theme: MarkdownTheme) -> String {
        "layout|\(width)|\(theme.layoutSignature)|\(content)"
    }

    private static func preprocessedChildren(for content: String) -> [any Markup] {
        var processedContent = content
        let footnoteResult = FootnotePreprocessor().process(processedContent)
        processedContent = footnoteResult.processedMarkdown
        processedContent = LaTeXPreprocessor.process(processedContent)

        let document = Document(parsing: processedContent)
        return Array(document.children)
    }
}

struct MarkdownBlockNode: Identifiable, @unchecked Sendable {
    let id: MarkdownBlockIdentity
    let markup: any Markup
}

struct MarkdownBlockIdentity: Hashable, Sendable {
    let kind: String
    let occurrence: Int
}

@MainActor
private final class MarkdownParsedBlocksCache {
    static let shared: NSCache<NSString, MarkdownParsedBlocksBox> = {
        let cache = NSCache<NSString, MarkdownParsedBlocksBox>()
        cache.countLimit = 128
        return cache
    }()
}

@MainActor
private final class MarkdownRenderSnapshotCache {
    static let shared: NSCache<NSString, MarkdownRenderSnapshotBox> = {
        let cache = NSCache<NSString, MarkdownRenderSnapshotBox>()
        cache.countLimit = 128
        return cache
    }()
}

private final class MarkdownParsedBlocksBox: NSObject {
    let blocks: [MarkdownBlockNode]

    init(blocks: [MarkdownBlockNode]) {
        self.blocks = blocks
    }
}

private final class MarkdownRenderSnapshotBox: NSObject {
    let snapshot: MarkdownRenderSnapshot

    init(snapshot: MarkdownRenderSnapshot) {
        self.snapshot = snapshot
    }
}
