// Features.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI

/// Environment key for custom link tap handling.
private struct MarkdownLinkHandlerKey: EnvironmentKey {
    static let defaultValue: (@Sendable (URL) -> Void)? = nil
}

public extension EnvironmentValues {
    /// A custom handler for link taps in ``MarkdownView``.
    var markdownLinkHandler: (@Sendable (URL) -> Void)? {
        get { self[MarkdownLinkHandlerKey.self] }
        set { self[MarkdownLinkHandlerKey.self] = newValue }
    }
}

public extension View {

    /// Sets a custom handler for link taps in Markdown content.
    func onLinkTap(_ handler: @escaping @Sendable (URL) -> Void) -> some View {
        environment(\.markdownLinkHandler, handler)
    }
}
