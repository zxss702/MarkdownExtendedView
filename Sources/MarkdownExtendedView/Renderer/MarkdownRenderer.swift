// MarkdownRenderer.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import Markdown

/// Renders a parsed Markdown document to SwiftUI views.
struct MarkdownRenderer: View {

    let snapshot: MarkdownRenderSnapshot
    let theme: MarkdownTheme
    let baseURL: URL?

    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        LazyVStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
            ForEach(snapshot.blocks) { block in
                renderBlock(block.markup)
            }
        }
        .lineSpacing(theme.paragraphSpacing)
    }

    // MARK: - Block Rendering

    private func renderBlock(_ markup: any Markup) -> AnyView {
        if let heading = markup as? Heading {
            return AnyView(renderHeading(heading))
        } else if let paragraph = markup as? Paragraph {
            return AnyView(renderParagraph(paragraph))
        } else if let codeBlock = markup as? CodeBlock {
            return AnyView(renderCodeBlock(codeBlock))
        } else if let blockQuote = markup as? BlockQuote {
            return AnyView(renderBlockQuote(blockQuote))
        } else if let orderedList = markup as? OrderedList {
            return AnyView(renderOrderedList(orderedList))
        } else if let unorderedList = markup as? UnorderedList {
            return AnyView(renderUnorderedList(unorderedList))
        } else if let table = markup as? Markdown.Table {
            return AnyView(renderTable(table))
        } else if markup is ThematicBreak {
            return AnyView(Divider().padding(.vertical, 8))
        } else if let htmlBlock = markup as? HTMLBlock {
            return AnyView(
                SwiftUI.Text(htmlBlock.rawHTML)
                    .font(theme.codeSwiftUIFont)
                    .foregroundColor(theme.secondaryTextColor)
                    .selectionTextPassThrough()
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func renderHeading(_ heading: Heading) -> some View {
        renderInlineChildren(heading)
            .font(theme.headingSwiftUIFont(level: heading.level))
            .foregroundColor(theme.textColor)
            .padding(.top, heading.level == 1 ? 16 : 8)
            .padding(.bottom, 4)
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func renderParagraph(_ paragraph: Paragraph) -> some View {
        // Check if this paragraph contains only a display LaTeX block
        let plainText = paragraph.plainText
        if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") {
            // This is a display LaTeX block
            let latex = String(plainText.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            LaTeXView(latex: latex, isBlock: true, theme: theme)
        } else {
            renderInlineChildren(paragraph)
                .font(theme.bodySwiftUIFont)
                .foregroundColor(theme.textColor)
        }
    }

    // MARK: - Code Block

    @ViewBuilder
    private func renderCodeBlock(_ codeBlock: CodeBlock) -> some View {
        if codeBlock.language == "mermaid" {
            renderMermaidBlock(codeBlock)
        } else {
            renderRegularCodeBlock(codeBlock)
        }
    }

    @ViewBuilder
    private func renderMermaidBlock(_ codeBlock: CodeBlock) -> some View {
        MermaidView(code: codeBlock.code, theme: theme)
    }

    @ViewBuilder
    private func renderRegularCodeBlock(_ codeBlock: CodeBlock) -> some View {
        Group {
            if codeBlock.language != nil {
                HighlightedCodeView(
                    code: codeBlock.code,
                    language: codeBlock.language,
                    theme: theme
                )
            } else {
                Text(codeBlock.code.trimmingCharacters(in: .newlines))
                    .font(theme.codeBlockSwiftUIFont)
                    .foregroundColor(theme.textColor)
            }
        }
        .modifier(CodeBlockContainerModifier(theme: theme, isInteractive: false))
    }

    @ViewBuilder
    private func renderMCodeReferences(_ references: [MCodeReference]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                MCodeReferenceBlockView(
                    reference: reference,
                    theme: theme,
                    tapHandler: MCodeReferenceHandler
                )
            }
        }
    }

    // MARK: - Block Quote

    @ViewBuilder
    private func renderBlockQuote(_ blockQuote: BlockQuote) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.blockQuoteBorderColor)
                .frame(width: 4)

            LazyVStack(alignment: .leading, spacing: theme.paragraphSpacing / 2) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    renderBlock(child)
                }
            }
            .padding(.leading, 12)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Lists

    /// Bullet styles for different nesting levels in unordered lists.
    private static let bulletStyles = ["•", "◦", "▪", "▸"]

    /// Returns the bullet character for a given nesting depth.
    private func bulletForDepth(_ depth: Int) -> String {
        Self.bulletStyles[depth % Self.bulletStyles.count]
    }

    @ViewBuilder
    private func renderOrderedList(_ list: OrderedList, depth: Int = 0) -> some View {
        LazyVStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                renderListItem(item, bullet: "\(index + Int(list.startIndex)).", depth: depth)
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }

    @ViewBuilder
    private func renderUnorderedList(_ list: UnorderedList, depth: Int = 0) -> some View {
        LazyVStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
                if item.checkbox != nil {
                    renderTaskListItem(item, depth: depth)
                } else {
                    renderListItem(item, bullet: bulletForDepth(depth), depth: depth)
                }
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }

    @ViewBuilder
    private func renderListItem(_ item: ListItem, bullet: String, depth: Int) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(bullet)
                .font(theme.bodySwiftUIFont)
                .foregroundColor(theme.textColor)
                .selectionTextPassThrough()

            LazyVStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    renderListChildBlock(child, depth: depth)
                }
            }
        }
    }

    @ViewBuilder
    private func renderTaskListItem(_ item: ListItem, depth: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.checkbox?.isChecked == true ? "checkmark.square.fill" : "square")
                .font(theme.bodySwiftUIFont)
                .foregroundColor(item.checkbox?.isChecked == true ? theme.linkColor : theme.secondaryTextColor)
                .frame(width: 20, alignment: .trailing)

            LazyVStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    renderListChildBlock(child, depth: depth)
                }
            }
        }
    }

    /// Renders a child block within a list item, handling nested lists specially.
    private func renderListChildBlock(_ markup: any Markup, depth: Int) -> AnyView {
        if let nestedOrdered = markup as? OrderedList {
            return AnyView(renderOrderedList(nestedOrdered, depth: depth + 1))
        } else if let nestedUnordered = markup as? UnorderedList {
            return AnyView(renderUnorderedList(nestedUnordered, depth: depth + 1))
        } else {
            return renderBlock(markup)
        }
    }

    // MARK: - Table

    @ViewBuilder
    private func renderTable(_ table: Markdown.Table) -> some View {
        let cellArrays = extractTableCells(from: table)
        LazyVStack(spacing: 0) {
            // Header row
            if !cellArrays.header.isEmpty {
                renderTableCellRow(cells: cellArrays.header, isHeader: true)

                if !cellArrays.body.isEmpty {
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 1)
                        .allowsHitTesting(false)
                }
            }

            // Body rows
            ForEach(Array(cellArrays.body.enumerated()), id: \.offset) { rowIndex, rowCells in
                renderTableCellRow(cells: rowCells, isHeader: false, rowIndex: rowIndex)

                if rowIndex < cellArrays.body.count - 1 {
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.3), lineWidth: 1)
        )
        .selectionTextPassThrough()
    }

    /// Extracts cells from a table into arrays for easier SwiftUI rendering.
    private func extractTableCells(from table: Markdown.Table) -> (header: [Markdown.Table.Cell], body: [[Markdown.Table.Cell]]) {
        let header: [Markdown.Table.Cell] = Array(table.head.cells)
        let body: [[Markdown.Table.Cell]] = table.body.rows.map { Array($0.cells) }
        return (header, body)
    }
    
    @ViewBuilder
    private func renderTableCellRow(cells: [Markdown.Table.Cell], isHeader: Bool, rowIndex: Int? = nil) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                renderInlineChildren(cell)
                    .font(theme.bodySwiftUIFont)
                    .fontWeight(isHeader ? .semibold : nil)
                    .foregroundColor(theme.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, isHeader ? 10 : 9)

                if index < cells.count - 1 {
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(isHeader ? Color.secondary.opacity(0.2) : Color.clear)
    }

    // MARK: - Inline Rendering

    @ViewBuilder
    private func renderInlineChildren(_ parent: any Markup) -> some View {
        buildInlineText(from: parent)
    }

    /// Builds a Text view from inline children, handling LaTeX segments and links.
    private func buildInlineText(from parent: any Markup) -> AnyView {
        let plainText = extractPlainText(from: parent)

        // Check if text contains LaTeX
        if LaTeXPreprocessor.containsLaTeX(plainText) {
            return AnyView(renderTextWithLaTeX(parent))
        }

        if containsInlineMCodeReferences(parent) {
            return AnyView(renderTextWithLinks(parent))
        }

        if containsLinks(parent) {
            return AnyView(renderTextWithLinks(parent))
        }

        if containsImages(parent) {
            return AnyView(renderTextWithImages(parent))
        }

        return AnyView(buildAttributedText(from: parent).selectionTextPassThrough())
    }

    /// Checks if the markup contains any Link nodes.
    private func containsLinks(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if child is Markdown.Link { return true }
            if containsLinks(child) { return true }
        }
        return false
    }

    private func containsInlineMCodeReferences(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if let code = child as? InlineCode, parseMCodeReferences(from: code.code)?.isEmpty == false {
                return true
            }
            if containsInlineMCodeReferences(child) { return true }
        }
        return false
    }

    /// Checks if the markup contains any Image nodes.
    private func containsImages(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if child is Markdown.Image { return true }
            if containsImages(child) { return true }
        }
        return false
    }

    /// Renders text with images using flow layout.
    @ViewBuilder
    private func renderTextWithImages(_ parent: any Markup) -> some View {
        FlowLayout(spacing: 0) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                renderInlineFlowElement(element)
            }
        }
    }

    /// Renders text with clickable links using flow layout.
    @ViewBuilder
    private func renderTextWithLinks(_ parent: any Markup) -> some View {
        FlowLayout(spacing: 0) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                renderInlineFlowElement(element)
            }
        }
    }

    /// Renders an inline flow element as a View.
    @ViewBuilder
    private func renderInlineFlowElement(_ element: InlineFlowElement) -> some View {
        switch element {
        case .text(let text, let style):
            styledText(text, style: style)
                .selectionTextPassThrough()

        case .link(let link):
            TappableLinkView(
                link: link,
                theme: theme,
                linkHandler: linkHandler,
                baseURL: baseURL
            )

        case .codeReference(let reference):
            MCodeReferenceBlockView(
                reference: reference,
                theme: theme,
                tapHandler: MCodeReferenceHandler
            )

        case .image(let image):
            MarkdownImageView(
                image: image,
                theme: theme,
                baseURL: baseURL
            )

        case .latex(let latex, let isBlock):
            LaTeXView(latex: latex, isBlock: isBlock, theme: theme)

        case .lineBreak:
            Color.clear
                .frame(width: 0, height: theme.bodyFont.markdownLineHeight)
                .layoutValue(key: FlowLineBreakLayoutValueKey.self, value: true)
        }
    }

    /// Renders text that may contain inline LaTeX.
    @ViewBuilder
    private func renderTextWithLaTeX(_ parent: any Markup) -> some View {
        let plainText = extractPlainText(from: parent)

        FlowLayout(spacing: 0) {
            let elements = flowInlineElements(from: LaTeXPreprocessor.extractSegments(from: plainText))
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                renderInlineFlowElement(element)
            }
        }
    }

    /// Builds attributed text for inline content without LaTeX.
    private func buildAttributedText(from parent: any Markup) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for child in parent.children {
            result = result + renderInlineElement(child)
        }
        return result
    }

    /// Renders a single inline element to Text.
    private func renderInlineElement(_ element: any Markup) -> SwiftUI.Text {
        switch element {
        case let text as Markdown.Text:
            return SwiftUI.Text(text.string)

        case let strong as Strong:
            let inner = buildTextFromChildren(strong)
            return inner.bold()

        case let emphasis as Emphasis:
            let inner = buildTextFromChildren(emphasis)
            return inner.italic()

        case let strikethrough as Strikethrough:
            let inner = buildTextFromChildren(strikethrough)
            return inner.strikethrough()

        case let code as InlineCode:
            return SwiftUI.Text(code.code)
                .font(theme.codeSwiftUIFont)
            
        case let link as Markdown.Link:
            let inner = buildTextFromChildren(link)
            return inner.foregroundColor(theme.linkColor)

        case _ as SoftBreak:
            return SwiftUI.Text("\n")

        case _ as LineBreak:
            return SwiftUI.Text("\n")

        case let image as Markdown.Image:
            // Display alt text for images (actual image loading would need AsyncImage)
            return SwiftUI.Text("[\(image.plainText)]")
                .foregroundColor(theme.secondaryTextColor)

        default:
            // For any other inline elements, try to extract plain text
            if let plainText = element as? any PlainTextConvertibleMarkup {
                return SwiftUI.Text(plainText.plainText)
            }
            return SwiftUI.Text("")
        }
    }

    /// Builds Text from children of a markup element.
    private func buildTextFromChildren(_ parent: any Markup) -> SwiftUI.Text {
        parent.children.reduce(SwiftUI.Text("")) { result, child in
            result + renderInlineElement(child)
        }
    }

    /// Extracts plain text from markup for LaTeX detection.
    private func extractPlainText(from markup: any Markup) -> String {
        if let plainText = markup as? any PlainTextConvertibleMarkup {
            return plainText.plainText
        }
        return markup.children.map { extractPlainText(from: $0) }.joined()
    }

    private func flowInlineElements(from parent: any Markup) -> [InlineFlowElement] {
        parent.children.flatMap {
            flowInlineElements(from: $0, style: [])
        }
    }

    private func flowInlineElements(
        from element: any Markup,
        style: InlineTextStyle
    ) -> [InlineFlowElement] {
        switch element {
        case let text as Markdown.Text:
            return textInlineFlowElements(text.string, style: style)

        case let strong as Strong:
            return strong.children.flatMap {
                flowInlineElements(from: $0, style: style.union(.bold))
            }

        case let emphasis as Emphasis:
            return emphasis.children.flatMap {
                flowInlineElements(from: $0, style: style.union(.italic))
            }

        case let strikethrough as Strikethrough:
            return strikethrough.children.flatMap {
                flowInlineElements(from: $0, style: style.union(.strikethrough))
            }

        case let link as Markdown.Link:
            return [.link(link)]

        case let code as InlineCode:
            if let references = parseMCodeReferences(from: code.code), references.count == 1, let reference = references.first {
                return [.codeReference(reference)]
            }
            return textInlineFlowElements(code.code, style: style.union(.code))

        case _ as SoftBreak:
            return textInlineFlowElements(" ", style: style)

        case _ as LineBreak:
            return [.lineBreak]

        case let image as Markdown.Image:
            return [.image(image)]

        default:
            if let plainText = element as? any PlainTextConvertibleMarkup {
                return textInlineFlowElements(plainText.plainText, style: style)
            }
            return []
        }
    }

    private func flowInlineElements(from segments: [LaTeXPreprocessor.Segment]) -> [InlineFlowElement] {
        segments.flatMap { segment in
            switch segment {
            case .text(let text):
                return textInlineFlowElements(text, style: [])
            case .latex(let latex, let isBlock):
                return [.latex(latex, isBlock)]
            }
        }
    }

    private func textInlineFlowElements(_ text: String, style: InlineTextStyle) -> [InlineFlowElement] {
        MarkdownInlineTextWrapping.units(in: text).map {
            .text($0, style)
        }
    }

    private func styledText(_ text: String, style: InlineTextStyle) -> SwiftUI.Text {
        var result = SwiftUI.Text(text)

        if style.contains(.bold) {
            result = result.bold()
        }
        if style.contains(.italic) {
            result = result.italic()
        }
        if style.contains(.strikethrough) {
            result = result.strikethrough()
        }

        result = result.font(style.contains(.code) ? theme.codeSwiftUIFont : theme.bodySwiftUIFont)
        return result.foregroundColor(theme.textColor)
    }

}

private struct CodeBlockContainerModifier: ViewModifier {
    let theme: MarkdownTheme
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .padding(isInteractive ? .zero : theme.codeBlockPadding)
            .background(isInteractive ? Color.clear : theme.codeBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .modifier(CodeBlockSelectionModifier(isInteractive: isInteractive))
    }
}

private struct CodeBlockSelectionModifier: ViewModifier {
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInteractive {
            content
        } else {
            content.selectionTextPassThrough()
        }
    }
}

extension View {

    func selectionTextPassThrough() -> some View {
#if os(macOS)
        self
            .allowsHitTesting(false)
            .pointerStyle(.horizontalText)
#else
        self
            .allowsHitTesting(false)
#endif
    }
    
    func buttonLink() -> some View {
#if os(macOS)
        self
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .pointerStyle(.link)
#else
        self
#endif
    }
}

// MARK: - Flow Layout

/// A simple flow layout for mixed text and views.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0

    private struct MeasuredSubview {
        let size: CGSize
        let baseline: CGFloat
        let proposal: ProposedViewSize
        let isForcedBreak: Bool
    }

    private struct Line {
        let indices: [Int]
        let width: CGFloat
        let maxAscent: CGFloat
        let maxDescent: CGFloat

        var height: CGFloat {
            maxAscent + maxDescent
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                let measured = result.measured[index]
                subview.place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                    proposal: measured.proposal
                )
            }
        }
    }

    private func computeLayout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint], measured: [MeasuredSubview]) {
        guard !subviews.isEmpty else {
            return (.zero, [], [])
        }

        let maxWidth = max(proposal.width ?? .infinity, 1)
        let measured = subviews.map { subview -> MeasuredSubview in
            let measurementProposal = measurementProposal(for: subview, maxWidth: maxWidth)
            let size = subview.sizeThatFits(measurementProposal)
            let dimensions = subview.dimensions(in: measurementProposal)
            let baseline = resolvedBaseline(from: dimensions, size: size)
            return MeasuredSubview(
                size: size,
                baseline: baseline,
                proposal: measurementProposal,
                isForcedBreak: subview[FlowLineBreakLayoutValueKey.self]
            )
        }

        let lines = computeLines(measured: measured, maxWidth: maxWidth)
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0

        for line in lines {
            var currentX: CGFloat = 0

            for index in line.indices {
                let item = measured[index]
                let y = currentY + (line.maxAscent - item.baseline)
                positions[index] = CGPoint(x: currentX, y: y)
                currentX += item.size.width + spacing
            }

            totalWidth = max(totalWidth, line.width)
            currentY += line.height + spacing
        }

        let totalHeight = max(0, currentY - spacing)
        return (CGSize(width: totalWidth, height: totalHeight), positions, measured)
    }

    private func computeLines(measured: [MeasuredSubview], maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var currentIndices: [Int] = []
        var currentWidth: CGFloat = 0
        var currentAscent: CGFloat = 0
        var currentDescent: CGFloat = 0

        func flushCurrentLine() {
            guard !currentIndices.isEmpty else { return }
            lines.append(
                Line(
                    indices: currentIndices,
                    width: currentWidth,
                    maxAscent: currentAscent,
                    maxDescent: currentDescent
                )
            )
            currentIndices.removeAll(keepingCapacity: true)
            currentWidth = 0
            currentAscent = 0
            currentDescent = 0
        }

        for (index, item) in measured.enumerated() {
            if item.isForcedBreak {
                if currentIndices.isEmpty {
                    lines.append(
                        Line(
                            indices: [],
                            width: 0,
                            maxAscent: item.baseline,
                            maxDescent: item.size.height - item.baseline
                        )
                    )
                } else {
                    flushCurrentLine()
                }
                continue
            }

            let candidateWidth = currentIndices.isEmpty ? item.size.width : currentWidth + spacing + item.size.width
            if !currentIndices.isEmpty, candidateWidth > maxWidth {
                flushCurrentLine()
            }

            currentIndices.append(index)
            currentWidth = currentIndices.count == 1 ? item.size.width : currentWidth + spacing + item.size.width
            currentAscent = max(currentAscent, item.baseline)
            currentDescent = max(currentDescent, item.size.height - item.baseline)
        }

        flushCurrentLine()
        return lines
    }

    private func measurementProposal(for subview: LayoutSubview, maxWidth: CGFloat) -> ProposedViewSize {
        guard maxWidth.isFinite else {
            return .unspecified
        }

        let unspecifiedSize = subview.sizeThatFits(.unspecified)
        guard unspecifiedSize.width > maxWidth else {
            return .unspecified
        }

        return ProposedViewSize(width: maxWidth, height: nil)
    }

    private func resolvedBaseline(from dimensions: ViewDimensions, size: CGSize) -> CGFloat {
        let first = dimensions[.firstTextBaseline]
        if first.isFinite, first > 0, first <= size.height {
            return first
        }

        let last = dimensions[.lastTextBaseline]
        if last.isFinite, last > 0, last <= size.height {
            return last
        }

        // For non-text views, use vertical center as a neutral fallback.
        return size.height / 2
    }
}

private struct InlineTextStyle: OptionSet {
    let rawValue: Int

    static let bold = InlineTextStyle(rawValue: 1 << 0)
    static let italic = InlineTextStyle(rawValue: 1 << 1)
    static let strikethrough = InlineTextStyle(rawValue: 1 << 2)
    static let code = InlineTextStyle(rawValue: 1 << 3)
}

private enum InlineFlowElement {
    case text(String, InlineTextStyle)
    case link(Markdown.Link)
    case codeReference(MCodeReference)
    case image(Markdown.Image)
    case latex(String, Bool)
    case lineBreak
}

private struct FlowLineBreakLayoutValueKey: LayoutValueKey {
    static let defaultValue = false
}
