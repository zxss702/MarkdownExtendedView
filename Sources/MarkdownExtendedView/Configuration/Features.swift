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

/// Environment key for custom code reference tap handling.
private struct MarkdownMCodeReferenceHandlerKey: EnvironmentKey {
    static let defaultValue: (@Sendable (MCodeReference) -> Void)? = nil
}

/// Environment key for the base URL used to resolve relative links.
private struct MarkdownBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

public extension EnvironmentValues {
    /// A custom handler for link taps in ``MarkdownView``.
    var markdownLinkHandler: (@Sendable (URL) -> Void)? {
        get { self[MarkdownLinkHandlerKey.self] }
        set { self[MarkdownLinkHandlerKey.self] = newValue }
    }

    /// A custom handler for code reference taps in ``MarkdownView``.
    var markdownMCodeReferenceHandler: (@Sendable (MCodeReference) -> Void)? {
        get { self[MarkdownMCodeReferenceHandlerKey.self] }
        set { self[MarkdownMCodeReferenceHandlerKey.self] = newValue }
    }
    
    /// The base URL used to resolve relative links in ``MarkdownView``.
    var markdownBaseURL: URL? {
        get { self[MarkdownBaseURLKey.self] }
        set { self[MarkdownBaseURLKey.self] = newValue }
    }
}

public extension View {

    /// Sets a custom handler for link taps in Markdown content.
    func onLinkTap(_ handler: @escaping @Sendable (URL) -> Void) -> some View {
        environment(\.markdownLinkHandler, handler)
    }

    /// Sets a custom handler for code reference taps in Markdown code blocks.
    func onMCodeReferenceTap(_ handler: @escaping @Sendable (MCodeReference) -> Void) -> some View {
        environment(\.markdownMCodeReferenceHandler, handler)
    }
    
    /// Sets the base URL used to resolve relative links.
    func markdownBaseURL(_ url: URL?) -> some View {
        environment(\.markdownBaseURL, url)
    }
}
