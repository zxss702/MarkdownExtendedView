// MarkdownFlattener.swift
//  MarkdownExtendedView
//
//  Synchronous one-pass conversion of a parsed Markdown document into
//  the flattened `[MDBlock]` render model. Runs inside `MarkdownView.init`;
//  no async work is ever scheduled from here.
//
//  Paragraphs that contain view-level elements (images, code references,
//  `$$..$$` block formulas) are split into multiple sibling blocks so the
//  renderer body is a pure `switch` with no flow layout pass.

import Foundation
@preconcurrency import Markdown

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownFlattener {

    /// Parses `content` and flattens it into blocks, reusing ids from
    /// `previousBlocks` so streaming updates keep view identity stable.
    /// Inline LaTeX and code-reference icons are embedded as lazily
    /// resolved `MDBakedInlineImage` payloads — their typesetting/icon
    /// lookup happens on first render, not here.
    @MainActor
    static func flatten(_ content: String, baseURL: URL?, previousBlocks: [MDBlock]) -> [MDBlock] {
        let document = Document(parsing: content, options: [.disableSmartOpts, .disableSourcePosOpts])
        let pool = ReusePool(previous: previousBlocks)
        return flattenBlocks(document.children, previous: previousBlocks, baseURL: baseURL, pool: pool)
    }

    // MARK: - Blocks

    private static func flattenBlocks(
        _ children: MarkupChildren,
        previous: [MDBlock],
        baseURL: URL?,
        pool: ReusePool
    ) -> [MDBlock] {
        var blocks: [MDBlock] = []
        blocks.reserveCapacity(previous.count)
        for child in children {
            switch child {
            case let paragraph as Paragraph:
                // A paragraph may emit several blocks when it contains
                // view-level pieces (image / code reference / `$$..$$`).
                for content in paragraphContents(paragraph, baseURL: baseURL) {
                    appendBlock(content, into: &blocks, previous: previous, pool: pool)
                }
            default:
                guard let content = blockContent(
                    child,
                    previous: blocks.count < previous.count ? previous[blocks.count] : nil,
                    baseURL: baseURL,
                    pool: pool
                ) else {
                    continue
                }
                appendBlock(content, into: &blocks, previous: previous, pool: pool)
            }
        }
        return blocks
    }

    private static func appendBlock(
        _ content: MDBlockContent,
        into blocks: inout [MDBlock],
        previous: [MDBlock],
        pool: ReusePool
    ) {
        let signature = MDBlock.signature(of: content)
        let previousAtPosition = blocks.count < previous.count ? previous[blocks.count] : nil
        let id = pool.reuseID(kind: content.kind, signature: signature, previous: previousAtPosition)
        blocks.append(MDBlock(id: id, kind: content.kind, signature: signature, content: content))
    }

    private static func blockContent(
        _ markup: any Markup,
        previous: MDBlock?,
        baseURL: URL?,
        pool: ReusePool
    ) -> MDBlockContent? {
        switch markup {
        case let heading as Heading:
            return .heading(
                level: heading.level,
                flattenInline(
                    heading,
                    baseURL: baseURL,
                    sourcePrefix: String(repeating: "#", count: heading.level) + " "
                )
            )
        case let codeBlock as CodeBlock:
            return flattenCodeBlock(codeBlock)
        case let blockQuote as BlockQuote:
            let previousChildren: [MDBlock]
            if case .blockQuote(let children)? = previous?.content {
                previousChildren = children
            } else {
                previousChildren = []
            }
            return .blockQuote(
                children: flattenBlocks(blockQuote.children, previous: previousChildren, baseURL: baseURL, pool: pool)
            )
        case let orderedList as OrderedList:
            return flattenOrderedList(orderedList, previous: previous, baseURL: baseURL, pool: pool)
        case let unorderedList as UnorderedList:
            return flattenUnorderedList(unorderedList, previous: previous, baseURL: baseURL, pool: pool)
        case let table as Markdown.Table:
            return .table(flattenTable(table, baseURL: baseURL))
        case is ThematicBreak:
            return .thematicBreak
        case let html as HTMLBlock:
            return .htmlBlock(rawHTML: html.rawHTML)
        default:
            return nil
        }
    }

    // MARK: - Code blocks / mermaid

    private static func flattenCodeBlock(_ codeBlock: CodeBlock) -> MDBlockContent {
        let code = codeBlock.code
        if codeBlock.language?.lowercased() == "mermaid" {
            return .mermaid(code: code)
        }
        let normalized = code.trimmingCharacters(in: .newlines)
        let lines = HighlightedCodeView.resolveLines(code: normalized, language: codeBlock.language)
        return .codeBlock(MDCodeBlock(code: normalized, language: codeBlock.language, lines: lines))
    }

    // MARK: - Lists

    private static func flattenOrderedList(
        _ list: OrderedList,
        previous: MDBlock?,
        baseURL: URL?,
        pool: ReusePool
    ) -> MDBlockContent {
        let previousItems: [MDListItem]
        if case .orderedList(_, let items)? = previous?.content {
            previousItems = items
        } else {
            previousItems = []
        }
        return .orderedList(
            startIndex: Int(list.startIndex),
            items: flattenListItems(Array(list.listItems), previous: previousItems, baseURL: baseURL, pool: pool)
        )
    }

    private static func flattenUnorderedList(
        _ list: UnorderedList,
        previous: MDBlock?,
        baseURL: URL?,
        pool: ReusePool
    ) -> MDBlockContent {
        let previousItems: [MDListItem]
        if case .unorderedList(let items)? = previous?.content {
            previousItems = items
        } else {
            previousItems = []
        }
        return .unorderedList(
            items: flattenListItems(Array(list.listItems), previous: previousItems, baseURL: baseURL, pool: pool)
        )
    }

    private static func flattenListItems(
        _ listItems: [ListItem],
        previous: [MDListItem],
        baseURL: URL?,
        pool: ReusePool
    ) -> [MDListItem] {
        listItems.enumerated().map { index, item in
            let previousItem = index < previous.count ? previous[index] : nil
            let children = flattenBlocks(
                item.children,
                previous: previousItem?.children ?? [],
                baseURL: baseURL,
                pool: pool
            )
            let checkbox: MDCheckbox?
            switch item.checkbox {
            case .checked: checkbox = .checked
            case .unchecked: checkbox = .unchecked
            case nil: checkbox = nil
            }
            let id = pool.reuseItemID(previous: previousItem)
            return MDListItem(id: id, checkbox: checkbox, children: children)
        }
    }

    // MARK: - Tables

    private static func flattenTable(_ table: Markdown.Table, baseURL: URL?) -> MDTable {
        let head = table.head.cells.map { flattenInline($0, baseURL: baseURL) }
        let rows = table.body.rows.map { row in
            row.cells.map { flattenInline($0, baseURL: baseURL) }
        }
        return MDTable(
            alignments: Array(table.columnAlignments),
            head: Array(head),
            rows: rows.map { Array($0) }
        )
    }

    // MARK: - Inline pieces (transient)

    /// Transient semantic piece — only exists inside the flattener while
    /// inline markup is being walked; it is folded into the one
    /// `AttributedString` or split into sibling blocks before leaving
    /// this file.
    private enum Piece {
        case text(String, InlineTextStyle, link: String?)
        case latex(String, isBlock: Bool)
        case image(MDImage)
        /// `raw` is the canonical POSIX reference with backticks
        /// (`` `/abs/path:<46>-<58>` ``) — the selection copy payload.
        case codeReference(MCodeReference, raw: String)
        case newLine
    }

    /// Single recursive pass producing the flat piece sequence for an
    /// inline container (paragraph, heading, table cell…).
    private static func collectPieces(_ container: any Markup) -> [Piece] {
        var pieces: [Piece] = []
        for child in container.children {
            appendInline(child, style: [], linkDestination: nil, into: &pieces)
        }
        return pieces
    }

    private static func appendInline(
        _ markup: any Markup,
        style: InlineTextStyle,
        linkDestination: String?,
        into pieces: inout [Piece]
    ) {
        switch markup {
        case let text as Markdown.Text:
            appendTextPieces(text.string, style: style, linkDestination: linkDestination, into: &pieces)

        case let strong as Strong:
            for child in strong.children {
                appendInline(child, style: style.union(.bold), linkDestination: linkDestination, into: &pieces)
            }

        case let emphasis as Emphasis:
            for child in emphasis.children {
                appendInline(child, style: style.union(.italic), linkDestination: linkDestination, into: &pieces)
            }

        case let strikethrough as Strikethrough:
            for child in strikethrough.children {
                appendInline(child, style: style.union(.strikethrough), linkDestination: linkDestination, into: &pieces)
            }

        case let code as InlineCode:
            if let references = parseMCodeReferences(from: code.code), references.count == 1 {
                // Copy payload keeps the backticks and the canonical
                // POSIX form: `` `/abs/path:<46>-<58>` `` — never the
                // `file://` source spelling.
                pieces.append(.codeReference(references[0], raw: "`\(references[0].referenceString)`"))
            } else {
                pieces.append(.text(code.code, style.union(.code), link: linkDestination))
            }

        case let link as Markdown.Link:
            for child in link.children {
                appendInline(child, style: style, linkDestination: link.destination, into: &pieces)
            }

        case is SoftBreak, is LineBreak:
            pieces.append(.newLine)

        case let image as Markdown.Image:
            pieces.append(.image(MDImage(source: image.source, altText: image.plainText)))

        case let inlineHTML as InlineHTML:
            pieces.append(.text(inlineHTML.rawHTML, style, link: linkDestination))

        default:
            if let convertible = markup as? PlainTextConvertibleMarkup {
                appendTextPieces(convertible.plainText, style: style, linkDestination: linkDestination, into: &pieces)
            }
        }
    }

    /// Splits `$..$` / `$$..$$` LaTeX segments out of a raw text run.
    private static func appendTextPieces(
        _ string: String,
        style: InlineTextStyle,
        linkDestination: String?,
        into pieces: inout [Piece]
    ) {
        guard !string.isEmpty else { return }
        guard string.contains("$") else {
            pieces.append(.text(string, style, link: linkDestination))
            return
        }
        for segment in LaTeXPreprocessor.extractSegments(from: string) {
            switch segment {
            case .text(let text):
                pieces.append(.text(text, style, link: linkDestination))
            case .latex(let latex, let isBlock):
                pieces.append(.latex(latex, isBlock: isBlock))
            }
        }
    }

    // MARK: - Paragraph → sibling blocks

    /// Only true block-level views split the paragraph into siblings:
    /// `a ![img] b $$..$$ c` → `[.text, .image, .text, .latexBlock, .text]`.
    /// Inline LaTeX and code references stay inline as attachments/links
    /// inside the `AttributedString`.
    private static func paragraphContents(_ paragraph: Paragraph, baseURL: URL?) -> [MDBlockContent] {
        var contents: [MDBlockContent] = []
        var builder = InlineStringBuilder(baseURL: baseURL)

        for piece in collectPieces(paragraph) {
            switch piece {
            case .image(let image):
                if let inline = builder.finishInline() {
                    contents.append(.text(inline))
                }
                contents.append(.image(image))

            case .latex(let source, isBlock: true):
                if let inline = builder.finishInline() {
                    contents.append(.text(inline))
                }
                contents.append(.latexBlock(source))

            case .latex(let source, isBlock: false):
                builder.appendInlineLatex(source)

            case .codeReference(let reference, let raw):
                builder.appendCodeReference(reference, raw: raw)

            case .text(let string, let style, let link):
                builder.appendText(string, style: style, link: link)

            case .newLine:
                builder.appendNewline()
            }
        }

        if let inline = builder.finishInline() {
            contents.append(.text(inline))
        }
        return contents
    }

    // MARK: - Inline model (headings, table cells)

    /// Containers that cannot host views (headings, table cells) fold
    /// images into `[alt]` text; LaTeX and code references stay inline.
    /// `sourcePrefix`/`sourceSuffix` wrap the block's markdown-source
    /// copy payload (e.g. `#` markers on a heading).
    static func flattenInline(
        _ container: any Markup,
        baseURL: URL?,
        sourcePrefix: String? = nil,
        sourceSuffix: String? = nil
    ) -> AttributedString {
        var builder = InlineStringBuilder(baseURL: baseURL)
        for piece in collectPieces(container) {
            switch piece {
            case .text(let string, let style, let link):
                builder.appendText(string, style: style, link: link)
            case .newLine:
                builder.appendNewline()
            case .latex(let source, _):
                builder.appendInlineLatex(source)
            case .image(let image):
                builder.appendText(
                    "[\(image.altText)]",
                    style: [],
                    link: nil,
                    sourcePrefix: "!",
                    sourceSuffix: "(\(image.source ?? ""))"
                )
            case .codeReference(let reference, let raw):
                builder.appendCodeReference(reference, raw: raw)
            }
        }
        builder.applySourceWrapper(prefix: sourcePrefix, suffix: sourceSuffix)
        return builder.finishInline() ?? AttributedString()
    }

    // MARK: - Inline string builder

    /// Folds pieces into ONE `AttributedString`: text/emphasis/links as
    /// attributes, inline LaTeX and code references as lazy embedded
    /// image payloads (a formula image, an icon + blue link label), plus
    /// the run-encoded `MarkdownBlockMappingsAttribute` selection payload.
    private struct InlineStringBuilder {
        let baseURL: URL?
        private(set) var attributed = AttributedString()
        private(set) var mappings: [GlobalSelectionCache.CharacterMapping] = []
        /// Joined mapping characters, accumulated alongside `mappings`
        /// so `mdSignature` is a stored read instead of a re-join.
        private var signatureText = ""

        /// Inline formulas are typeset at a fixed default size — the
        /// theme is a render-time concern the flatten pass cannot see.
        private static let inlineMathFontSize: CGFloat = 14
        private static let codeReferenceIconSize: CGFloat = 13

        mutating func appendText(
            _ string: String,
            style: InlineTextStyle,
            link: String?,
            sourcePrefix: String = "",
            sourceSuffix: String = ""
        ) {
            guard !string.isEmpty else { return }
            var run = AttributedString(string)
            let intent = style.presentationIntent
            if !intent.isEmpty {
                run.inlinePresentationIntent = intent
            }
            let resolved = resolveURL(link, baseURL: baseURL)
            if let resolved {
                run.link = resolved
            }
            attributed.append(run)
            signatureText += string
            let linkString = resolved?.absoluteString

            // Markdown-source copy payload: emphasis/link markers ride
            // on the run's boundary glyphs (`source`), so a partial
            // selection drops the markers of any glyph it excludes.
            var sourcePrefix = sourcePrefix
            var sourceSuffix = sourceSuffix
            if style.contains(.code) { sourcePrefix += "`"; sourceSuffix = "`" + sourceSuffix }
            if style.contains(.strikethrough) { sourcePrefix += "~~"; sourceSuffix = "~~" + sourceSuffix }
            if style.contains(.italic) { sourcePrefix += "*"; sourceSuffix = "*" + sourceSuffix }
            if style.contains(.bold) { sourcePrefix += "**"; sourceSuffix = "**" + sourceSuffix }
            if let link {
                sourcePrefix = "[" + sourcePrefix
                sourceSuffix += "](\(link))"
            }

            guard !sourcePrefix.isEmpty || !sourceSuffix.isEmpty else {
                // One run entry covers every glyph — the per-glyph
                // slicing happens lazily in `MDGlyphCursor`.
                mappings.append(.init(
                    char: string[...],
                    glyphCount: string.count,
                    slicesText: true,
                    link: linkString
                ))
                return
            }

            let characters = Array(string)
            let last = characters.count - 1
            for (index, character) in characters.enumerated() {
                var source = String(character)
                if index == 0 { source = sourcePrefix + source }
                if index == last { source += sourceSuffix }
                mappings.append(.init(
                    char: String(character)[...],
                    link: linkString,
                    source: source == String(character) ? nil : source[...]
                ))
            }
        }

        /// Wraps the block's copy source — heading `#` markers, list
        /// indentation, … — onto the first/last mapping entries. A
        /// `slicesText` run cannot carry a `source`, so it is split:
        /// the boundary glyph becomes its own entry.
        mutating func applySourceWrapper(prefix: String?, suffix: String?) {
            if let prefix, let index = mappings.firstIndex(where: { $0.glyphCount > 0 }) {
                let mapping = mappings[index]
                if mapping.slicesText {
                    let first = mapping.char[mapping.char.startIndex]
                    var split: [GlobalSelectionCache.CharacterMapping] = [
                        .init(
                            char: String(first)[...],
                            link: mapping.link,
                            source: (prefix + String(first))[...]
                        )
                    ]
                    let rest = mapping.char.dropFirst()
                    if !rest.isEmpty {
                        split.append(.init(
                            char: rest,
                            glyphCount: mapping.glyphCount - 1,
                            slicesText: true,
                            link: mapping.link
                        ))
                    }
                    mappings.replaceSubrange(index...index, with: split)
                } else {
                    mappings[index] = GlobalSelectionCache.CharacterMapping(
                        char: mapping.char,
                        glyphCount: mapping.glyphCount,
                        group: mapping.group,
                        isLineBreak: mapping.isLineBreak,
                        link: mapping.link,
                        richImage: mapping.richImage,
                        source: (prefix + (mapping.source ?? mapping.char))[...]
                    )
                }
            }
            if let suffix, let index = mappings.lastIndex(where: { $0.glyphCount > 0 }) {
                let mapping = mappings[index]
                if mapping.slicesText {
                    let last = mapping.char[mapping.char.index(before: mapping.char.endIndex)]
                    var split: [GlobalSelectionCache.CharacterMapping] = []
                    let rest = mapping.char.dropLast()
                    if !rest.isEmpty {
                        split.append(.init(
                            char: rest,
                            glyphCount: mapping.glyphCount - 1,
                            slicesText: true,
                            link: mapping.link
                        ))
                    }
                    split.append(.init(
                        char: String(last)[...],
                        link: mapping.link,
                        source: (String(last) + suffix)[...]
                    ))
                    mappings.replaceSubrange(index...index, with: split)
                } else {
                    mappings[index] = GlobalSelectionCache.CharacterMapping(
                        char: mapping.char,
                        glyphCount: mapping.glyphCount,
                        group: mapping.group,
                        isLineBreak: mapping.isLineBreak,
                        link: mapping.link,
                        richImage: mapping.richImage,
                        source: ((mapping.source ?? mapping.char) + suffix)[...]
                    )
                }
            }
        }

        mutating func appendNewline() {
            attributed.append(AttributedString("\n"))
            signatureText.append("\n")
            mappings.append(.init(char: "\n", glyphCount: 0, isLineBreak: true))
        }

        /// `$..$` — the typeset is deferred to first render via a lazy
        /// `.inlineMath` payload so `init` stays cheap. Render/copy
        /// resolves it synchronously; parse failures degrade to the
        /// literal `$..$` source so content is never lost.
        mutating func appendInlineLatex(_ latex: String) {
            let baked = MDBakedInlineImage(
                payload: .inlineMath(latex: latex, fontSize: Self.inlineMathFontSize),
                sizing: .fixed
            )
            var run = AttributedString("\u{FFFC}")
            var container = AttributeContainer()
            container[MarkdownInlineImageKey.self] = baked
            run.mergeAttributes(container)
            attributed.append(run)
            let payload = "$\(latex)$"
            signatureText += payload
            mappings.append(.init(char: payload[...], richImage: baked))
        }

        /// A code reference renders inline like a link with a leading
        /// icon: `[icon] FileName.swift:46-58`, tinted system blue and
        /// carrying a `.link` back to the full `file://…:lines` URL so
        /// taps route to `onMCodeReferenceTap`. All its glyphs share one
        /// selection group so it selects atomically, copying `raw`.
        /// The icon resolves lazily at first render.
        mutating func appendCodeReference(_ reference: MCodeReference, raw: String) {
            let group = "coderef\(mappings.count)"
            let label = Self.displayName(for: reference)
            let linkURL = Self.linkURL(for: reference)
            let linkString = linkURL?.absoluteString

            let baked = MDBakedInlineImage(
                payload: .codeRefIcon(reference, size: Self.codeReferenceIconSize),
                sizing: .fontScaled
            )
            var iconRun = AttributedString("\u{FFFC}")
            var container = AttributeContainer()
            container[MarkdownInlineImageKey.self] = baked
            iconRun.mergeAttributes(container)
            attributed.append(iconRun)
            // The group's first member carries the copy payload.
            signatureText += raw
            mappings.append(.init(
                char: raw[...],
                group: group,
                link: linkString
            ))

            var labelRun = AttributedString(label)
            labelRun.foregroundColor = .systemBlue
            labelRun.inlinePresentationIntent = .code
            if let linkURL {
                labelRun.link = linkURL
            }
            attributed.append(labelRun)
            // Group members contribute no characters — the merged slice
            // copies the raw payload held by the icon glyph. One run
            // entry covers the whole label.
            mappings.append(.init(
                char: "",
                glyphCount: label.count,
                group: group,
                link: linkString
            ))
        }

        /// Returns nil when nothing was accumulated.
        mutating func finishInline() -> AttributedString? {
            guard !attributed.characters.isEmpty else { return nil }
            var container = AttributeContainer()
            container[MarkdownBakedMappingsKey.self] = mappings
            container[MarkdownBakedSignatureKey.self] = "m:" + signatureText
            attributed.mergeAttributes(container)
            return attributed
        }

        private func resolveURL(_ destination: String?, baseURL: URL?) -> URL? {
            guard let destination, let url = URL(string: destination) else {
                return nil
            }
            if url.scheme == nil, let baseURL {
                return URL(string: destination, relativeTo: baseURL)?.absoluteURL
            }
            return url
        }

        /// `FileName.swift:46-58` — matches the link payload format the
        /// tap handler parses back (`path:range` suffix).
        private static func displayName(for reference: MCodeReference) -> String {
            reference.fileName + lineRangeSuffix(for: reference)
        }

        /// `file:///path/name.swift:46-58` — `:` survives inside file-URL
        /// paths, so the tap handler can parse line ranges back out.
        private static func linkURL(for reference: MCodeReference) -> URL? {
            URL(fileURLWithPath: reference.url.path(percentEncoded: false)
                + lineRangeSuffix(for: reference))
        }

        private static func lineRangeSuffix(for reference: MCodeReference) -> String {
            let ranges = reference.lineRanges
            guard !ranges.isEmpty else { return "" }
            return ":" + ranges
                .map { range in
                    range.lowerBound == range.upperBound
                        ? "\(range.lowerBound)"
                        : "\(range.lowerBound)-\(range.upperBound)"
                }
                .joined(separator: ",")
        }


    }
}

// MARK: - ID reuse

private final class ReusePool {
    private var usedIDs = Set<UUID>()
    private var idsBySignature: [String: [UUID]]

    init(previous: [MDBlock]) {
        var map: [String: [UUID]] = [:]
        for block in previous {
            map[block.signature, default: []].append(block.id)
        }
        idsBySignature = map
    }

    /// Reuse the previous block's id when the block at the same output
    /// position has the same kind; otherwise fall back to a signature
    /// match; otherwise mint a fresh id.
    func reuseID(kind: String, signature: String, previous: MDBlock?) -> UUID {
        if let previous, previous.kind == kind, !usedIDs.contains(previous.id) {
            usedIDs.insert(previous.id)
            return previous.id
        }
        if var queue = idsBySignature[signature],
           let index = queue.firstIndex(where: { !usedIDs.contains($0) }) {
            let id = queue[index]
            queue.remove(at: index)
            idsBySignature[signature] = queue
            usedIDs.insert(id)
            return id
        }
        let id = UUID()
        usedIDs.insert(id)
        return id
    }

    /// List-item ids follow the same position rule; a fresh id when the
    /// slot is new or already claimed.
    func reuseItemID(previous: MDListItem?) -> UUID {
        if let previous, !usedIDs.contains(previous.id) {
            usedIDs.insert(previous.id)
            return previous.id
        }
        let id = UUID()
        usedIDs.insert(id)
        return id
    }
}
