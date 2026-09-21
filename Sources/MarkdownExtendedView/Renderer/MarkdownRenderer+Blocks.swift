//
//  MarkdownRenderer+Blocks.swift
//  MarkdownExtendedView
//
//  Block-level dispatch over the flattened `MDBlock` model — no Markup
//  traversal happens in the render layer.

import SwiftUI
import Markdown

// MARK: - Block Rendering

struct RenderBlock: View {
    let block: MDBlock

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Data-level anchor identity: `block.id` survives lazy
        // materialization, keeping selection snapshots stable.
        blockContent
            .environment(\.markdownSelectionID, block.id.uuidString)
    }

    @ViewBuilder private var blockContent: some View {
        switch block.content {
        case .heading(let level, let attributed):
            RenderHeading(level: level, attributed: attributed)

        case .text(let attributed):
            InlineContentView(attributed: attributed)

        case .image(let image):
            // Registers its own block anchor (with the loaded image for
            // rich copies) and its context menu.
            MarkdownImageView(image: image, theme: theme, baseURL: baseURL)

        case .latexBlock(let latex):
            LaTeXView(latex: latex, isBlock: true, theme: theme)
                .makeCanSelectable(
                    isBlock: true,
                    blockText: "$$\(latex)$$",
                    richImage: MathDisplayCache.shared.getCachedImage(
                        latex: latex,
                        fontSize: theme.latexBlockFontSize,
                        isBlock: true,
                        textColor: colorScheme == .dark ? .white : .black
                    )?.platformImage
                )

        case .codeBlock(let code):
            RenderRegularCodeBlock(code: code)

        case .mermaid(let code):
            // MermaidView registers its own block anchor (with the
            // rendered image for rich copies) and its context menu.
            MermaidView(code: code, theme: theme)

        case .blockQuote(let children):
            RenderBlockQuote(children: children)

        case .orderedList(let startIndex, let items):
            RenderOrderedList(startIndex: startIndex, items: items, depth: 0)

        case .unorderedList(let items):
            RenderUnorderedList(items: items, depth: 0)

        case .table(let table):
            RenderTable(table: table)

        case .thematicBreak:
            Divider().padding(.horizontal, 8)

        case .htmlBlock(let rawHTML):
            RenderHTMLBlock(rawHTML: rawHTML)
        }
    }
}

extension RenderBlock: @preconcurrency Equatable {
    /// `MDBlock` equality is `id + signature`, so unchanged blocks skip
    /// body evaluation during streaming updates.
    static func == (lhs: RenderBlock, rhs: RenderBlock) -> Bool {
        lhs.block == rhs.block
    }
}

// MARK: - Heading

struct RenderHeading: View {
    let level: Int
    let attributed: AttributedString

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        InlineContentView(
            attributed: attributed,
            font: theme.headingFont(level: level)
        )
    }
}

// MARK: - Code Block

struct RenderRegularCodeBlock: View {
    let code: MDCodeBlock

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        HighlightedCodeView(code: code.code, language: code.language, theme: theme, lines: code.lines)
            .makeCanSelectable()
            .contentTransition(.numericText())
            .modifier(CodeBlockContainerModifier(theme: theme, isInteractive: false))
            .contextMenu {
                Button("拷贝全文") {
                    MarkdownCopy.text(code.code)
                }
            }
    }
}

// MARK: - HTML

struct RenderHTMLBlock: View {
    let rawHTML: String

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        SwiftUI.Text(
            AttributedString(
                NSAttributedString(
                    html: rawHTML.data(using: .utf8) ?? Data(),
                    documentAttributes: nil
                ) ?? NSAttributedString(string: rawHTML)
            )
        )
        .font(theme.codeSwiftUIFont)
        .foregroundColor(theme.secondaryTextColor)
        .makeCanSelectable()
    }
}

// MARK: - Block Quote

struct RenderBlockQuote: View {
    let children: [MDBlock]

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownSelectionLinePrefix) private var linePrefix

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.blockQuoteBorderColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: theme.paragraphSpacing / 2) {
                ForEach(children) { child in
                    RenderBlock(block: child).equatable()
                }
            }
            .padding(.leading, 12)
            .environment(\.markdownSelectionLinePrefix, linePrefix + "> ")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Lists

fileprivate let bulletStyles = ["•", "◦", "▪", "▸"]
func bulletForDepth(_ depth: Int) -> String {
    bulletStyles[depth % bulletStyles.count]
}

struct RenderOrderedList: View {
    let startIndex: Int
    let items: [MDListItem]
    let depth: Int

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                RenderListItem(item: item, bullet: "\(index + startIndex).", depth: depth)
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }
}

struct RenderUnorderedList: View {
    let items: [MDListItem]
    let depth: Int

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(items) { item in
                if item.checkbox != nil {
                    RenderTaskListItem(item: item, depth: depth)
                } else {
                    RenderListItem(item: item, bullet: bulletForDepth(depth), depth: depth)
                }
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }
}

struct RenderListItem: View {
    let item: MDListItem
    let bullet: String
    let depth: Int

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(bullet)
                .font(theme.bodySwiftUIFont)
                .foregroundColor(theme.textColor)
                .contentTransition(.numericText(countsDown: true))
                .makeCanSelectable(isBlock: true, blockText: bullet + " ")

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(item.children) { child in
                    RenderListChildBlock(block: child, depth: depth)
                }
            }
        }
    }
}

struct RenderTaskListItem: View {
    let item: MDListItem
    let depth: Int

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.checkbox == .checked ? "checkmark.square.fill" : "square")
                .font(theme.bodySwiftUIFont)
                .foregroundColor(item.checkbox == .checked ? theme.linkColor : theme.secondaryTextColor)
                .frame(width: 20, alignment: .trailing)
                .makeCanSelectable(
                    isBlock: true,
                    blockText: item.checkbox == .checked ? "[x] " : "[ ] "
                )

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(item.children) { child in
                    RenderListChildBlock(block: child, depth: depth)
                }
            }
        }
    }
}

/// List children are pre-flattened blocks; nested lists get `depth + 1`
/// for indentation and bullet style.
struct RenderListChildBlock: View {
    let block: MDBlock
    let depth: Int

    var body: some View {
        switch block.content {
        case .orderedList(let startIndex, let items):
            RenderOrderedList(startIndex: startIndex, items: items, depth: depth + 1)
        case .unorderedList(let items):
            RenderUnorderedList(items: items, depth: depth + 1)
        default:
            RenderBlock(block: block).equatable()
        }
    }
}
