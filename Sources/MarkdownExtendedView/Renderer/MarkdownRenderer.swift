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
        VStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
            ForEach(snapshot.blocks) { block in
                renderBlock(block.markup, features: block.features, highlightedLines: snapshot.codeHighlights[block.id])
                    .transition(.markdownBlockAppear)
            }
        }
        .lineSpacing(theme.paragraphSpacing)
    }

    // MARK: - Block Rendering

    private func renderBlock(_ markup: any Markup, features: MarkdownBlockFeatures = [], highlightedLines: [[Token]]? = nil) -> AnyView {
        if let heading = markup as? Heading {
            return AnyView(renderHeading(heading, features: features))
        } else if let paragraph = markup as? Paragraph {
            return AnyView(renderParagraph(paragraph, features: features))
        } else if let codeBlock = markup as? CodeBlock {
            return AnyView(renderCodeBlock(codeBlock, highlightedLines: highlightedLines))
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
    private func renderHeading(_ heading: Heading, features: MarkdownBlockFeatures) -> some View {
        renderInlineChildren(heading, features: features)
            .font(theme.headingSwiftUIFont(level: heading.level))
            .foregroundColor(theme.textColor)
            .contentTransition(.numericText())
            .padding(.top, heading.level == 1 ? 16 : 8)
            .padding(.bottom, 4)
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func renderParagraph(_ paragraph: Paragraph, features: MarkdownBlockFeatures) -> some View {
        let plainText = paragraph.plainText
        if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") {
            let latex = String(plainText.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            LaTeXView(latex: latex, isBlock: true, theme: theme)
        } else {
            renderInlineChildren(paragraph, features: features)
                .font(theme.bodySwiftUIFont)
                .foregroundColor(theme.textColor)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Code Block

    @ViewBuilder
    private func renderCodeBlock(_ codeBlock: CodeBlock, highlightedLines: [[Token]]? = nil) -> some View {
        if codeBlock.language == "mermaid" {
            renderMermaidBlock(codeBlock)
        } else {
            renderRegularCodeBlock(codeBlock, highlightedLines: highlightedLines)
        }
    }

    @ViewBuilder
    private func renderMermaidBlock(_ codeBlock: CodeBlock) -> some View {
        MermaidView(code: codeBlock.code, theme: theme)
    }

    @ViewBuilder
    private func renderRegularCodeBlock(_ codeBlock: CodeBlock, highlightedLines: [[Token]]? = nil) -> some View {
        Group {
            if codeBlock.language != nil {
                HighlightedCodeView(
                    code: codeBlock.code,
                    language: codeBlock.language,
                    theme: theme,
                    highlightedLines: highlightedLines
                )
            } else {
                Text(codeBlock.code.trimmingCharacters(in: .newlines))
                    .font(theme.codeBlockSwiftUIFont)
                    .contentTransition(.numericText())
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

            VStack(alignment: .leading, spacing: theme.paragraphSpacing / 2) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    renderBlock(child, features: computeInlineFeatures(child))
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
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                renderListItem(item, bullet: "\(index + Int(list.startIndex)).", depth: depth)
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }

    @ViewBuilder
    private func renderUnorderedList(_ list: UnorderedList, depth: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
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
                .contentTransition(.numericText(countsDown: true))
                .foregroundColor(theme.textColor)
                .selectionTextPassThrough()

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
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

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    renderListChildBlock(child, depth: depth)
                }
            }
        }
    }

    /// Renders a child block within a list item, handling nested lists specially.
    /// Renders a child block within a list item, handling nested lists specially.
    private func renderListChildBlock(_ markup: any Markup, depth: Int) -> AnyView {
        if let nestedOrdered = markup as? OrderedList {
            return AnyView(renderOrderedList(nestedOrdered, depth: depth + 1))
        } else if let nestedUnordered = markup as? UnorderedList {
            return AnyView(renderUnorderedList(nestedUnordered, depth: depth + 1))
        } else {
            return renderBlock(markup, features: computeInlineFeatures(markup))
        }
    }

    // MARK: - Table

    @ViewBuilder
    private func renderTable(_ table: Markdown.Table) -> some View {
        let cellArrays = extractTableCells(from: table)
        let alignments = table.columnAlignments
        
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            if !cellArrays.header.isEmpty {
                GridRow {
                    renderGridCells(cellArrays.header, isHeader: true, alignments: alignments)
                }
                // Horizontal line below header
                if !cellArrays.body.isEmpty {
                    renderHorizontalLine(above: cellArrays.body[0], alignments: alignments)
                } else {
                    renderSolidHorizontalLine(alignments: alignments)
                }
            }

            // Body rows
            ForEach(Array(cellArrays.body.enumerated()), id: \.offset) { rowIndex, rowCells in
                GridRow {
                    renderGridCells(rowCells, isHeader: false, alignments: alignments)
                }
                // Horizontal line between rows
                if rowIndex < cellArrays.body.count - 1 {
                    renderHorizontalLine(above: cellArrays.body[rowIndex + 1], alignments: alignments)
                }
            }
        }
        .padding(.vertical, 8)
        .selectionTextPassThrough()
    }

    @ViewBuilder
    private func renderSolidHorizontalLine(alignments: [Markdown.Table.ColumnAlignment?]) -> some View {
        let totalCols = alignments.count
        GridRow {
            Color.primary.opacity(0.15).frame(height: 0.5)
                .gridCellUnsizedAxes([.horizontal])
                .gridCellColumns(max(1, totalCols * 2 - 1))
        }
    }

    @ViewBuilder
    private func renderHorizontalLine(above rowCells: [GridCell], alignments: [Markdown.Table.ColumnAlignment?]) -> some View {
        GridRow {
            // We can't mutate variables in a @ViewBuilder natively, so we must compute the segments first.
            let segments = computeHorizontalSegments(rowCells: rowCells, totalCols: alignments.count)
            ForEach(segments) { segment in
                if segment.isClear {
                    Color.clear.frame(height: 0.5)
                        .gridCellUnsizedAxes([.horizontal])
                        .gridCellColumns(segment.gridSpan)
                } else {
                    Color.primary.opacity(0.15).frame(height: 0.5)
                        .gridCellUnsizedAxes([.horizontal])
                        .gridCellColumns(segment.gridSpan)
                }
            }
        }
    }

    private struct HorizontalSegment: Identifiable {
        let id = UUID()
        let isClear: Bool
        let gridSpan: Int
    }

    private func computeHorizontalSegments(rowCells: [GridCell], totalCols: Int) -> [HorizontalSegment] {
        var segments: [HorizontalSegment] = []
        var currentVisualCol = 0
        
        for gridCell in rowCells {
            let colIdx = gridCell.visualColumn
            let displayColspan = max(1, Int(gridCell.node.colspan))
            
            if currentVisualCol < colIdx {
                let missingCols = colIdx - currentVisualCol
                segments.append(HorizontalSegment(isClear: false, gridSpan: missingCols * 2))
            }
            
            segments.append(HorizontalSegment(isClear: gridCell.node.rowspan == 0, gridSpan: displayColspan * 2 - 1))
            
            if colIdx + displayColspan < totalCols {
                segments.append(HorizontalSegment(isClear: false, gridSpan: 1)) // Intersection
            }
            
            currentVisualCol = colIdx + displayColspan
        }
        
        if currentVisualCol < totalCols {
            let missingCols = totalCols - currentVisualCol
            // The last missing column doesn't have a trailing intersection, so it's missingCols * 2 - 1, PLUS 1 for the intersection BEFORE it!
            // Wait, if currentVisualCol < totalCols, there was an intersection BEFORE this missing block, which was ALREADY added by the previous cell!
            // Actually, the previous cell added the intersection IF its colIdx + displayColspan < totalCols.
            // So the previous cell DID add the intersection!
            // So the remaining block just covers `missingCols * 2 - 1`.
            // Wait, what if there were NO cells? (rowCells is empty)
            if currentVisualCol == 0 {
                segments.append(HorizontalSegment(isClear: false, gridSpan: totalCols * 2 - 1))
            } else {
                segments.append(HorizontalSegment(isClear: false, gridSpan: missingCols * 2 - 1))
            }
        }
        
        return segments
    }



    private struct GridCell {
        let node: Markdown.Table.Cell
        let visualColumn: Int
    }

    private func extractGridCells(from cells: [Markdown.Table.Cell]) -> [GridCell] {
        var result = [GridCell]()
        var skipCount = 0
        var currentVisualColumn = 0
        for cell in cells {
            if skipCount > 0 {
                skipCount -= 1
                currentVisualColumn += 1
                continue
            }
            result.append(GridCell(node: cell, visualColumn: currentVisualColumn))
            if cell.colspan > 1 {
                skipCount = Int(cell.colspan) - 1
            }
            currentVisualColumn += 1
        }
        return result
    }

    /// Extracts cells from a table into arrays for easier SwiftUI rendering.
    private func extractTableCells(from table: Markdown.Table) -> (header: [GridCell], body: [[GridCell]]) {
        let header = extractGridCells(from: Array(table.head.cells))
        let body = Array(table.body.rows.map { extractGridCells(from: Array($0.cells)) })
        return (header, body)
    }

    private func horizontalAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> HorizontalAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none, .some: return .leading
        }
    }

    private func textAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none, .some: return .leading
        }
    }

    private func swiftUITextAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> TextAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .none, .some: return .leading
        }
    }
    
    @ViewBuilder
    private func renderGridCells(_ cells: [GridCell], isHeader: Bool, alignments: [Markdown.Table.ColumnAlignment?]) -> some View {
        ForEach(Array(cells.enumerated()), id: \.offset) { index, gridCell in
            let cell = gridCell.node
            let colIdx = gridCell.visualColumn
            let colAlignment = colIdx < alignments.count ? alignments[colIdx] : nil
            
            let frameAlign: Alignment = textAlignment(for: colAlignment)
            let multilineAlign: TextAlignment = swiftUITextAlignment(for: colAlignment)
            let hAlign: HorizontalAlignment = horizontalAlignment(for: colAlignment)
            
            let displayColspan = max(1, cell.colspan)
            let finalColspan = displayColspan * 2 - 1

            if cell.rowspan > 0 {
                renderInlineChildren(cell, features: computeInlineFeatures(cell))
                    .font(theme.bodySwiftUIFont)
                    .fontWeight(isHeader ? .semibold : nil)
                    .foregroundColor(theme.textColor)
                    .multilineTextAlignment(multilineAlign)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxHeight: .infinity, alignment: frameAlign)
                    .gridColumnAlignment(hAlign)
                    .gridCellColumns(Int(finalColspan))
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .gridCellColumns(Int(finalColspan))
            }
            
            // Render vertical line if not the last visual column
            if colIdx + Int(displayColspan) < alignments.count {
                Color.primary.opacity(0.15).frame(width: 0.5)
                    .gridCellUnsizedAxes([.vertical])
            }
        }
    }

    // MARK: - Inline Rendering

    /// Computes feature flags for a markup node by traversing its subtree.
    /// Used for non-top-level blocks (blockquote children, list children, table cells)
    /// where features are not precomputed in MarkdownBlockNode.
    private func computeInlineFeatures(_ markup: any Markup) -> MarkdownBlockFeatures {
        var features: MarkdownBlockFeatures = []
        if markup is Markdown.Image { features.insert(.hasImages) }
        if markup is Markdown.Link { features.insert(.hasLinks) }
        if let code = markup as? InlineCode, let refs = parseMCodeReferences(from: code.code), !refs.isEmpty {
            features.insert(.hasMCodeReferences)
        }
        if let plainTextConvertible = markup as? (any PlainTextConvertibleMarkup) {
            if LaTeXPreprocessor.containsLaTeX(plainTextConvertible.plainText) {
                features.insert(.hasLaTeX)
            }
        }
        for child in markup.children {
            features.formUnion(computeInlineFeatures(child))
        }
        return features
    }

    @ViewBuilder
    private func renderInlineChildren(_ parent: any Markup, features: MarkdownBlockFeatures) -> some View {
        buildInlineText(from: parent, features: features)
    }

    /// Builds a Text view from inline children, using precomputed feature flags.
    private func buildInlineText(from parent: any Markup, features: MarkdownBlockFeatures) -> AnyView {

        if features.contains(.hasLaTeX) {
            return AnyView(renderTextWithLaTeX(parent))
        }
        if features.contains(.hasMCodeReferences) {
            return AnyView(renderTextWithLinks(parent))
        }
        if features.contains(.hasLinks) {
            return AnyView(renderTextWithLinks(parent))
        }
        if features.contains(.hasImages) {
            return AnyView(renderTextWithImages(parent))
        }
        return AnyView(buildAttributedText(from: parent).selectionTextPassThrough())
    }


    @ViewBuilder
    private func renderTextWithImages(_ parent: any Markup) -> some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                renderInlineFlowElement(element)
            }
        }
    }

    /// Renders text with clickable links using flow layout.
    @ViewBuilder
    private func renderTextWithLinks(_ parent: any Markup) -> some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
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
            if isBlock {
                LaTeXView(latex: latex, isBlock: true, theme: theme)
                    .layoutValue(key: BlockFormulaKey.self, value: true)
            } else {
                LaTeXView(latex: latex, isBlock: false, theme: theme)
            }

        case .lineBreak:
            Color.clear
                .frame(width: 0, height: theme.bodyFont.markdownLineHeight)
                .layoutValue(key: FlowLineBreakLayoutValueKey.self, value: true)
        }
    }

    /// Renders text that may contain inline LaTeX, using cached segments when available.
    @ViewBuilder
    private func renderTextWithLaTeX(_ parent: any Markup) -> some View {
        let plainText = extractPlainText(from: parent)
        let segments = LaTeXPreprocessor.extractSegments(from: plainText)

        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: segments)
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
            return [.lineBreak]

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



private struct BlockFormulaKey: LayoutValueKey {
    static let defaultValue: Bool = false
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
    var lineSpacing: CGFloat = 0
    var minimumLineHeight: CGFloat = 0

    struct CacheData {
        var size: CGSize
        var positions: [CGPoint]
        var measured: [MeasuredSubview]
        var proposal: ProposedViewSize?
    }

    func makeCache(subviews: Subviews) -> CacheData? {
        return nil
    }

    struct MeasuredSubview {
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

        func resolvedHeight(minimumLineHeight: CGFloat) -> CGFloat {
            max(height, minimumLineHeight)
        }

        func verticalInset(minimumLineHeight: CGFloat) -> CGFloat {
            max(0, resolvedHeight(minimumLineHeight: minimumLineHeight) - height) / 2
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) -> CGSize {
        if let cached = cache, cached.proposal == proposal {
            return cached.size
        }
        let result = computeLayout(proposal: proposal, subviews: subviews)
        cache = CacheData(size: result.size, positions: result.positions, measured: result.measured, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) {
        let result: (size: CGSize, positions: [CGPoint], measured: [MeasuredSubview])
        if let cached = cache, cached.proposal == proposal {
            result = (cached.size, cached.positions, cached.measured)
        } else {
            result = computeLayout(proposal: proposal, subviews: subviews)
            cache = CacheData(size: result.size, positions: result.positions, measured: result.measured, proposal: proposal)
        }

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
        let measured = subviews.map {
            measuredSubview(for: $0, maxWidth: maxWidth)
        }

        let lines = computeLines(measured: measured, maxWidth: maxWidth)
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0

        for line in lines {
            var currentX: CGFloat = 0
            let lineTopInset = line.verticalInset(minimumLineHeight: minimumLineHeight)

            for index in line.indices {
                let item = measured[index]
                let y = currentY + lineTopInset + (line.maxAscent - item.baseline)
                positions[index] = CGPoint(x: currentX, y: y)
                currentX += item.size.width + spacing
            }

            totalWidth = max(totalWidth, line.width)
            currentY += line.resolvedHeight(minimumLineHeight: minimumLineHeight) + lineSpacing
        }

        let totalHeight = max(0, currentY - lineSpacing)
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

    private func measuredSubview(for subview: LayoutSubview, maxWidth: CGFloat) -> MeasuredSubview {
        let isBlockFormula = subview[BlockFormulaKey.self]
        let unspecifiedProposal = ProposedViewSize.unspecified
        let unspecifiedSize = subview.sizeThatFits(unspecifiedProposal)

        let measurementProposal: ProposedViewSize
        let size: CGSize
        if isBlockFormula {
            measurementProposal = ProposedViewSize(width: maxWidth, height: nil)
            size = CGSize(width: maxWidth, height: subview.sizeThatFits(measurementProposal).height)
        } else if maxWidth.isFinite, unspecifiedSize.width > maxWidth {
            measurementProposal = ProposedViewSize(width: maxWidth, height: nil)
            size = subview.sizeThatFits(measurementProposal)
        } else {
            measurementProposal = unspecifiedProposal
            size = unspecifiedSize
        }

        let dimensions = subview.dimensions(in: measurementProposal)
        return MeasuredSubview(
            size: size,
            baseline: resolvedBaseline(from: dimensions, size: size),
            proposal: measurementProposal,
            isForcedBreak: subview[FlowLineBreakLayoutValueKey.self]
        )
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

// MARK: - Block Appear Transition

private struct MarkdownBlockAppearModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 4 : 0)
            .scaleEffect(isActive ? 0.01 : 1, anchor: .bottomLeading)
            .opacity(isActive ? 0 : 1)
    }
}

extension AnyTransition {
    static var markdownBlockAppear: AnyTransition {
        .modifier(
            active: MarkdownBlockAppearModifier(isActive: true),
            identity: MarkdownBlockAppearModifier(isActive: false)
        )
    }
}
