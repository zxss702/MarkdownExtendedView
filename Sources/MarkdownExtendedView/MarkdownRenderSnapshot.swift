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

    func reusingBlockIdentities(
        from previous: MarkdownRenderSnapshot,
        mode: MarkdownSnapshotReconciliationMode
    ) -> MarkdownRenderSnapshot {
        guard !blocks.isEmpty, !previous.blocks.isEmpty else {
            return self
        }

        var resolvedIDs = Array<MarkdownBlockIdentity?>(repeating: nil, count: blocks.count)
        var matchedPrevious = Array(repeating: false, count: previous.blocks.count)
        var matchedNext = Array(repeating: false, count: blocks.count)

        var lowerBound = 0
        while lowerBound < previous.blocks.count,
              lowerBound < blocks.count,
              previous.blocks[lowerBound].fingerprint == blocks[lowerBound].fingerprint {
            resolvedIDs[lowerBound] = previous.blocks[lowerBound].id
            matchedPrevious[lowerBound] = true
            matchedNext[lowerBound] = true
            lowerBound += 1
        }

        var previousUpper = previous.blocks.count - 1
        var nextUpper = blocks.count - 1
        while previousUpper >= lowerBound,
              nextUpper >= lowerBound,
              previous.blocks[previousUpper].fingerprint == blocks[nextUpper].fingerprint {
            resolvedIDs[nextUpper] = previous.blocks[previousUpper].id
            matchedPrevious[previousUpper] = true
            matchedNext[nextUpper] = true

            if previousUpper == 0 || nextUpper == 0 {
                break
            }
            previousUpper -= 1
            nextUpper -= 1
        }

        if mode == .streaming,
           lowerBound < previous.blocks.count,
           lowerBound < blocks.count,
           !matchedPrevious[lowerBound],
           !matchedNext[lowerBound],
           previous.blocks[lowerBound].canReuseIdentityWhenStreaming(to: blocks[lowerBound]) {
            resolvedIDs[lowerBound] = previous.blocks[lowerBound].id
            matchedPrevious[lowerBound] = true
            matchedNext[lowerBound] = true
        }

        var availablePreviousIDs: [MarkdownBlockFingerprint: [Int]] = [:]
        for index in previous.blocks.indices where !matchedPrevious[index] {
            availablePreviousIDs[previous.blocks[index].fingerprint, default: []].append(index)
        }

        for index in blocks.indices where !matchedNext[index] {
            let fingerprint = blocks[index].fingerprint
            guard var candidates = availablePreviousIDs[fingerprint],
                  let previousIndex = candidates.first else {
                continue
            }

            candidates.removeFirst()
            availablePreviousIDs[fingerprint] = candidates
            resolvedIDs[index] = previous.blocks[previousIndex].id
            matchedPrevious[previousIndex] = true
        }

        var usedIDs = Set<MarkdownBlockIdentity>()
        let resolvedBlocks = blocks.indices.map { index in
            let proposedID = resolvedIDs[index] ?? blocks[index].id
            let uniqueID = uniqueIdentity(for: proposedID, usedIDs: &usedIDs)
            return blocks[index].withIdentity(uniqueID)
        }

        return MarkdownRenderSnapshot(blocks: resolvedBlocks, estimatedHeight: estimatedHeight)
    }

    private func uniqueIdentity(
        for identity: MarkdownBlockIdentity,
        usedIDs: inout Set<MarkdownBlockIdentity>
    ) -> MarkdownBlockIdentity {
        guard usedIDs.contains(identity) else {
            usedIDs.insert(identity)
            return identity
        }

        var occurrence = identity.occurrence + 1
        while true {
            let candidate = MarkdownBlockIdentity(
                kind: identity.kind,
                occurrence: occurrence,
                digest: identity.digest
            )
            if !usedIDs.contains(candidate) {
                usedIDs.insert(candidate)
                return candidate
            }
            occurrence += 1
        }
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
                fingerprint: fingerprint,
                animationKind: MarkdownBlockAnimationKind(markup: child),
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

enum MarkdownSnapshotReconciliationMode: Sendable {
    case exact
    case streaming
}

struct MarkdownBlockNode: Identifiable, @unchecked Sendable {
    let id: MarkdownBlockIdentity
    fileprivate let fingerprint: MarkdownBlockFingerprint
    let animationKind: MarkdownBlockAnimationKind
    let markup: any Markup

    fileprivate func withIdentity(_ id: MarkdownBlockIdentity) -> MarkdownBlockNode {
        MarkdownBlockNode(
            id: id,
            fingerprint: fingerprint,
            animationKind: animationKind,
            markup: markup
        )
    }

    fileprivate func canReuseIdentityWhenStreaming(to next: MarkdownBlockNode) -> Bool {
        guard animationKind == .text, next.animationKind == .text else {
            return false
        }

        switch (markup, next.markup) {
        case let (previous as Heading, current as Heading):
            return previous.level == current.level &&
                MarkdownBlockNode.hasGrowingTextPrefix(from: previous.plainText, to: current.plainText)

        case let (previous as Paragraph, current as Paragraph):
            return MarkdownBlockNode.hasGrowingTextPrefix(from: previous.plainText, to: current.plainText)

        case let (previous as CodeBlock, current as CodeBlock):
            return previous.language == current.language &&
                previous.language != "mermaid" &&
                MarkdownBlockNode.hasGrowingTextPrefix(from: previous.code, to: current.code)

        case let (previous as HTMLBlock, current as HTMLBlock):
            return MarkdownBlockNode.hasGrowingTextPrefix(from: previous.rawHTML, to: current.rawHTML)

        default:
            return false
        }
    }

    private static func hasGrowingTextPrefix(from previous: String, to current: String) -> Bool {
        guard !previous.isEmpty, current.count >= previous.count else {
            return false
        }
        if current.hasPrefix(previous) {
            return true
        }

        let commonPrefixCount = zip(previous, current).prefix { $0 == $1 }.count
        let requiredPrefixCount: Int
        if previous.count < 12 {
            requiredPrefixCount = max(1, previous.count - 2)
        } else {
            requiredPrefixCount = Int((Double(previous.count) * 0.8).rounded(.down))
        }
        return commonPrefixCount >= requiredPrefixCount
    }
}

struct MarkdownBlockIdentity: Hashable, Sendable {
    let kind: String
    let occurrence: Int
    let digest: Int
}

enum MarkdownBlockAnimationKind: Sendable, Equatable {
    case text
    case nonText

    init(markup: any Markup) {
        switch markup {
        case _ as Heading:
            self = .text

        case let paragraph as Paragraph:
            let plainText = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") ||
                MarkdownBlockAnimationKind.containsImage(in: paragraph) {
                self = .nonText
            } else {
                self = .text
            }

        case let codeBlock as CodeBlock:
            self = codeBlock.language == "mermaid" ? .nonText : .text

        case _ as HTMLBlock:
            self = .text

        default:
            self = .nonText
        }
    }

    private static func containsImage(in markup: any Markup) -> Bool {
        for child in markup.children {
            if child is Markdown.Image {
                return true
            }
            if containsImage(in: child) {
                return true
            }
        }
        return false
    }
}

private struct MarkdownBlockFingerprint: Hashable, Sendable {
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
