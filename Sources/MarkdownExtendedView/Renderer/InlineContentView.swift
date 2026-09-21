//
//  InlineContentView.swift
//  MarkdownExtendedView
//
//  Renders a flattened inline `AttributedString` as one continuous
//  `SwiftUI.Text`. Emphasis, links and colors are already baked as
//  attributes; `\u{FFFC}` markers carry `MDBakedInlineImage` payloads
//  (inline LaTeX, code-reference icons) which resolve lazily on first
//  render and draw via `Text(Image)` concatenation — the only way
//  SwiftUI draws images inside text, and it still produces a single
//  shared layout.
//

import SwiftUI

struct InlineContentView: View {
    let attributed: AttributedString
    /// Overrides the theme body font (headings); also drives the
    /// metric-based scaling of `.fontScaled` baked images.
    var font: MarkdownNativeFont? = nil

    @Environment(\.markdownTheme) private var theme

    private var effectiveFont: MarkdownNativeFont {
        font ?? theme.bodyFont
    }

    var body: some View {
        text
            .font(effectiveFont.swiftUIFont)
            .foregroundColor(theme.textColor)
            .tint(theme.linkColor)
            .makeCanSelectable()
    }

    private var text: Text {
        var combined: Text? = nil
        var segment = AttributedString()

        func flush() {
            guard !segment.characters.isEmpty else { return }
            let piece = Text(segment)
            segment = AttributedString()
            combined = combined.map { $0 + piece } ?? piece
        }

        for run in attributed.runs {
            if let baked = run.attributes[MarkdownInlineImageKey.self] {
                flush()
                if let rendered = baked.rendered(for: effectiveFont) {
                    let piece = Text(platformImage: rendered.image)
                        .baselineOffset(-rendered.descent)
                    combined = combined.map { $0 + piece } ?? piece
                } else if let fallback = baked.fallbackText {
                    // Un-typesettable math renders as its literal
                    // `$..$` source — the mapping payload still reads
                    // correctly via the reflection fallback.
                    segment.append(AttributedString(fallback))
                }
            } else {
                segment.append(attributed[run.range])
            }
        }
        flush()

        var text = combined ?? Text("")
        // Re-publish the baked selection payload through SwiftUI's
        // TextAttribute channel — `Text.Layout` run subscripts don't
        // see raw AttributedString keys.
        if let mappings = attributed.selectionMappings {
            text = text.customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
        }
        return text
    }
}

private extension Text {
    init(platformImage: MTImage) {
        #if canImport(AppKit)
        self.init(Image(nsImage: platformImage))
        #elseif canImport(UIKit)
        self.init(Image(uiImage: platformImage))
        #endif
    }
}
