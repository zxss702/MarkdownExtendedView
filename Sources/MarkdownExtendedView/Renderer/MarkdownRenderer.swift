//
//  MarkdownRenderer.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
//  Licensed under MIT License
//

import SwiftUI
import Markdown

/// Renders a parsed Markdown document to SwiftUI views.
struct MarkdownRenderer: View {
    let snapshot: MarkdownRenderSnapshot
    let theme: MarkdownTheme
    let baseURL: URL?
    let isLazy: Bool
    
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler
    
    var body: some View {
        let context = MarkdownContext(
            theme: theme,
            baseURL: baseURL,
            linkHandler: linkHandler,
            MCodeReferenceHandler: MCodeReferenceHandler
        )
        
        if isLazy {
            LazyVStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
                ForEach(Array(snapshot.blocks.enumerated()), id: \.element.id) { index, block in
                    RenderBlock(
                        markup: block.markup,
                        features: block.features,
                        context: context
                    )
                    .transition(.markdownBlockAppear)
                    .padding(.bottom, index < snapshot.blocks.count - 1 ? max(0, theme.paragraphSpacing - 8) : 0)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: theme.textAlignment, vertical: .center))
                }
            }
            .lineSpacing(theme.paragraphSpacing)
            .foregroundColor(theme.textColor)
        } else {
            VStack(alignment: theme.textAlignment, spacing: theme.paragraphSpacing) {
                ForEach(Array(snapshot.blocks.enumerated()), id: \.element.id) { index, block in
                    RenderBlock(
                        markup: block.markup,
                        features: block.features,
                        context: context
                    )
                    .transition(.markdownBlockAppear)
                    .padding(.bottom, index < snapshot.blocks.count - 1 ? max(0, theme.paragraphSpacing - 8) : 0)
                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: theme.textAlignment, vertical: .center))
                }
            }
            .lineSpacing(theme.paragraphSpacing)
            .foregroundColor(theme.textColor)
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
            .allowsHitTesting(false)
            .pointerStyle(.horizontalText)
#else
        self
            .allowsHitTesting(false)
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

// MARK: - Block Appear Transition

private struct MarkdownBlockAppearModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 4 : 0)
            .scaleEffect(isActive ? 0.01 : 1, anchor: .bottomLeading)
            .opacity(isActive ? 0 : 1)
    }
}

extension AnyTransition {
    static var markdownBlockAppear: AnyTransition {
        .modifier(
            active: MarkdownBlockAppearModifier(isActive: true),
            identity: MarkdownBlockAppearModifier(isActive: false)
        )
    }
}
