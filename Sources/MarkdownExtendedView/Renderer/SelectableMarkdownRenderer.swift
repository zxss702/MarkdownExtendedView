// SelectableMarkdownRenderer.swift
// MarkdownExtendedView
//
// Copyright (c) 2025 Christian C. Berclaz
// Licensed under MIT License

import SwiftUI
import Markdown

/// Renders markdown with dual-layer large-area text selection.
///
/// Uses a layout-driven native interaction overlay for accurate cross-block
/// selection geometry.
struct SelectableMarkdownRenderer: View {

    let document: Document
    let theme: MarkdownTheme
    let baseURL: URL?

    var body: some View {
#if os(macOS) || os(iOS)
        SelectableMarkdownRendererNative(
            document: document,
            theme: theme,
            baseURL: baseURL
        )
#else
        MarkdownRenderer(
            document: document,
            theme: theme,
            baseURL: baseURL
        )
#endif
    }
}
