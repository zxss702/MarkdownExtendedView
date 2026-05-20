//  MarkdownExtendedView.swift
//  MarkdownExtendedView
//
// A native SwiftUI Markdown renderer with LaTeX support.
// Uses Apple's swift-markdown for parsing and SwiftMath for LaTeX rendering.
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI

@Observable
@MainActor
public class MarkdownObject {
    var snapshot: MarkdownRenderSnapshot  = MarkdownRenderSnapshot.empty
    
    init()
    
    @ObservationIgnored var updateTask: Task<Void, Never>? = nil
    @ObservationIgnored var hasAppeared = false
    @ObservationIgnored var lastUpdateTime: Date = .distantPast
    
    func task(content: String) async {
        if snapshot.blocks.isEmpty && !content.isEmpty {
            scheduleSnapshotUpdate(for: content, debounce: false)
        }
    }
    
    func onChangeContentChange(newValue: String) {
        scheduleSnapshotUpdate(for: newValue, debounce: true)
    }
    
    func onDisappear() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    // MARK: - Snapshot Updates

    private func scheduleSnapshotUpdate(for content: String, debounce: Bool) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        let delay: TimeInterval = debounce ? max(0, 0.1 - timeSinceLastUpdate) : 0

        updateTask?.cancel()
        let animate = hasAppeared
        let previousBlocks = snapshot.blocks

        updateTask = Task.detached(priority: .userInitiated) { [weak self, content] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled, let self else { return }
            let nextSnapshot = await MarkdownRenderSnapshot.parse(content, previousBlocks: previousBlocks)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                lastUpdateTime = Date()
                if animate {
                    withAnimation(.snappy) {
                        snapshot = nextSnapshot
                    }
                } else {
                    snapshot = nextSnapshot
                    hasAppeared = true
                }
                updateTask = nil
            }
        }
    }
}

struct MarkdownObjectStateViewModifier: ViewModifier {
    let content: String
    let object: MarkdownObject
    
    func body(content view: Content) -> some View {
        view
            .onAppear {
                if let cached = MarkdownRenderSnapshot.cachedSnapshot(for: content) {
                    object.snapshot = cached
                }
            }
            .task {
                await object.task(content: content)
            }
            .onChange(of: content) { oldValue, newValue in
                object.onChangeContentChange(newValue: newValue)
            }
            .onDisappear {
                object.onDisappear()
            }
    }
}

public extension View {
    func markdownObjectSetter(_ object: MarkdownObject, content: String) -> some View {
        modifier(MarkdownObjectStateViewModifier(content: content, object: object))
    }
}

/// A SwiftUI view that renders Markdown content with LaTeX equation support.
public struct MarkdownView: View, @MainActor Equatable {
    private static let synchronousParseCharacterLimit = 4096

    // MARK: - Initialization

    public init(_ content: String, baseURL: URL? = nil, markdownObject: MarkdownObject) {
        self.content = content
        self.baseURL = baseURL
        self.markdownObject = markdownObject
    }

    // MARK: - Stored Properties

    private let content: String
    private let baseURL: URL?
    private let markdownObject: MarkdownObject

    // MARK: - State

    @Environment(\.markdownTheme) private var theme
    
    // MARK: - Equatable

    public static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content && lhs.baseURL == rhs.baseURL
    }

    // MARK: - Body

    public var body: some View {
        MarkdownRenderer(snapshot: markdownObject.snapshot, theme: theme, baseURL: baseURL)
            .lineLimit(nil)
    }
}


public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}
