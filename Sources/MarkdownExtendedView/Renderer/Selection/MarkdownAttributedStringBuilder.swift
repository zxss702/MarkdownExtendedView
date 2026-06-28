// MarkdownTextBuilder.swift
// MarkdownExtendedView

import SwiftUI
import Markdown

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Builds a single concatenated SwiftUI.Text from Markdown AST inline nodes.
/// Uses Text.customAttribute() to tag each character for TextRenderer extraction.
struct MarkdownTextBuilder {
    let theme: MarkdownTheme
    let baseURL: URL?
    var baseFont: Font? = nil
    var baseFontSize: CGFloat? = nil
    
    // Keep track of the character index for the entire paragraph and buffer strings
    private class BuilderState {
        var offset: Int = 0
        var mappings: [GlobalSelectionCache.CharacterMapping] = []
        var currentAttrString = AttributedString()
        var pieces: [SwiftUI.Text] = []
        
        func flush() {
            if !currentAttrString.characters.isEmpty {
                pieces.append(SwiftUI.Text(currentAttrString))
                currentAttrString = AttributedString()
            }
        }
        
        func appendImageText(_ text: SwiftUI.Text) {
            flush()
            pieces.append(text)
        }
        
        func buildFinalText() -> SwiftUI.Text {
            flush()
            guard !pieces.isEmpty else { return SwiftUI.Text("") }
            
            var current = pieces
            while current.count > 1 {
                var next: [SwiftUI.Text] = []
                next.reserveCapacity((current.count + 1) / 2)
                for i in stride(from: 0, to: current.count, by: 2) {
                    if i + 1 < current.count {
                        next.append(current[i] + current[i + 1])
                    } else {
                        next.append(current[i])
                    }
                }
                current = next
            }
            return current[0].customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
        }
    }
    private let state = BuilderState()
    
    func build(from markup: any Markup) -> SwiftUI.Text {
        let plainText = extractPlainText(from: markup)
        if LaTeXPreprocessor.containsLaTeX(plainText) {
            let segments = LaTeXPreprocessor.extractSegments(from: plainText)
            buildText(from: segments)
        } else {
            buildTextFromChildren(markup, style: .init())
        }
        
        return state.buildFinalText()
    }
    
    private func buildText(from segments: [LaTeXPreprocessor.Segment]) {
        for segment in segments {
            switch segment {
            case .text(let text):
                styledText(text, style: .init())
                
            case .latex(let latex, _):
                // Render inline latex to Image
                let fontSize = self.baseFontSize ?? theme.latexInlineFontSize
                #if canImport(AppKit)
                let mtColor = NSColor(theme.textColor)
                #elseif canImport(UIKit)
                let mtColor = UIColor(theme.textColor)
                #endif
                
                let image = MTMathImage(latex: latex, fontSize: fontSize, textColor: mtColor, labelMode: .text)
                let displayList = MathDisplayCache.shared.getDisplay(latex: latex, fontSize: fontSize, isBlock: false)
                // The bottom of the image sits on the text baseline by default.
                // We shift the image down by its descent so its internal baseline matches the text baseline.
                let descent = displayList?.descent ?? 0
                
                var imageText: SwiftUI.Text
                if let img = image.asImage().1 {
                    #if canImport(AppKit)
                    imageText = SwiftUI.Text(Image(nsImage: img)).baselineOffset(-descent)
                    #elseif canImport(UIKit)
                    imageText = SwiftUI.Text(Image(uiImage: img)).baselineOffset(-descent)
                    #endif
                } else {
                    imageText = SwiftUI.Text("$\(latex)$")
                }
                
                state.mappings.append(.init(index: state.offset, char: "$\(latex)$"))
                state.offset += "$\(latex)$".count
                
                state.appendImageText(imageText)
            }
        }
    }
    
    private func buildTextFromChildren(_ parent: any Markup, style: InlineTextStyle) {
        for child in parent.children {
            renderInlineElement(child, style: style)
        }
    }
    
    private func renderInlineElement(_ element: any Markup, style: InlineTextStyle) {
        switch element {
        case let text as Markdown.Text:
            styledText(text.string, style: style)
            
        case let strong as Strong:
            buildTextFromChildren(strong, style: style.union(.bold))
            
        case let emphasis as Emphasis:
            buildTextFromChildren(emphasis, style: style.union(.italic))
            
        case let strikethrough as Strikethrough:
            buildTextFromChildren(strikethrough, style: style.union(.strikethrough))
            
        case let code as InlineCode:
            styledText(code.code, style: style.union(.code))
            
        case let link as Markdown.Link:
            styledLinkText(link, style: style)
            
        case _ as SoftBreak:
            styledText("\n", style: style)
            
        case _ as LineBreak:
            styledText("\n", style: style)
            
        case let image as Markdown.Image:
            styledText("[\(image.plainText)]", style: style, color: theme.secondaryTextColor)
            
        default:
            if let plainText = element as? any PlainTextConvertibleMarkup {
                styledText(plainText.plainText, style: style)
            }
        }
    }
    
    private func styledText(_ string: String, style: InlineTextStyle, color: Color? = nil) {
        let baseFont = self.baseFont ?? theme.bodySwiftUIFont
        
        for char in string {
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
            charAttr.foregroundColor = color ?? theme.textColor
            
            state.mappings.append(.init(index: state.offset, char: String(char)))
            state.offset += 1
            state.currentAttrString.append(charAttr)
        }
    }
    
    private func styledLinkText(_ link: Markdown.Link, style: InlineTextStyle) {
        let plainText = extractPlainText(from: link)
        let baseFont = self.baseFont ?? theme.bodySwiftUIFont
        
        for char in plainText {
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
            charAttr.foregroundColor = theme.linkColor
            if let dest = link.destination, let url = URL(string: dest) {
                charAttr.link = url
            }
            
            state.mappings.append(.init(index: state.offset, char: String(char)))
            state.offset += 1
            state.currentAttrString.append(charAttr)
        }
    }
    
    private func extractPlainText(from markup: any Markup) -> String {
        if let plainText = markup as? any PlainTextConvertibleMarkup {
            return plainText.plainText
        }
        return markup.children.map { extractPlainText(from: $0) }.joined()
    }
}
