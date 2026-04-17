import Foundation
import Markdown

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]
    let estimatedHeight: CGFloat?

    static func parse(_ content: String) async -> Self {
        await MainActor.run {
            Self.parse(content)
        }
    }

    static func parse(_ content: String, width: CGFloat, theme: MarkdownTheme) async -> Self {
        let roundedWidth = roundedWidth(width)
        guard roundedWidth > 0 else {
            return await MainActor.run {
                Self.parse(content)
            }
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
        var counts: [MarkdownBlockFingerprint: Int] = [:]

        return children.map { child in
            let fingerprint = MarkdownBlockFingerprint(markup: child)
            let occurrence = counts[fingerprint, default: 0]
            counts[fingerprint] = occurrence + 1

            return MarkdownBlockNode(
                id: .init(
                    kind: fingerprint.kind,
                    occurrence: occurrence,
                    digest: fingerprint.digest
                ),
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
    let digest: Int
}

private struct MarkdownBlockFingerprint: Hashable {
    let kind: String
    let digest: Int

    init(markup: any Markup) {
        kind = String(describing: type(of: markup))

        var hasher = Hasher()
        hasher.combine(kind)

        switch markup {
        case let heading as Heading:
            hasher.combine(heading.level)
            hasher.combine(heading.plainText)
        case let paragraph as Paragraph:
            hasher.combine(paragraph.plainText)
        case let codeBlock as CodeBlock:
            hasher.combine(codeBlock.language)
            hasher.combine(codeBlock.code)
        case let blockQuote as BlockQuote:
            hasher.combine(blockQuote.childCount)
            hasher.combine(String(describing: blockQuote))
        case let orderedList as OrderedList:
            hasher.combine(orderedList.childCount)
            hasher.combine(String(describing: orderedList))
        case let unorderedList as UnorderedList:
            hasher.combine(unorderedList.childCount)
            hasher.combine(String(describing: unorderedList))
        case let table as Markdown.Table:
            hasher.combine(String(describing: table))
        case let htmlBlock as HTMLBlock:
            hasher.combine(htmlBlock.rawHTML)
        default:
            hasher.combine(String(describing: markup))
        }

        digest = hasher.finalize()
    }
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
