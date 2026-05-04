//  MarkdownExtendedView.swift
//  MarkdownExtendedView
//
// A native SwiftUI Markdown renderer with LaTeX support.
// Uses Apple's swift-markdown for parsing and SwiftMath for LaTeX rendering.
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI

/// A SwiftUI view that renders Markdown content with LaTeX equation support.
public struct MarkdownView: View, @MainActor Equatable {
    public static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content && lhs.baseURL == rhs.baseURL
    }

    private let content: String
    private let baseURL: URL?

    @Environment(\.markdownTheme) private var theme
    @State private var snapshot: MarkdownRenderSnapshot
    @State private var measuredWidth: CGFloat = 0
    @State private var updateTask: Task<Void, Never>? = nil

    public init(_ content: String, baseURL: URL? = nil) {
        self.content = content
        self.baseURL = baseURL
        _snapshot = State(initialValue: MarkdownRenderSnapshot.parse(content))
    }

    public init(content: String, baseURL: URL? = nil) {
        self.init(content, baseURL: baseURL)
    }

    public var body: some View {
        MarkdownRenderer(snapshot: snapshot, theme: theme, baseURL: baseURL)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: snapshot.estimatedHeight, alignment: .top)
            .background(widthReader)
#if os(macOS) || os(iOS)
            .selectable()
#endif
            .onPreferenceChange(MarkdownViewWidthPreferenceKey.self, perform: updateMeasuredWidth(_:))
            .onAppear(perform: refreshLayoutSnapshot)
            .onChange(of: content) { _, newValue in
                scheduleSnapshotUpdate(for: newValue, debounce: true)
            }
            .onChange(of: theme.layoutSignature) { _, _ in
                refreshLayoutSnapshot()
            }
            .onDisappear {
                updateTask?.cancel()
                updateTask = nil
            }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkdownViewWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
    }

    private func updateMeasuredWidth(_ width: CGFloat) {
        let roundedWidth = MarkdownRenderSnapshot.roundedWidth(width)
        guard abs(measuredWidth - roundedWidth) > 0.5 else { return }
        measuredWidth = roundedWidth
        refreshLayoutSnapshot()
    }

    private func refreshLayoutSnapshot() {
        scheduleSnapshotUpdate(for: content, debounce: false)
    }

    private func scheduleSnapshotUpdate(for content: String, debounce: Bool) {
        updateTask?.cancel()
        let width = measuredWidth
        let theme = theme

        updateTask = Task.detached(priority: .utility) { [content] in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let nextSnapshot: MarkdownRenderSnapshot
            if width > 0 {
                nextSnapshot = await MarkdownRenderSnapshot.parse(content, width: width, theme: theme)
            } else {
                nextSnapshot = await MarkdownRenderSnapshot.parse(content)
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                snapshot = nextSnapshot
                updateTask = nil
            }
        }
    }
}

private struct MarkdownViewWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}
