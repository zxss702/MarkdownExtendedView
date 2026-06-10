//
//  MarkdownRenderer+Blocks.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Block Rendering

struct RenderBlock: View {
    let markup: any Markup
    let features: MarkdownBlockFeatures
    let context: MarkdownContext

    var body: some View {
        if let heading = markup as? Heading {
            RenderHeading(heading: heading, features: features, context: context)
        } else if let paragraph = markup as? Paragraph {
            RenderParagraph(paragraph: paragraph, features: features, context: context)
        } else if let codeBlock = markup as? CodeBlock {
            RenderCodeBlock(codeBlock: codeBlock, context: context)
        } else if let blockQuote = markup as? BlockQuote {
            RenderBlockQuote(blockQuote: blockQuote, context: context)
        } else if let orderedList = markup as? OrderedList {
            RenderOrderedList(list: orderedList, depth: 0, context: context)
        } else if let unorderedList = markup as? UnorderedList {
            RenderUnorderedList(list: unorderedList, depth: 0, context: context)
        } else if let table = markup as? Markdown.Table {
            RenderTable(table: table, context: context)
        } else if markup is ThematicBreak {
            Divider().padding(.vertical, 8)
        } else if let htmlBlock = markup as? HTMLBlock {
            SwiftUI.Text(
                AttributedString(
                    NSAttributedString(
                        html: htmlBlock.rawHTML.data(using: .utf8) ?? Data(),
                        documentAttributes: nil
                    ) ?? NSAttributedString(string: htmlBlock.rawHTML)
                )
            )
            .font(context.theme.codeSwiftUIFont)
            .foregroundColor(context.theme.secondaryTextColor)
            .selectionTextPassThrough()
        }
    }
}

// MARK: - Heading

struct RenderHeading: View {
    let heading: Heading
    let features: MarkdownBlockFeatures
    let context: MarkdownContext

    var body: some View {
        BuildInlineText(
            parent: heading,
            features: features,
            context: context
        )
        .font(context.theme.headingSwiftUIFont(level: heading.level))
        .foregroundColor(context.theme.textColor)
        .contentTransition(.numericText())
        .padding(.top, heading.level == 1 ? 16 : 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Paragraph

struct RenderParagraph: View {
    let paragraph: Paragraph
    let features: MarkdownBlockFeatures
    let context: MarkdownContext

    var body: some View {
        let plainText = paragraph.plainText
        if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") {
            let latex = String(plainText.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            LaTeXView(latex: latex, isBlock: true, theme: context.theme)
        } else {
            BuildInlineText(
                parent: paragraph,
                features: features,
                context: context
            )
            .font(context.theme.bodySwiftUIFont)
            .foregroundColor(context.theme.textColor)
            .contentTransition(.numericText())
        }
    }
}

// MARK: - Code Block

struct RenderCodeBlock: View {
    let codeBlock: CodeBlock
    let context: MarkdownContext

    var body: some View {
        if codeBlock.language == "mermaid" {
            RenderMermaidBlock(codeBlock: codeBlock, context: context)
        } else {
            RenderRegularCodeBlock(codeBlock: codeBlock, context: context)
        }
    }
}

struct RenderMermaidBlock: View {
    let codeBlock: CodeBlock
    let context: MarkdownContext
    
    var body: some View {
        MermaidView(code: codeBlock.code, theme: context.theme, viewWidth: context.viewWidth)
    }
}

struct RenderRegularCodeBlock: View {
    let codeBlock: CodeBlock
    let context: MarkdownContext

    var body: some View {
        Group {
            if codeBlock.language != nil {
                HighlightedCodeView(
                    code: codeBlock.code,
                    language: codeBlock.language,
                    theme: context.theme
                )
            } else {
                Text(codeBlock.code.trimmingCharacters(in: .newlines))
                    .font(context.theme.codeBlockSwiftUIFont)
                    .contentTransition(.numericText())
                    .foregroundColor(context.theme.textColor)
            }
        }
        .modifier(CodeBlockContainerModifier(theme: context.theme, isInteractive: false))
    }
}

struct RenderMCodeReferences: View {
    let references: [MCodeReference]
    let context: MarkdownContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                MCodeReferenceBlockView(
                    reference: reference,
                    theme: context.theme,
                    tapHandler: context.MCodeReferenceHandler
                )
            }
        }
    }
}

// MARK: - Block Quote

struct RenderBlockQuote: View {
    let blockQuote: BlockQuote
    let context: MarkdownContext

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(context.theme.blockQuoteBorderColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: context.theme.paragraphSpacing / 2) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    RenderBlock(
                        markup: child,
                        features: computeInlineFeatures(child),
                        context: context
                    )
                }
            }
            .padding(.leading, 12)
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
    let list: OrderedList
    let depth: Int
    let context: MarkdownContext

    var body: some View {
        VStack(alignment: .leading, spacing: context.theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                RenderListItem(item: item, bullet: "\(index + Int(list.startIndex)).", depth: depth, context: context)
            }
        }
        .padding(.leading, depth > 0 ? context.theme.indentation : 0)
    }
}

struct RenderUnorderedList: View {
    let list: UnorderedList
    let depth: Int
    let context: MarkdownContext

    var body: some View {
        VStack(alignment: .leading, spacing: context.theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
                if item.checkbox != nil {
                    RenderTaskListItem(item: item, depth: depth, context: context)
                } else {
                    RenderListItem(item: item, bullet: bulletForDepth(depth), depth: depth, context: context)
                }
            }
        }
        .padding(.leading, depth > 0 ? context.theme.indentation : 0)
    }
}

struct RenderListItem: View {
    let item: ListItem
    let bullet: String
    let depth: Int
    let context: MarkdownContext

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(bullet)
                .font(context.theme.bodySwiftUIFont)
                .contentTransition(.numericText(countsDown: true))
                .foregroundColor(context.theme.textColor)
                .selectionTextPassThrough()

            VStack(alignment: .leading, spacing: context.theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    RenderListChildBlock(markup: child, depth: depth, context: context)
                }
            }
        }
    }
}

struct RenderTaskListItem: View {
    let item: ListItem
    let depth: Int
    let context: MarkdownContext

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.checkbox?.isChecked == true ? "checkmark.square.fill" : "square")
                .font(context.theme.bodySwiftUIFont)
                .foregroundColor(item.checkbox?.isChecked == true ? context.theme.linkColor : context.theme.secondaryTextColor)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: context.theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    RenderListChildBlock(markup: child, depth: depth, context: context)
                }
            }
        }
    }
}

struct RenderListChildBlock: View {
    let markup: any Markup
    let depth: Int
    let context: MarkdownContext

    var body: some View {
        if let nestedOrdered = markup as? OrderedList {
            RenderOrderedList(list: nestedOrdered, depth: depth + 1, context: context)
        } else if let nestedUnordered = markup as? UnorderedList {
            RenderUnorderedList(list: nestedUnordered, depth: depth + 1, context: context)
        } else {
            RenderBlock(markup: markup, features: computeInlineFeatures(markup), context: context)
        }
    }
}
