// HighlightedCodeView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
//  Licensed under MIT License
//

import SwiftUI

/// A view that renders syntax-highlighted code.
///
/// Tokenization is fully synchronous: either pre-tokenized `lines` are
/// passed in (the `MDBlock` path) or the public initializer tokenizes
/// inline with a snapshot cache short-circuit. No `.task`, no second
/// frame — the first render already shows highlighted code.
public struct HighlightedCodeView: View {

    private let code: String
    private let language: String?
    private let theme: MarkdownTheme
    private let lines: [[Token]]

    /// Public entry point — tokenizes synchronously (cache first).
    public init(code: String, language: String?, theme: MarkdownTheme) {
        self.code = code
        self.language = language
        self.theme = theme
        self.lines = Self.resolveLines(code: code, language: language)
    }

    /// Render-model entry point — lines were tokenized during flattening.
    init(code: String, language: String?, theme: MarkdownTheme, lines: [[Token]]) {
        self.code = code
        self.language = language
        self.theme = theme
        self.lines = lines
    }

    public var body: some View {
        buildText(from: lines)
            .font(theme.codeBlockSwiftUIFont)
            .customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
            .selectionTextPassThrough()
    }

    // MARK: - Text assembly

    /// One run-length entry per token — O(tokens), not O(characters).
    /// `MDGlyphCursor` expands the per-glyph slicing lazily when the
    /// selection document consumes it.
    private var mappings: [GlobalSelectionCache.CharacterMapping] {
        var result: [GlobalSelectionCache.CharacterMapping] = []
        result.reserveCapacity(lines.reduce(0) { $0 + $1.count } + lines.count)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(.init(char: "\n", glyphCount: 0, isLineBreak: true))
            }
            for token in line where !token.text.isEmpty {
                result.append(.init(
                    char: token.text[...],
                    glyphCount: token.text.count,
                    slicesText: true
                ))
            }
        }
        return result
    }

    private func buildText(from lines: [[Token]]) -> SwiftUI.Text {
        var combinedAttr = AttributedString()

        for (index, line) in lines.enumerated() {
            if index > 0 {
                combinedAttr.append(AttributedString("\n"))
            }
            for token in line {
                var tokenAttr = AttributedString(token.text)
                tokenAttr.foregroundColor = Self.color(for: token.type, theme: theme)
                combinedAttr.append(tokenAttr)
            }
        }

        return SwiftUI.Text(combinedAttr)
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

    // MARK: - Tokenization + cache

    /// Synchronous resolve: snapshot cache hit → stored lines; otherwise
    /// tokenize on the spot and store the result. `nonisolated` — the
    /// NSCache underneath is internally synchronized.
    nonisolated static func resolveLines(code: String, language: String?) -> [[Token]] {
        let normalizedCode = code.trimmingCharacters(in: .newlines)
        let cacheKey = Self.cacheKey(for: normalizedCode, language: language) as NSString

        if let cached = HighlightedCodeSnapshotCache.shared.object(forKey: cacheKey) {
            return cached.lines
        }

        let lines = makeHighlightedLines(code: normalizedCode, language: language)
        HighlightedCodeSnapshotCache.shared.setObject(
            HighlightedCodeSnapshot(lines: lines),
            forKey: cacheKey
        )
        return lines
    }

    nonisolated private static func makeHighlightedLines(code: String, language: String?) -> [[Token]] {
        let tokens = SyntaxHighlighter().tokenize(code, language: language)
        return splitIntoLines(tokens)
    }

    nonisolated static func cacheKey(for code: String, language: String?) -> String {
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
    nonisolated(unsafe) static let shared: NSCache<NSString, HighlightedCodeSnapshot> = {
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
