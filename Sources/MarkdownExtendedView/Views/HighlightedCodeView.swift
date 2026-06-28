// HighlightedCodeView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI

/// A view that renders syntax-highlighted code.
///
/// This view tokenizes code using the ``SyntaxHighlighter`` and renders
/// each token with the appropriate color from the theme's ``SyntaxColors``.
public struct HighlightedCodeView: View {

    private let code: String
    private let language: String?
    private let theme: MarkdownTheme
    
    @State private var resolvedLines: [[Token]]?

    public init(code: String, language: String?, theme: MarkdownTheme) {
        self.code = code
        self.language = language
        self.theme = theme
        
        let normalizedCode = code.trimmingCharacters(in: .newlines)
        let cacheKey = Self.cacheKey(for: normalizedCode, language: language)
        if let cachedLines = HighlightedCodeSnapshotCache.shared.object(forKey: cacheKey as NSString)?.lines {
            self._resolvedLines = State(initialValue: cachedLines)
        } else {
            self._resolvedLines = State(initialValue: nil)
        }
    }
    
    public var body: some View {
        Group {
            if let resolvedLines {
                buildText(from: resolvedLines)
            } else {
                SwiftUI.Text(code.trimmingCharacters(in: .newlines))
                    .foregroundColor(theme.textColor)
            }
        }
        .font(theme.codeBlockSwiftUIFont)
        .codeSelectionTextPassThrough()
        .task(id: code) {
            let normalizedCode = code.trimmingCharacters(in: .newlines)
            let cacheKey = Self.cacheKey(for: normalizedCode, language: language)
            
            let computedLines = await Task.detached(priority: .userInitiated) {
                Self.makeHighlightedLines(code: normalizedCode, language: language)
            }.value
            
            await MainActor.run {
                HighlightedCodeSnapshotCache.shared.setObject(
                    HighlightedCodeSnapshot(lines: computedLines),
                    forKey: cacheKey as NSString
                )
                self.resolvedLines = computedLines
            }
        }
    }
    
    private func buildText(from lines: [[Token]]) -> SwiftUI.Text {
        var combinedText = SwiftUI.Text("")
        var offset = 0
        
        for (index, line) in lines.enumerated() {
            if index > 0 {
                var nl = SwiftUI.Text("\n").customAttribute(MarkdownCharacterAttribute(index: offset, char: "\n"))
                combinedText = combinedText + nl
                offset += 1
            }
            if line.isEmpty {
                // Not adding space for empty line, just newline which we already added
            } else {
                for token in line {
                    let color = Self.color(for: token.type, theme: theme)
                    for char in token.text {
                        var charAttr = AttributedString(String(char))
                        charAttr.foregroundColor = color
                        var piece = SwiftUI.Text(charAttr).customAttribute(MarkdownCharacterAttribute(index: offset, char: String(char)))
                        combinedText = combinedText + piece
                        offset += 1
                    }
                }
            }
        }
        return combinedText
    }

    private static func color(for tokenType: TokenType, theme: MarkdownTheme) -> Color {
        switch tokenType {
        case .keyword:
            return theme.syntaxColors.keyword
        case .string:
            return theme.syntaxColors.string
        case .comment:
            return theme.syntaxColors.comment
        case .number:
            return theme.syntaxColors.number
        case .type:
            return theme.syntaxColors.type
        case .function:
            return theme.syntaxColors.function
        case .plain:
            return theme.syntaxColors.plain
        }
    }

    nonisolated private static func makeHighlightedLines(code: String, language: String?) -> [[Token]] {
        let tokens = SyntaxHighlighter().tokenize(code, language: language)
        return splitIntoLines(tokens)
    }

    static func cacheKey(for code: String, language: String?) -> String {
        var hasher = Hasher()
        hasher.combine(code)
        let codeHash = hasher.finalize()
        return "\(language ?? "plain")::\(codeHash)"
    }

    /// Splits tokens into lines, preserving token structure.
    nonisolated static func splitIntoLines(_ tokens: [Token]) -> [[Token]] {
            var lines: [[Token]] = [[]]

            for token in tokens {
                let parts = token.text.components(separatedBy: "\n")
                for (index, part) in parts.enumerated() {
                    if index > 0 {
                        lines.append([])
                    }
                    if !part.isEmpty {
                        lines[lines.count - 1].append(Token(text: part, type: token.type))
                    }
                }
            }

            return lines
    }
}

private final class HighlightedCodeSnapshotCache {
    @MainActor static let shared: NSCache<NSString, HighlightedCodeSnapshot> = {
        let cache = NSCache<NSString, HighlightedCodeSnapshot>()
        cache.countLimit = 128
        return cache
    }()
}

private final class HighlightedCodeSnapshot: NSObject {
    let lines: [[Token]]

    init(lines: [[Token]]) {
        self.lines = lines
    }
}

private extension View {
    @ViewBuilder
    func codeSelectionTextPassThrough() -> some View {
#if os(macOS)
        self
            .pointerStyle(.horizontalText)
#else
        self
#endif
    }
}
