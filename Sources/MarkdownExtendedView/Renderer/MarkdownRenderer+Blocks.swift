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
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        if let heading = markup as? Heading {
            RenderHeading(heading: heading, features: features)
        } else if let paragraph = markup as? Paragraph {
            RenderParagraph(paragraph: paragraph, features: features)
        } else if let codeBlock = markup as? CodeBlock {
            RenderCodeBlock(codeBlock: codeBlock)
        } else if let blockQuote = markup as? BlockQuote {
            RenderBlockQuote(blockQuote: blockQuote)
        } else if let orderedList = markup as? OrderedList {
            RenderOrderedList(list: orderedList, depth: 0)
        } else if let unorderedList = markup as? UnorderedList {
            RenderUnorderedList(list: unorderedList, depth: 0)
        } else if let table = markup as? Markdown.Table {
            RenderTable(table: table)
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
            .font(theme.codeSwiftUIFont)
            .foregroundColor(theme.secondaryTextColor)
            .selectionTextPassThrough()
        }
    }
}

// MARK: - Heading

struct RenderHeading: View {
    let heading: Heading
    let features: MarkdownBlockFeatures
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    
    var body: some View {
        let nativeFont = theme.headingFont(level: heading.level)
        let baseFontSize = nativeFont.pointSize
        
        if features.contains(.hasMCodeReferences) || features.contains(.hasImages) || features.contains(.hasLinks) {
            BuildInlineText(parent: heading, features: features, baseFont: theme.headingSwiftUIFont(level: heading.level), baseFontSize: baseFontSize)
        } else {
            MarkdownTextBuilder(theme: theme, baseURL: baseURL, baseFont: theme.headingSwiftUIFont(level: heading.level), baseFontSize: baseFontSize).build(from: heading)
                .font(theme.headingSwiftUIFont(level: heading.level))
                .makeCanSelectable()
        }
    }
}

// MARK: - Paragraph

struct RenderParagraph: View {
    let paragraph: Paragraph
    let features: MarkdownBlockFeatures
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    
    var body: some View {
        let plainText = paragraph.plainText
        if plainText.hasPrefix("$$") && plainText.hasSuffix("$$") {
            let latex = String(plainText.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            LaTeXView(latex: latex, isBlock: true, theme: theme)
                .makeCanSelectable(isBlock: true, blockText: "$\(latex)$")
        } else if features.contains(.hasMCodeReferences) || features.contains(.hasImages) || features.contains(.hasLinks) {
            BuildInlineText(parent: paragraph, features: features, baseFont: theme.bodySwiftUIFont, baseFontSize: theme.bodyFont.pointSize)
        } else {
            MarkdownTextBuilder(theme: theme, baseURL: baseURL, baseFont: theme.bodySwiftUIFont, baseFontSize: theme.bodyFont.pointSize).build(from: paragraph)
                .font(theme.bodySwiftUIFont)
                .makeCanSelectable()
        }
    }
}

// MARK: - Code Block

struct RenderCodeBlock: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        if codeBlock.language == "mermaid" {
            RenderMermaidBlock(codeBlock: codeBlock)
        } else {
            RenderRegularCodeBlock(codeBlock: codeBlock)
        }
    }
}

struct RenderMermaidBlock: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler
    
    var body: some View {
        MermaidView(code: codeBlock.code, theme: theme, viewWidth: 1024)
            .makeCanSelectable(isBlock: true, blockText: codeBlock.code)
    }
}

struct RenderRegularCodeBlock: View {
    let codeBlock: CodeBlock
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        buildCodeText()
            .makeCanSelectable()
            .contentTransition(.numericText())
            .modifier(CodeBlockContainerModifier(theme: theme, isInteractive: false))
    }
    
    @ViewBuilder
    private func buildCodeText() -> some View {
        if codeBlock.language != nil {
            HighlightedCodeView(
                code: codeBlock.code,
                language: codeBlock.language,
                theme: theme
            )
        } else {
            buildPlainCodeText()
        }
    }
    
    private func buildPlainCodeText() -> SwiftUI.Text {
        var combinedText = SwiftUI.Text("")
        let plainString = codeBlock.code.trimmingCharacters(in: .newlines)
        var offset = 0
        for char in plainString {
            var charAttr = AttributedString(String(char))
            charAttr.font = theme.codeBlockSwiftUIFont
            charAttr.foregroundColor = theme.textColor
            let piece = SwiftUI.Text(charAttr).customAttribute(MarkdownCharacterAttribute(index: offset, char: String(char)))
            combinedText = combinedText + piece
            offset += 1
        }
        return combinedText
    }
}

struct RenderMCodeReferences: View {
    let references: [MCodeReference]
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
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
}

// MARK: - Block Quote

struct RenderBlockQuote: View {
    let blockQuote: BlockQuote
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.blockQuoteBorderColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: theme.paragraphSpacing / 2) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    RenderBlock(
                        markup: child,
                        features: computeInlineFeatures(child),
                        
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
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                RenderListItem(item: item, bullet: "\(index + Int(list.startIndex)).", depth: depth)
            }
        }
        .padding(.leading, depth > 0 ? theme.indentation : 0)
    }
}

struct RenderUnorderedList: View {
    let list: UnorderedList
    let depth: Int
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        VStack(alignment: .leading, spacing: theme.listItemSpacing) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
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
    let item: ListItem
    let bullet: String
    let depth: Int
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            let t = Text(bullet)
                .font(theme.bodySwiftUIFont)
                .foregroundColor(theme.textColor)
            
           
            if item.parent is OrderedList {
                t
                    .contentTransition(.numericText(countsDown: true))
                    .makeCanSelectable(isBlock: true, blockText: bullet)
            } else {
                t
                    .contentTransition(.numericText(countsDown: true))
            }

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    RenderListChildBlock(markup: child, depth: depth)
                }
            }
        }
    }
}

struct RenderTaskListItem: View {
    let item: ListItem
    let depth: Int
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.checkbox?.isChecked == true ? "checkmark.square.fill" : "square")
                .font(theme.bodySwiftUIFont)
                .foregroundColor(item.checkbox?.isChecked == true ? theme.linkColor : theme.secondaryTextColor)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: theme.listItemSpacing) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    RenderListChildBlock(markup: child, depth: depth)
                }
            }
        }
    }
}

struct RenderListChildBlock: View {
    let markup: any Markup
    let depth: Int
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        if let nestedOrdered = markup as? OrderedList {
            RenderOrderedList(list: nestedOrdered, depth: depth + 1)
        } else if let nestedUnordered = markup as? UnorderedList {
            RenderUnorderedList(list: nestedUnordered, depth: depth + 1)
        } else {
            RenderBlock(markup: markup, features: computeInlineFeatures(markup))
        }
    }
}
