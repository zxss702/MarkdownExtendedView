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
    private static let synchronousParseCharacterLimit = 4096

    // MARK: - Initialization

    public init(_ content: String, baseURL: URL? = nil) {
        self.content = content
        self.baseURL = baseURL
        if let cached = MarkdownRenderSnapshot.cachedSnapshot(for: content) {
            self._snapshot = State(initialValue: cached)
        } else {
            self._snapshot = State(initialValue: MarkdownRenderSnapshot.empty)
        }
    }

    // MARK: - Stored Properties

    private let content: String
    private let baseURL: URL?

    // MARK: - State

    @Environment(\.markdownTheme) private var theme
    @State private var snapshot: MarkdownRenderSnapshot
    @State private var helper = ViewHelper()

    // MARK: - Equatable

    public static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content && lhs.baseURL == rhs.baseURL
    }

    // MARK: - Body

    public var body: some View {
        Color.white
            .opacity(0.01)
            .frame(width: 0, height: 0)
            .task {
                if snapshot.blocks.isEmpty && !content.isEmpty {
                    scheduleSnapshotUpdate(for: content, debounce: false)
                }
            }
            .onChange(of: content) { _, newValue in
                scheduleSnapshotUpdate(for: newValue, debounce: true)
            }
            .onDisappear {
                helper.updateTask?.cancel()
                helper.updateTask = nil
            }
            
        MarkdownRenderer(snapshot: snapshot, theme: theme, baseURL: baseURL)
            .lineLimit(nil)
    }

    // MARK: - Snapshot Updates

    private func scheduleSnapshotUpdate(for content: String, debounce: Bool) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(helper.lastUpdateTime)
        let delay: TimeInterval = debounce ? max(0, 0.1 - timeSinceLastUpdate) : 0

        helper.updateTask?.cancel()
        let animate = helper.hasAppeared
        let previousBlocks = snapshot.blocks

        helper.updateTask = Task.detached(priority: .userInitiated) { [content] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let nextSnapshot = await MarkdownRenderSnapshot.parse(content, previousBlocks: previousBlocks)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                helper.lastUpdateTime = Date()
                if animate {
                    withAnimation(.snappy) {
                        snapshot = nextSnapshot
                    }
                } else {
                    snapshot = nextSnapshot
                    helper.hasAppeared = true
                }
                helper.updateTask = nil
            }
        }
    }
}


public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}

// MARK: - View Helper

extension MarkdownView {
    @Observable
    final class ViewHelper {
        @ObservationIgnored var updateTask: Task<Void, Never>? = nil
        @ObservationIgnored var hasAppeared = false
        @ObservationIgnored var lastUpdateTime: Date = .distantPast
    }
}
