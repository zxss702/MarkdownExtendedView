//
//  MarkdownContext.swift
//  MarkdownExtendedView
//

import SwiftUI

/// A context object that holds the rendering configuration for a Markdown document.
/// Passed down the view hierarchy to configure themes, handlers, and base URLs.
struct MarkdownContext {
    let theme: MarkdownTheme
    let baseURL: URL?
    let linkHandler: (@Sendable (URL) -> Void)?
    let MCodeReferenceHandler: (@Sendable (MCodeReference) -> Void)?
    let viewWidth: CGFloat
    
    init(
        theme: MarkdownTheme,
        baseURL: URL?,
        viewWidth: CGFloat,
        linkHandler: (@Sendable (URL) -> Void)?,
        MCodeReferenceHandler: (@Sendable (MCodeReference) -> Void)?
    ) {
        self.viewWidth = viewWidth
        self.theme = theme
        self.baseURL = baseURL
        self.linkHandler = linkHandler
        self.MCodeReferenceHandler = MCodeReferenceHandler
    }
}
