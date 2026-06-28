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
    
    func build(from markup: any Markup) -> SwiftUI.Text {
        // We first convert to plain text to check for LaTeX
        let plainText = extractPlainText(from: markup)
        if LaTeXPreprocessor.containsLaTeX(plainText) {
            let segments = LaTeXPreprocessor.extractSegments(from: plainText)
            return buildText(from: segments)
        }
        
        // Otherwise, render normally
        return buildTextFromChildren(markup, style: .init())
    }
    
    private func buildText(from segments: [LaTeXPreprocessor.Segment]) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for segment in segments {
            switch segment {
            case .text(let text):
                result = result + styledText(text, style: .init())
                
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
                
                imageText = imageText.customAttribute(MarkdownCharacterAttribute(index: tracker.offset, char: "$\(latex)$"))
                
                tracker.offset += "$\(latex)$".count
                
                result = result + imageText
            }
        }
        return result
    }
    
    private func buildTextFromChildren(_ parent: any Markup, style: InlineTextStyle) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for child in parent.children {
            result = result + renderInlineElement(child, style: style)
        }
        return result
    }
    
    private func renderInlineElement(_ element: any Markup, style: InlineTextStyle) -> SwiftUI.Text {
        switch element {
        case let text as Markdown.Text:
            return styledText(text.string, style: style)
            
        case let strong as Strong:
            return buildTextFromChildren(strong, style: style.union(.bold))
            
        case let emphasis as Emphasis:
            return buildTextFromChildren(emphasis, style: style.union(.italic))
            
        case let strikethrough as Strikethrough:
            return buildTextFromChildren(strikethrough, style: style.union(.strikethrough))
            
        case let code as InlineCode:
            return styledText(code.code, style: style.union(.code))
            
        case let link as Markdown.Link:
            return styledLinkText(link, style: style)
            
        case _ as SoftBreak:
            return styledText("\n", style: style)
            
        case _ as LineBreak:
            return styledText("\n", style: style)
            
        case let image as Markdown.Image:
            return styledText("[\(image.plainText)]", style: style).foregroundColor(theme.secondaryTextColor)
            
        default:
            if let plainText = element as? any PlainTextConvertibleMarkup {
                return styledText(plainText.plainText, style: style)
            }
            return SwiftUI.Text("")
        }
    }
    
    // Keep track of the character index for the entire paragraph
    private class IndexTracker {
        var offset: Int = 0
    }
    private let tracker = IndexTracker()
    
    /// Build styled text using Text concatenation with .customAttribute() for each character.
    /// This is the CORRECT way to set TextAttribute values so they survive to TextRenderer.
    private func styledText(_ string: String, style: InlineTextStyle) -> SwiftUI.Text {
        let baseFont = self.baseFont ?? theme.bodySwiftUIFont
        var pieces: [SwiftUI.Text] = []
        pieces.reserveCapacity(string.count)
        
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
            charAttr.foregroundColor = theme.textColor
            
            let piece = SwiftUI.Text(charAttr).customAttribute(MarkdownCharacterAttribute(index: tracker.offset, char: String(char)))
            
            tracker.offset += 1
            pieces.append(piece)
        }
        
        return combineTexts(pieces)
    }
    
    /// Combine an array of SwiftUI.Text into a balanced tree to prevent stack overflows
    /// when rendering extremely long text (which causes O(N) recursion in SwiftUI's resolve).
    private func combineTexts(_ texts: [SwiftUI.Text]) -> SwiftUI.Text {
        guard !texts.isEmpty else { return SwiftUI.Text("") }
        var current = texts
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
        return current[0]
    }
    
    /// Build styled link text using Text concatenation with .customAttribute().
    private func styledLinkText(_ link: Markdown.Link, style: InlineTextStyle) -> SwiftUI.Text {
        let plainText = extractPlainText(from: link)
        let baseFont = self.baseFont ?? theme.bodySwiftUIFont
        var pieces: [SwiftUI.Text] = []
        pieces.reserveCapacity(plainText.count)
        
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
            
            let piece = SwiftUI.Text(charAttr).customAttribute(MarkdownCharacterAttribute(index: tracker.offset, char: String(char)))
            
            tracker.offset += 1
            pieces.append(piece)
        }
        
        return combineTexts(pieces)
    }
    
    private func extractPlainText(from markup: any Markup) -> String {
        if let plainText = markup as? any PlainTextConvertibleMarkup {
            return plainText.plainText
        }
        return markup.children.map { extractPlainText(from: $0) }.joined()
    }
}
