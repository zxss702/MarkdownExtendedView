//  MarkdownExtendedView.swift
//  MarkdownExtendedView
//
// A native SwiftUI Markdown renderer with LaTeX support.
// Uses Apple's swift-markdown for parsing and SwiftMath for LaTeX rendering.
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License
//

import SwiftUI

/// A SwiftUI view that renders Markdown content with LaTeX equation support.
///
/// The Markdown document is parsed and flattened into `[MDBlock]`
/// **synchronously** inside `init`, so the first rendered frame already
/// has its full content — there is no `onAppear` loading pass and no
/// empty-to-populated height jump.
public struct MarkdownView: View, @MainActor Equatable {
    /// Kept for API compatibility. Parsing is always synchronous now.
    public static var synchronousParseCharacterLimit = 4096

    // MARK: - Initialization

    public init(_ content: String, baseURL: URL? = nil, isLazy: Bool = false) {
        self.content = content
        self.baseURL = baseURL
        self.isLazy = isLazy
        self.blocks = MarkdownSnapshotCache.getOrBuild(content, baseURL: baseURL)
    }

    // MARK: - Stored Properties

    private let content: String
    private let baseURL: URL?
    private let isLazy: Bool
    private let blocks: [MDBlock]

    // MARK: - Equatable

    public static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content && lhs.baseURL == rhs.baseURL && lhs.isLazy == rhs.isLazy
    }

    // MARK: - Body

    public var body: some View {
        MarkdownRenderer(blocks: blocks, isLazy: isLazy)
            .markdownBaseURL(baseURL)
    }
}

public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}
