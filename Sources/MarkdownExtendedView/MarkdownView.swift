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
    public static var synchronousParseCharacterLimit = 4096

    // MARK: - Initialization

    public init(_ content: String, baseURL: URL? = nil, isLazy: Bool = false) {
        self.content = content
        self.baseURL = baseURL

        self.isLazy = isLazy
        if let cached = MarkdownRenderSnapshot.cachedSnapshot(for: content) {
            self._snapshot = State(initialValue: cached)
        } else if !isLazy {
            let parsed = MarkdownRenderSnapshot.parseSynchronously(content)
            self._snapshot = State(initialValue: parsed)
        } else {
            self._snapshot = State(initialValue: MarkdownRenderSnapshot.empty)
        }
    }

    // MARK: - Stored Properties

    private let content: String
    private let baseURL: URL?
    private let isLazy: Bool
    
    // MARK: - State

    @State private var snapshot: MarkdownRenderSnapshot
    @State private var helper = ViewHelper()

    // MARK: - Equatable

    public static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content && lhs.baseURL == rhs.baseURL
    }

    // MARK: - Body
    
    public var body: some View {
        MarkdownRenderer(snapshot: snapshot, isLazy: isLazy)
//            .lineLimit(nil)
            .markdownBaseURL(baseURL)
            .onAppear {
                if isLazy && snapshot.blocks.isEmpty && !content.isEmpty {
                    scheduleSnapshotUpdate(for: content, debounce: false)
                }
            }
            .onChange(of: content) { _, newValue in
                if isLazy {
                    scheduleSnapshotUpdate(for: newValue, debounce: true)
                } else {
                    snapshot = MarkdownRenderSnapshot.parseSynchronously(newValue)
                }
            }
            .onDisappear {
                helper.updateTask?.cancel()
                helper.updateTask = nil
            }
        
    }

    // MARK: - Snapshot Updates

    private func scheduleSnapshotUpdate(for content: String, debounce: Bool) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(helper.lastUpdateTime)
        let delay: TimeInterval = debounce ? max(0, 0.1 - timeSinceLastUpdate) : 0

        helper.updateTask?.cancel()
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
                snapshot = nextSnapshot
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
        @ObservationIgnored var lastUpdateTime: Date = .distantPast
    }
}
