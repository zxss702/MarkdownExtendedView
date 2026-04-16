import Foundation
import Markdown

struct MarkdownRenderSnapshot: Sendable {
    let blocks: [MarkdownBlockNode]

    static func parse(_ content: String) async -> Self {
        if let cached = await MainActor.run(resultType: MarkdownRenderSnapshot?.self, body: {
            return MarkdownRenderSnapshotCache.shared.object(forKey: content as NSString)?.snapshot
        }) {
            return cached
        }
        
        var processedContent = content
        let footnoteResult = FootnotePreprocessor().process(processedContent)
        processedContent = footnoteResult.processedMarkdown
        processedContent = LaTeXPreprocessor.process(processedContent)

        let document = Document(parsing: processedContent)
        let snapshot = MarkdownRenderSnapshot(
            blocks: makeBlocks(from: Array(document.children))
        )
        await MainActor.run {
            MarkdownRenderSnapshotCache.shared.setObject(
                MarkdownRenderSnapshotBox(snapshot: snapshot),
                forKey: content as NSString
            )
        }
        return snapshot
    }
    
    @MainActor
    static func parse(_ content: String) -> Self {
        if let cached = MarkdownRenderSnapshotCache.shared.object(forKey: content as NSString)?.snapshot {
            return cached
        }
        
        var processedContent = content
        let footnoteResult = FootnotePreprocessor().process(processedContent)
        processedContent = footnoteResult.processedMarkdown
        processedContent = LaTeXPreprocessor.process(processedContent)

        let document = Document(parsing: processedContent)
        let snapshot = MarkdownRenderSnapshot(
            blocks: makeBlocks(from: Array(document.children))
        )
        
        MarkdownRenderSnapshotCache.shared.setObject(
            MarkdownRenderSnapshotBox(snapshot: snapshot),
            forKey: content as NSString
        )
        
        return snapshot
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

private final class MarkdownRenderSnapshotCache {
    @MainActor static let shared: NSCache<NSString, MarkdownRenderSnapshotBox> = {
        let cache = NSCache<NSString, MarkdownRenderSnapshotBox>()
        cache.countLimit = 128
        return cache
    }()
}

private final class MarkdownRenderSnapshotBox: NSObject {
    let snapshot: MarkdownRenderSnapshot

    init(snapshot: MarkdownRenderSnapshot) {
        self.snapshot = snapshot
    }
}
