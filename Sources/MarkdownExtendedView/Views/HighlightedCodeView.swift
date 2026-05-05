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

    public init(code: String, language: String?, theme: MarkdownTheme) {
        self.code = code.trimmingCharacters(in: .newlines)
        self.language = language
        self.theme = theme
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.codeLineSpacing) {
            ForEach(Array(Self.highlightedLines(code: code, language: language).enumerated()), id: \.offset) { _, lineTokens in
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
                .contentTransition(.numericText())
        } else {
            tokens.reduce(SwiftUI.Text("")) { result, token in
                result + SwiftUI.Text(token.text)
                    .foregroundColor(color(for: token.type))
            }
            .font(theme.codeBlockSwiftUIFont)
            .codeSelectionTextPassThrough()
            .contentTransition(.numericText())
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

    @MainActor
    private static func highlightedLines(code: String, language: String?) -> [[Token]] {
        let cacheKey = Self.cacheKey(for: code, language: language)
        if let cachedLines = HighlightedCodeSnapshotCache.shared.object(forKey: cacheKey as NSString)?.lines {
            return cachedLines
        }

        let resolvedLines = Self.makeHighlightedLines(code: code, language: language)
        HighlightedCodeSnapshotCache.shared.setObject(
            HighlightedCodeSnapshot(lines: resolvedLines),
            forKey: cacheKey as NSString
        )
        return resolvedLines
    }

    private static func cacheKey(for code: String, language: String?) -> String {
        "\(language ?? "plain")::\(code)"
    }

    /// Splits tokens into lines, preserving token structure.
    private static func splitIntoLines(_ tokens: [Token]) -> [[Token]] {
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
