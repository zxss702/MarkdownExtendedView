// LaTeXPreprocessor.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import Foundation

/// Handles LaTeX detection and extraction from Markdown content.
///
/// Since swift-markdown doesn't recognize LaTeX syntax ($...$ and $$...$$),
/// this preprocessor identifies LaTeX regions for special handling during rendering.
nonisolated enum LaTeXPreprocessor {

    // MARK: - Public API

    /// Process content for markdown parsing.
    ///
    /// Currently returns content as-is since we handle LaTeX during rendering.
    /// This method is a hook for future preprocessing if needed.
    ///
    /// - Parameter content: The raw Markdown content.
    /// - Returns: Processed content ready for markdown parsing.
    static func process(_ content: String) -> String {
        // For now, return as-is. LaTeX is handled during text rendering.
        return content
    }

    /// Extracts LaTeX segments from a text string.
    ///
    /// Identifies both inline ($...$) and display ($$...$$) LaTeX and returns
    /// an array of segments, each marked as either text or LaTeX.
    ///
    /// - Parameter text: The text to scan for LaTeX.
    /// - Returns: Array of segments in order.
    static func extractSegments(from text: String) -> [Segment] {
        var segments: [Segment] = []
        var currentIndex = text.startIndex
        var textBuffer = ""

        while currentIndex < text.endIndex {
            // Check for display math ($$...$$) first
            if let displayMatch = findDisplayMath(in: text, from: currentIndex) {
                // Flush text buffer
                if !textBuffer.isEmpty {
                    segments.append(.text(textBuffer))
                    textBuffer = ""
                }
                segments.append(.latex(displayMatch.content, isBlock: true))
                currentIndex = displayMatch.endIndex
                continue
            }

            // Check for inline math ($...$)
            if let inlineMatch = findInlineMath(in: text, from: currentIndex) {
                // Flush text buffer
                if !textBuffer.isEmpty {
                    segments.append(.text(textBuffer))
                    textBuffer = ""
                }
                segments.append(.latex(inlineMatch.content, isBlock: false))
                currentIndex = inlineMatch.endIndex
                continue
            }

            // Regular character - add to buffer
            textBuffer.append(text[currentIndex])
            currentIndex = text.index(after: currentIndex)
        }

        // Flush remaining text buffer
        if !textBuffer.isEmpty {
            segments.append(.text(textBuffer))
        }

        return segments
    }

    /// Checks if a string contains any LaTeX.
    ///
    /// - Parameter text: The text to check.
    /// - Returns: True if the text contains LaTeX delimiters.
    static func containsLaTeX(_ text: String) -> Bool {
        text.contains("$")
    }

    // MARK: - Types

    /// A segment of text that is either plain text or LaTeX.
    enum Segment: Equatable, Sendable {
        /// Plain text content.
        case text(String)
        /// LaTeX content with flag for block (display) vs inline.
        case latex(String, isBlock: Bool)
    }

    // MARK: - Private Helpers

    private struct Match {
        let content: String
        let endIndex: String.Index
    }

    /// Find display math ($$...$$) starting at the given index.
    private static func findDisplayMath(in text: String, from startIndex: String.Index) -> Match? {
        // Must start with "$$"
        guard text.distance(from: startIndex, to: text.endIndex) >= 2 else { return nil }
        
        let startPlus2 = text.index(startIndex, offsetBy: 2)
        guard text[startIndex..<startPlus2] == "$$" else { return nil }
        
        // Find closing "$$"
        if let range = text.range(of: "$$", range: startPlus2..<text.endIndex) {
            let content = String(text[startPlus2..<range.lowerBound])
            return Match(content: content.trimmingCharacters(in: .whitespacesAndNewlines), endIndex: range.upperBound)
        }
        
        return nil
    }

    private static func findInlineMath(in text: String, from startIndex: String.Index) -> Match? {
        guard startIndex < text.endIndex, text[startIndex] == "$" else { return nil }
        
        // Ensure not "$$"
        let nextIndex = text.index(after: startIndex)
        if nextIndex < text.endIndex && text[nextIndex] == "$" { return nil }
        
        guard nextIndex < text.endIndex else { return nil }
        if text[nextIndex].isWhitespace { return nil } // Content shouldn't start with space
        
        var searchIndex = nextIndex
        while let range = text.range(of: "$", range: searchIndex..<text.endIndex) {
            let matchIndex = range.lowerBound
            
            // Check it's not escaped
            var isEscaped = false
            var escapeCheck = text.index(before: matchIndex)
            var backslashCount = 0
            while escapeCheck >= nextIndex && text[escapeCheck] == "\\" {
                backslashCount += 1
                if escapeCheck == nextIndex { break }
                escapeCheck = text.index(before: escapeCheck)
            }
            if backslashCount % 2 != 0 {
                isEscaped = true
            }
            
            if isEscaped {
                searchIndex = range.upperBound
                continue
            }
            
            // Check it's not "$$"
            if range.upperBound < text.endIndex && text[range.upperBound] == "$" {
                searchIndex = text.index(after: range.upperBound)
                continue
            }
            
            // Check content doesn't end with space
            let prevIndex = text.index(before: matchIndex)
            if prevIndex >= nextIndex && text[prevIndex].isWhitespace {
                searchIndex = range.upperBound
                continue
            }
            
            // Don't allow newlines in inline math
            let content = String(text[nextIndex..<matchIndex])
            if content.isEmpty || content.contains(where: { $0.isNewline }) {
                return nil
            }
            
            return Match(content: content, endIndex: range.upperBound)
        }
        
        return nil
    }
}
