//
//  MarkdownRenderer.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
//  Licensed under MIT License
//

import SwiftUI
import Markdown

/// Renders the flattened `[MDBlock]` model to SwiftUI views. The body is
/// a pure mapping — all parsing, flattening and tokenization already
/// happened in `MarkdownView.init`.
struct MarkdownRenderer: View {
    let blocks: [MDBlock]
    let isLazy: Bool

    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var codeReferenceHandler

    var body: some View {
        if isLazy {
            LazyVStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
                blockList
            }
            .lineSpacing(theme.paragraphSpacing)
            .foregroundColor(theme.textColor)
            .environment(\.openURL, openURLAction)
        } else {
            VStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
                blockList
            }
            .lineSpacing(theme.paragraphSpacing)
            .foregroundColor(theme.textColor)
            .environment(\.openURL, openURLAction)
        }
    }

    private var blockList: some View {
        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            RenderBlock(block: block)
                .equatable()
                .padding(.bottom, index < blocks.count - 1 ? max(0, theme.paragraphSpacing - 8) : 0)
        }
    }

    /// Bridge `.link` attributed-string taps into the tap handlers.
    /// `file://` URLs carrying line ranges are inline code references —
    /// they go to `onMCodeReferenceTap` (or open the plain file as a
    /// fallback); everything else goes to `onLinkTap` / the system.
    private var openURLAction: OpenURLAction {
        OpenURLAction { url in
            if url.isFileURL, let reference = MCodeReference(url.absoluteString) {
                if let codeReferenceHandler {
                    codeReferenceHandler(reference)
                    return .handled
                }
                return .systemAction(reference.url)
            }
            if let linkHandler {
                linkHandler(url)
                return .handled
            }
            return .systemAction
        }
    }
}

// MARK: - Modifiers

struct CodeBlockContainerModifier: ViewModifier {
    let theme: MarkdownTheme
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .padding(isInteractive ? .zero : theme.codeBlockPadding)
            .background(isInteractive ? Color.clear : theme.codeBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .modifier(CodeBlockSelectionModifier(isInteractive: isInteractive))
    }
}

struct CodeBlockSelectionModifier: ViewModifier {
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isInteractive {
            content
        } else {
            content.selectionTextPassThrough()
        }
    }
}

extension View {
    func selectionTextPassThrough() -> some View {
#if os(macOS)
        self
            .pointerStyle(.horizontalText)
#else
        self
#endif
    }

    func buttonLink() -> some View {
#if os(macOS)
        self
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .pointerStyle(.link)
#else
        self
#endif
    }
}
