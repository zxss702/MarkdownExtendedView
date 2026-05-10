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

    private let theme: MarkdownTheme
    @State private var lines: [[Token]]

    public init(code: String, language: String?, theme: MarkdownTheme, highlightedLines: [[Token]]? = nil) {
        self.theme = theme

        let resolvedLines: [[Token]]
        if let highlightedLines {
            resolvedLines = highlightedLines
        } else {
            let normalizedCode = code.trimmingCharacters(in: .newlines)
            let cacheKey = Self.cacheKey(for: normalizedCode, language: language)
            let cachedLines = HighlightedCodeSnapshotCache.shared.object(forKey: cacheKey as NSString)?.lines
            let computedLines = cachedLines ?? Self.makeHighlightedLines(
                code: normalizedCode,
                language: language
            )

            if cachedLines == nil {
                HighlightedCodeSnapshotCache.shared.setObject(
                    HighlightedCodeSnapshot(lines: computedLines),
                    forKey: cacheKey as NSString
                )
            }

            resolvedLines = computedLines
        }

        _lines = State(initialValue: resolvedLines)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.codeLineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, lineTokens in
                lineView(for: lineTokens)
            }
        }
    }

    @ViewBuilder
    private func lineView(for tokens: [Token]) -> some View {
        if tokens.isEmpty {
            Text(" ")
                .font(theme.codeBlockSwiftUIFont)
                .codeSelectionTextPassThrough()
                .contentTransition(.numericText(countsDown: true))
        } else {
            tokens.reduce(SwiftUI.Text("")) { result, token in
                result + SwiftUI.Text(token.text)
                    .foregroundColor(color(for: token.type))
            }
            .font(theme.codeBlockSwiftUIFont)
            .codeSelectionTextPassThrough()
            .contentTransition(.numericText(countsDown: true))
        }
    }

    private func color(for tokenType: TokenType) -> Color {
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

    private static func makeHighlightedLines(code: String, language: String?) -> [[Token]] {
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
            .allowsHitTesting(false)
            .pointerStyle(.horizontalText)
#else
        self
            .allowsHitTesting(false)
#endif
    }
}
