//
//  MarkdownRenderer+Inlines.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Inline Rendering

fileprivate func extractPlainTextForFeatures(from markup: any Markup) -> String {
    if let plainText = markup as? any PlainTextConvertibleMarkup {
        return plainText.plainText
    }
    return markup.children.map { extractPlainTextForFeatures(from: $0) }.joined()
}

func computeInlineFeatures(_ markup: any Markup) -> MarkdownBlockFeatures {
    var features: MarkdownBlockFeatures = []
    
    // Check LaTeX using the full text of the markup to handle formulas spanning multiple nodes
    let plainText = extractPlainTextForFeatures(from: markup)
    if LaTeXPreprocessor.containsLaTeX(plainText) {
        features.insert(.hasLaTeX)
    }
    
    func visit(_ node: any Markup) {
        if node is Markdown.Image { features.insert(.hasImages) }
        if node is Markdown.Link { features.insert(.hasLinks) }
        if let code = node as? InlineCode, let refs = parseMCodeReferences(from: code.code), !refs.isEmpty {
            features.insert(.hasMCodeReferences)
        }
        for child in node.children {
            visit(child)
        }
    }
    visit(markup)
    
    return features
}

struct BuildInlineText: View {
    let parent: any Markup
    let features: MarkdownBlockFeatures
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        if features.contains(.hasLaTeX) {
            RenderTextWithLaTeX(parent: parent, baseFont: baseFont, baseFontSize: baseFontSize)
        } else if features.contains(.hasMCodeReferences) {
            RenderTextWithLinks(parent: parent, baseFont: baseFont, baseFontSize: baseFontSize)
        } else if features.contains(.hasLinks) {
            RenderTextWithLinks(parent: parent, baseFont: baseFont, baseFontSize: baseFontSize)
        } else if features.contains(.hasImages) {
            RenderTextWithImages(parent: parent, baseFont: baseFont, baseFontSize: baseFontSize)
        } else {
            // Note: Should not be reached because MarkdownTextBuilder handles the simple cases
            EmptyView()
        }
    }
}


struct RenderTextWithImages: View {
    let parent: any Markup
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, baseFont: baseFont, baseFontSize: baseFontSize)
            }
        }
    }
}

struct RenderTextWithLinks: View {
    let parent: any Markup
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, baseFont: baseFont, baseFontSize: baseFontSize)
            }
        }
    }
}

fileprivate struct RenderInlineFlowElement: View {
    let element: InlineFlowElement
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler
    
    var body: some View {
        switch element {
        case .text(let text, let style):
            buildSelectableText(text, style: style)
                .makeCanSelectable()
            
        case .link(let link):
            TappableLinkView(
                link: link,
                theme: theme,
                linkHandler: linkHandler,
                baseURL: baseURL
            )
            .makeCanSelectable(isBlock: true, blockText: link.plainText)
            
        case .codeReference(let reference):
            MCodeReferenceBlockView(
                reference: reference,
                theme: theme,
                tapHandler: MCodeReferenceHandler
            )
            .makeCanSelectable(isBlock: true, blockText: reference.referenceString)
        case .image(let image):
            MarkdownImageView(
                image: image,
                theme: theme,
                baseURL: baseURL
            )
            .makeCanSelectable(isBlock: true, blockText: "[\(image.plainText)]")
            
        case .latex(let latex, let isBlock):
            if isBlock {
                LaTeXView(latex: latex, isBlock: true, theme: theme, overrideFontSize: baseFontSize)
                    .layoutValue(key: BlockFormulaKey.self, value: true)
                    .makeCanSelectable(isBlock: true, blockText: "$\(latex)$")
            } else {
                LaTeXView(latex: latex, isBlock: false, theme: theme, overrideFontSize: baseFontSize)
                    .layoutValue(key: InlineFormulaKey.self, value: true)
                    .makeCanSelectable(isBlock: true, blockText: "$\(latex)$")
            }
            
        case .lineBreak:
            Color.clear
                .frame(width: 0, height: theme.bodyFont.markdownLineHeight)
                .layoutValue(key: FlowLineBreakLayoutValueKey.self, value: true)
        }
    }
    
    private func buildSelectableText(_ text: String, style: InlineTextStyle) -> SwiftUI.Text {
        let baseFont = self.baseFont ?? theme.bodySwiftUIFont
        var combinedAttr = AttributedString()
        var mappings: [GlobalSelectionCache.CharacterMapping] = []
        
        for (i, char) in text.enumerated() {
            var charAttr = AttributedString(String(char))
            if style.contains(.code) {
                charAttr.font = baseFont
                charAttr.inlinePresentationIntent = .code
            } else {
                charAttr.font = baseFont
                if style.contains(.bold) { charAttr.font = charAttr.font?.bold() }
                if style.contains(.italic) { charAttr.font = charAttr.font?.italic() }
            }
            if style.contains(.strikethrough) { charAttr.strikethroughStyle = .single }
            charAttr.foregroundColor = theme.textColor
            
            combinedAttr.append(charAttr)
            mappings.append(.init(index: i, char: String(char)))
        }
        
        return SwiftUI.Text(combinedAttr).customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
    }
}

struct RenderTextWithLaTeX: View {
    let parent: any Markup
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        let plainText = extractPlainText(from: parent)
        let segments = LaTeXPreprocessor.extractSegments(from: plainText)

        FlowLayout(
            spacing: 0,
            lineSpacing: theme.paragraphSpacing,
            minimumLineHeight: theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: segments)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, baseFont: baseFont, baseFontSize: baseFontSize)
            }
        }
    }
}

fileprivate func buildAttributedText(from parent: any Markup, theme: MarkdownTheme) -> SwiftUI.Text {
    var result = SwiftUI.Text("")
    for child in parent.children {
        result = result + renderInlineElement(child, theme: theme)
    }
    return result
}

fileprivate func renderInlineElement(_ element: any Markup, theme: MarkdownTheme) -> SwiftUI.Text {
    switch element {
    case let text as Markdown.Text:
        return SwiftUI.Text(text.string)

    case let strong as Strong:
        let inner = buildTextFromChildren(strong, theme: theme)
        return inner.bold()

    case let emphasis as Emphasis:
        let inner = buildTextFromChildren(emphasis, theme: theme)
        return inner.italic()

    case let strikethrough as Strikethrough:
        let inner = buildTextFromChildren(strikethrough, theme: theme)
        return inner.strikethrough()

    case let code as InlineCode:
        return SwiftUI.Text(code.code)
            .font(theme.codeSwiftUIFont)
        
    case let link as Markdown.Link:
        let inner = buildTextFromChildren(link, theme: theme)
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

fileprivate func buildTextFromChildren(_ parent: any Markup, theme: MarkdownTheme) -> SwiftUI.Text {
    parent.children.reduce(SwiftUI.Text("")) { result, child in
        result + renderInlineElement(child, theme: theme)
    }
}

fileprivate func extractPlainText(from markup: any Markup) -> String {
    if let plainText = markup as? any PlainTextConvertibleMarkup {
        return plainText.plainText
    }
    return markup.children.map { extractPlainText(from: $0) }.joined()
}

func flowInlineElements(from parent: any Markup) -> [InlineFlowElement] {
    parent.children.flatMap {
        flowInlineElements(from: $0, style: [])
    }
}

func flowInlineElements(
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

func flowInlineElements(from segments: [LaTeXPreprocessor.Segment]) -> [InlineFlowElement] {
    segments.flatMap { segment in
        switch segment {
        case .text(let text):
            return textInlineFlowElements(text, style: [])
        case .latex(let latex, let isBlock):
            return [.latex(latex, isBlock)]
        }
    }
}

fileprivate func textInlineFlowElements(_ text: String, style: InlineTextStyle) -> [InlineFlowElement] {
    MarkdownInlineTextWrapping.units(in: text).map {
        .text($0, style)
    }
}

fileprivate func styledText(_ text: String, style: InlineTextStyle, theme: MarkdownTheme) -> SwiftUI.Text {
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

struct BlockFormulaKey: LayoutValueKey {
    static let defaultValue: Bool = false
}
