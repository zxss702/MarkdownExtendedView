//
//  MarkdownRenderer+Inlines.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Inline Rendering

func computeInlineFeatures(_ markup: any Markup) -> MarkdownBlockFeatures {
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

struct BuildInlineText: View {
    let parent: any Markup
    let features: MarkdownBlockFeatures
    let context: MarkdownContext

    var body: some View {
        if features.contains(.hasLaTeX) {
            RenderTextWithLaTeX(parent: parent, context: context)
        } else if features.contains(.hasMCodeReferences) {
            RenderTextWithLinks(parent: parent, context: context)
        } else if features.contains(.hasLinks) {
            RenderTextWithLinks(parent: parent, context: context)
        } else if features.contains(.hasImages) {
            RenderTextWithImages(parent: parent, context: context)
        } else {
            buildAttributedText(from: parent, theme: context.theme).selectionTextPassThrough()
        }
    }
}


struct RenderTextWithImages: View {
    let parent: any Markup
    let context: MarkdownContext

    var body: some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: context.theme.paragraphSpacing,
            minimumLineHeight: context.theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, context: context)
            }
        }
    }
}

struct RenderTextWithLinks: View {
    let parent: any Markup
    let context: MarkdownContext

    var body: some View {
        FlowLayout(
            spacing: 0,
            lineSpacing: context.theme.paragraphSpacing,
            minimumLineHeight: context.theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: parent)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, context: context)
            }
        }
    }
}

fileprivate struct RenderInlineFlowElement: View {
    let element: InlineFlowElement
    let context: MarkdownContext

    var body: some View {
        switch element {
        case .text(let text, let style):
            styledText(text, style: style, theme: context.theme)
                .selectionTextPassThrough()

        case .link(let link):
            TappableLinkView(
                link: link,
                theme: context.theme,
                linkHandler: context.linkHandler,
                baseURL: context.baseURL
            )

        case .codeReference(let reference):
            MCodeReferenceBlockView(
                reference: reference,
                theme: context.theme,
                tapHandler: context.MCodeReferenceHandler
            )

        case .image(let image):
            MarkdownImageView(
                image: image,
                theme: context.theme,
                baseURL: context.baseURL
            )

        case .latex(let latex, let isBlock):
            if isBlock {
                LaTeXView(latex: latex, isBlock: true, theme: context.theme)
                    .layoutValue(key: BlockFormulaKey.self, value: true)
            } else {
                LaTeXView(latex: latex, isBlock: false, theme: context.theme)
                    .layoutValue(key: InlineFormulaKey.self, value: true)
            }

        case .lineBreak:
            Color.clear
                .frame(width: 0, height: context.theme.bodyFont.markdownLineHeight)
                .layoutValue(key: FlowLineBreakLayoutValueKey.self, value: true)
        }
    }
}

struct RenderTextWithLaTeX: View {
    let parent: any Markup
    let context: MarkdownContext

    var body: some View {
        let plainText = extractPlainText(from: parent)
        let segments = LaTeXPreprocessor.extractSegments(from: plainText)

        FlowLayout(
            spacing: 0,
            lineSpacing: context.theme.paragraphSpacing,
            minimumLineHeight: context.theme.bodyFont.markdownLineHeight
        ) {
            let elements = flowInlineElements(from: segments)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                RenderInlineFlowElement(element: element, context: context)
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
