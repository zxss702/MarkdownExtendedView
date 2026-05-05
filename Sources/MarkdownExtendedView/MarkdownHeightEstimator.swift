import Foundation
import Markdown
import ExtendedSwiftMath

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownHeightEstimator {
    private static let bulletStyles = ["•", "◦", "▪", "▸"]

    static func estimate(blocks: [MarkdownBlockNode], width: CGFloat, theme: MarkdownTheme) async -> CGFloat {
        guard width > 0 else { return 0 }

        return await withTaskGroup(of: CGFloat.self) { group in
            for block in blocks {
                group.addTask {
                    if Task.isCancelled { return 0 }
                    return await estimateBlock(block.markup, width: width, theme: theme)
                }
            }
            var totalHeight: CGFloat = 0
            for await height in group {
                totalHeight += height
            }
            let totalSpacing = theme.paragraphSpacing * CGFloat(max(0, blocks.count - 1))
            return ceil(totalHeight + totalSpacing)
        }
    }

    private static func estimateBlock(_ markup: any Markup, width: CGFloat, theme: MarkdownTheme) async -> CGFloat {
        let availableWidth = max(width, 1)

        switch markup {
        case let heading as Heading:
            let contentHeight = measureText(
                heading.plainText,
                font: theme.headingFont(level: heading.level),
                maxWidth: availableWidth,
                lineSpacing: 0
            )
            return ceil(contentHeight + (heading.level == 1 ? 16 : 8) + 4)

        case let paragraph as Paragraph:
            return await estimateParagraph(paragraph, width: availableWidth, theme: theme)

        case let codeBlock as CodeBlock:
            if codeBlock.language == "mermaid" {
                return MarkdownLayoutMetrics.fixedMermaidHeight
            }
            return estimateCodeBlock(codeBlock, width: availableWidth, theme: theme)

        case let blockQuote as BlockQuote:
            let innerWidth = max(availableWidth - 16, 1)
            var totalChildHeight: CGFloat = 0
            for child in blockQuote.children {
                if Task.isCancelled { return 0 }
                totalChildHeight += await estimateBlock(child, width: innerWidth, theme: theme)
            }
            let spacing = (theme.paragraphSpacing / 2) * CGFloat(max(0, blockQuote.childCount - 1))
            return ceil(totalChildHeight + spacing + 8)

        case let orderedList as OrderedList:
            return await estimateOrderedList(orderedList, width: availableWidth, theme: theme, depth: 0)

        case let unorderedList as UnorderedList:
            return await estimateUnorderedList(unorderedList, width: availableWidth, theme: theme, depth: 0)

        case let table as Markdown.Table:
            return estimateTable(table, width: availableWidth, theme: theme)

        case _ as ThematicBreak:
            return 17

        case let htmlBlock as HTMLBlock:
            return measureText(
                htmlBlock.rawHTML,
                font: theme.codeFont,
                maxWidth: availableWidth,
                lineSpacing: theme.paragraphSpacing
            )

        default:
            return 0
        }
    }

    private static func estimateParagraph(_ paragraph: Paragraph, width: CGFloat, theme: MarkdownTheme) async -> CGFloat {
        let plainText = paragraph.plainText

        if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") {
            let latex = String(plainText.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formulaSize = await measureFormula(
                latex,
                fontSize: theme.latexBlockFontSize,
                mode: .display,
                maxWidth: width
            )
            return ceil(max(formulaSize.height, theme.latexBlockFontSize) + 24)
        }

        if LaTeXPreprocessor.containsLaTeX(plainText) {
            var items: [FlowItem] = []
            for segment in LaTeXPreprocessor.extractSegments(from: plainText) {
                items.append(contentsOf: await flowItems(for: segment, theme: theme, maxWidth: width))
            }
            return estimateFlowHeight(
                items: items,
                maxWidth: width,
                fallbackLineHeight: theme.bodyFont.markdownLineHeight,
                lineSpacing: theme.paragraphSpacing
            )
        }

        if containsLinks(paragraph) || containsImages(paragraph) || containsInlineMCodeReferences(paragraph) {
            var items: [FlowItem] = []
            for child in paragraph.children {
                items.append(contentsOf: flowItems(for: child, theme: theme, maxWidth: width))
            }
            return estimateFlowHeight(
                items: items,
                maxWidth: width,
                fallbackLineHeight: theme.bodyFont.markdownLineHeight,
                lineSpacing: theme.paragraphSpacing
            )
        }

        return measureText(
            extractPlainText(from: paragraph),
            font: theme.bodyFont,
            maxWidth: width,
            lineSpacing: theme.paragraphSpacing
        )
    }

    private static func estimateCodeBlock(_ codeBlock: CodeBlock, width: CGFloat, theme: MarkdownTheme) -> CGFloat {
        let innerWidth = max(width - (theme.codeBlockPadding * 2), 1)
        let normalized = codeBlock.code.trimmingCharacters(in: .newlines)
        let lines = normalized.isEmpty ? [" "] : normalized.components(separatedBy: .newlines)
        let heights = lines.map { line in
            measureText(
                line.isEmpty ? " " : line,
                font: theme.codeBlockFont,
                maxWidth: innerWidth,
                lineSpacing: 0
            )
        }
        let lineSpacing = theme.codeLineSpacing * CGFloat(max(0, heights.count - 1))
        return ceil(heights.reduce(0, +) + lineSpacing + (theme.codeBlockPadding * 2))
    }

    private static func estimateOrderedList(_ list: OrderedList, width: CGFloat, theme: MarkdownTheme, depth: Int) async -> CGFloat {
        let listWidth = max(width - (depth > 0 ? theme.indentation : 0), 1)
        var totalHeight: CGFloat = 0
        for (index, item) in list.listItems.enumerated() {
            let itemH = await estimateListItem(
                item,
                width: listWidth,
                bulletWidth: measureSingleLine(
                    "\(index + Int(list.startIndex)).",
                    font: theme.bodyFont
                ).width,
                bulletSpacing: 4,
                theme: theme,
                depth: depth
            )
            totalHeight += itemH
        }
        let spacing = theme.listItemSpacing * CGFloat(max(0, list.childCount - 1))
        return ceil(totalHeight + spacing)
    }

    private static func estimateUnorderedList(_ list: UnorderedList, width: CGFloat, theme: MarkdownTheme, depth: Int) async -> CGFloat {
        let listWidth = max(width - (depth > 0 ? theme.indentation : 0), 1)
        var totalHeight: CGFloat = 0
        for item in list.listItems {
            let itemH: CGFloat
            if item.checkbox != nil {
                itemH = await estimateTaskListItem(item, width: listWidth, theme: theme, depth: depth)
            } else {
                itemH = await estimateListItem(
                    item,
                    width: listWidth,
                    bulletWidth: measureSingleLine(
                        bulletStyles[depth % bulletStyles.count],
                        font: theme.bodyFont
                    ).width,
                    bulletSpacing: 4,
                    theme: theme,
                    depth: depth
                )
            }
            totalHeight += itemH
        }
        let spacing = theme.listItemSpacing * CGFloat(max(0, list.childCount - 1))
        return ceil(totalHeight + spacing)
    }

    private static func estimateListItem(
        _ item: ListItem,
        width: CGFloat,
        bulletWidth: CGFloat,
        bulletSpacing: CGFloat,
        theme: MarkdownTheme,
        depth: Int
    ) async -> CGFloat {
        let contentWidth = max(width - bulletWidth - bulletSpacing, 1)
        let contentHeight = await estimateListItemChildren(Array(item.children), width: contentWidth, theme: theme, depth: depth)
        return ceil(max(theme.bodyFont.markdownLineHeight, contentHeight))
    }

    private static func estimateTaskListItem(
        _ item: ListItem,
        width: CGFloat,
        theme: MarkdownTheme,
        depth: Int
    ) async -> CGFloat {
        let contentWidth = max(width - 20 - 8, 1)
        let contentHeight = await estimateListItemChildren(Array(item.children), width: contentWidth, theme: theme, depth: depth)
        return ceil(max(theme.bodyFont.markdownLineHeight, contentHeight))
    }

    private static func estimateListItemChildren(
        _ children: [any Markup],
        width: CGFloat,
        theme: MarkdownTheme,
        depth: Int
    ) async -> CGFloat {
        var totalHeight: CGFloat = 0
        for child in children {
            if let nestedOrdered = child as? OrderedList {
                totalHeight += await estimateOrderedList(nestedOrdered, width: width, theme: theme, depth: depth + 1)
            } else if let nestedUnordered = child as? UnorderedList {
                totalHeight += await estimateUnorderedList(nestedUnordered, width: width, theme: theme, depth: depth + 1)
            } else {
                totalHeight += await estimateBlock(child, width: width, theme: theme)
            }
        }
        let spacing = theme.listItemSpacing * CGFloat(max(0, children.count - 1))
        return ceil(totalHeight + spacing)
    }

    private static func estimateTable(_ table: Markdown.Table, width: CGFloat, theme: MarkdownTheme) -> CGFloat {
        let header = Array(table.head.cells)
        let bodyRows = Array(table.body.rows).map { Array($0.cells) }
        let columnCount = max(header.count, bodyRows.map(\.count).max() ?? 0)

        guard columnCount > 0 else { return 0 }

        let separatorWidth = CGFloat(max(0, columnCount - 1))
        let columnWidth = max((width - separatorWidth) / CGFloat(columnCount), 1)
        let contentWidth = max(columnWidth - 24, 1)

        var totalHeight: CGFloat = 0

        if !header.isEmpty {
            totalHeight += estimateTableRow(header, width: contentWidth, theme: theme, padding: 20)
            if !bodyRows.isEmpty {
                totalHeight += 1
            }
        }

        for rowIndex in bodyRows.indices {
            totalHeight += estimateTableRow(bodyRows[rowIndex], width: contentWidth, theme: theme, padding: 18)
            if rowIndex < bodyRows.count - 1 {
                totalHeight += 1
            }
        }

        return ceil(totalHeight)
    }

    private static func estimateTableRow(
        _ cells: [Markdown.Table.Cell],
        width: CGFloat,
        theme: MarkdownTheme,
        padding: CGFloat
    ) -> CGFloat {
        let heights = cells.map { cell in
            measureText(
                extractPlainText(from: cell),
                font: theme.bodyFont,
                maxWidth: width,
                lineSpacing: theme.paragraphSpacing
            )
        }
        return ceil((heights.max() ?? theme.bodyFont.markdownLineHeight) + padding)
    }

    private static func flowItems(for element: any Markup, theme: MarkdownTheme, maxWidth: CGFloat) -> [FlowItem] {
        switch element {
        case let text as Markdown.Text:
            return textFlowItems(text.string, font: theme.bodyFont)

        case let strong as Strong:
            return textFlowItems(extractPlainText(from: strong), font: theme.bodyFont)

        case let emphasis as Emphasis:
            return textFlowItems(extractPlainText(from: emphasis), font: theme.bodyFont)

        case let link as Markdown.Link:
            return textFlowItems(extractPlainText(from: link), font: theme.bodyFont)

        case let code as InlineCode:
            if let references = parseMCodeReferences(from: code.code), references.count == 1 {
                return [
                    .box(
                        size: mCodeReferenceInlineSize(theme: theme),
                        baseline: mCodeReferenceInlineBaseline(theme: theme)
                    )
                ]
            }
            return textFlowItems(code.code, font: theme.codeFont)

        case _ as SoftBreak:
            return textFlowItems(" ", font: theme.bodyFont)

        case _ as LineBreak:
            return [.forcedBreak(lineHeight: theme.bodyFont.markdownLineHeight)]

        case _ as Markdown.Image:
            return [.box(size: MarkdownLayoutMetrics.fixedImageSize)]

        default:
            if let plain = element as? any PlainTextConvertibleMarkup {
                return textFlowItems(plain.plainText, font: theme.bodyFont)
            }
            return []
        }
    }

    private static func flowItems(
        for segment: LaTeXPreprocessor.Segment,
        theme: MarkdownTheme,
        maxWidth: CGFloat
    ) async -> [FlowItem] {
        switch segment {
        case .text(let text):
            return textFlowItems(text, font: theme.bodyFont)
        case .latex(let latex, _):
            let size = await measureFormula(
                latex,
                fontSize: theme.latexInlineFontSize,
                mode: .text,
                maxWidth: maxWidth
            )
            return [.box(size: size)]
        }
    }

    private static func textFlowItems(_ text: String, font: MarkdownNativeFont) -> [FlowItem] {
        MarkdownInlineTextWrapping.units(in: text).map {
            .text($0, font: font)
        }
    }

    private static func estimateFlowHeight(
        items: [FlowItem],
        maxWidth: CGFloat,
        fallbackLineHeight: CGFloat,
        lineSpacing: CGFloat
    ) -> CGFloat {
        guard !items.isEmpty else { return ceil(fallbackLineHeight) }

        var currentWidth: CGFloat = 0
        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        var hasLine = false
        var totalHeight: CGFloat = 0
        var lineCount = 0

        func flushLine() {
            guard hasLine else { return }
            totalHeight += max(maxAscent + maxDescent, fallbackLineHeight)
            lineCount += 1
            currentWidth = 0
            maxAscent = 0
            maxDescent = 0
            hasLine = false
        }

        for item in items {
            if item.isForcedBreak {
                if hasLine {
                    flushLine()
                } else {
                    totalHeight += max(item.size.height, fallbackLineHeight)
                    lineCount += 1
                }
                continue
            }

            let candidateWidth = hasLine ? currentWidth + item.size.width : item.size.width
            if hasLine && candidateWidth > maxWidth {
                flushLine()
            }

            hasLine = true
            currentWidth = hasLine && currentWidth > 0 ? currentWidth + item.size.width : item.size.width
            maxAscent = max(maxAscent, item.baseline)
            maxDescent = max(maxDescent, item.size.height - item.baseline)
        }

        flushLine()
        totalHeight += lineSpacing * CGFloat(max(0, lineCount - 1))
        return ceil(max(totalHeight, fallbackLineHeight))
    }

@MainActor
private final class MTMathUILabelCache {
    static let shared = MTMathUILabel()
}

extension MarkdownHeightEstimator {
    @MainActor
    private static func measureFormula(
        _ latex: String,
        fontSize: CGFloat,
        mode: MTMathUILabelMode,
        maxWidth: CGFloat
    ) -> CGSize {
        let label = MTMathUILabelCache.shared
        label.latex = latex
        label.fontSize = fontSize
        label.labelMode = mode
        label.preferredMaxLayoutWidth = max(maxWidth, 1)
        let size = label.sizeThatFits(CGSize(width: max(maxWidth, 1), height: .greatestFiniteMagnitude))
        return CGSize(
            width: ceil(max(size.width, 1)),
            height: ceil(max(size.height, fontSize))
        )
    }

    private static func measureText(
        _ text: String,
        font: MarkdownNativeFont,
        maxWidth: CGFloat,
        lineSpacing: CGFloat
    ) -> CGFloat {
        let content = text.isEmpty ? " " : text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing

        let attributed = NSAttributedString(
            string: content,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )

        let rect = attributed.boundingRect(
            with: CGSize(width: max(maxWidth, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        return ceil(max(rect.height, font.markdownLineHeight))
    }

    fileprivate static func measureSingleLine(_ text: String, font: MarkdownNativeFont) -> CGSize {
        let content = text.isEmpty ? " " : text
        let size = (content as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: ceil(size.width),
            height: ceil(max(size.height, font.markdownLineHeight))
        )
    }

    private static func containsLinks(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if child is Markdown.Link { return true }
            if containsLinks(child) { return true }
        }
        return false
    }

    private static func containsImages(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if child is Markdown.Image { return true }
            if containsImages(child) { return true }
        }
        return false
    }

    private static func containsInlineMCodeReferences(_ parent: any Markup) -> Bool {
        for child in parent.children {
            if let code = child as? InlineCode, parseMCodeReferences(from: code.code)?.isEmpty == false {
                return true
            }
            if containsInlineMCodeReferences(child) { return true }
        }
        return false
    }

    private static func extractPlainText(from markup: any Markup) -> String {
        if let plainText = markup as? any PlainTextConvertibleMarkup {
            return plainText.plainText
        }
        return markup.children.map { extractPlainText(from: $0) }.joined()
    }

    private static func mCodeReferenceInlineSize(theme: MarkdownTheme) -> CGSize {
        let titleHeight = theme.codeFont.markdownLineHeight
        let lineNumberHeight = max(theme.codeFont.pointSize - 4, 8)
        let contentHeight = max(titleHeight, lineNumberHeight, 12)
        return CGSize(width: 160, height: ceil(contentHeight + 2))
    }

    private static func mCodeReferenceInlineBaseline(theme: MarkdownTheme) -> CGFloat {
        max(theme.codeFont.ascender, 0) + 1
    }
}

private struct FlowItem {
    let size: CGSize
    let baseline: CGFloat
    let isForcedBreak: Bool

    static func text(_ text: String, font: MarkdownNativeFont) -> FlowItem {
        let size = MarkdownHeightEstimator.measureSingleLine(text, font: font)
        return FlowItem(size: size, baseline: max(font.ascender, 0), isForcedBreak: false)
    }

    static func box(size: CGSize, baseline: CGFloat? = nil) -> FlowItem {
        FlowItem(size: size, baseline: baseline ?? size.height / 2, isForcedBreak: false)
    }

    static func forcedBreak(lineHeight: CGFloat) -> FlowItem {
        FlowItem(size: CGSize(width: 0, height: lineHeight), baseline: 0, isForcedBreak: true)
    }
}
