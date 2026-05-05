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
        let initialSnapshot = content.count > Self.synchronousParseCharacterLimit
            ? MarkdownRenderSnapshot.empty
            : MarkdownRenderSnapshot.parse(content)
        _snapshot = State(initialValue: initialSnapshot)
    }

    public init(content: String, baseURL: URL? = nil) {
        self.init(content, baseURL: baseURL)
    }

    public var body: some View {
        MarkdownRenderer(snapshot: snapshot, theme: theme, baseURL: baseURL)
            .lineLimit(nil)
//            .frame(maxWidth: .infinity, alignment: .topLeading)
//            .fixedSize(horizontal: false, vertical: true)
            .frame(height: snapshot.estimatedHeight, alignment: .top)
            .background(widthReader)
#if os(macOS) || os(iOS)
            .selectable()
#endif
            .onPreferenceChange(MarkdownViewWidthPreferenceKey.self, perform: updateMeasuredWidth(_:))
            .onAppear(perform: refreshLayoutSnapshot)
            .onChange(of: content) { oldValue, newValue in
                scheduleSnapshotUpdate(
                    for: newValue,
                    reason: .contentChange(old: oldValue, new: newValue)
                )
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
        scheduleSnapshotUpdate(for: content, reason: .layout)
    }

    private func scheduleSnapshotUpdate(for content: String, reason: SnapshotUpdateReason) {
        updateTask?.cancel()
        let width = measuredWidth
        let theme = theme
        let debounce = reason.debounce
        let reconcileMode = reason.reconciliationMode
        let shouldAnimate = reason.animatesSnapshotChange

        updateTask = Task.detached(priority: .utility) { [content] in
            if let debounce {
                do {
                    try await Task.sleep(for: debounce)
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
                let reconciledSnapshot = nextSnapshot.reusingBlockIdentities(
                    from: snapshot,
                    mode: reconcileMode
                )
                applySnapshot(reconciledSnapshot, animated: shouldAnimate)
                updateTask = nil
            }
        }
    }

    private func applySnapshot(_ nextSnapshot: MarkdownRenderSnapshot, animated: Bool) {
        if animated {
            withAnimation(.snappy) {
                snapshot = nextSnapshot
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                snapshot = nextSnapshot
            }
        }
    }

    private enum SnapshotUpdateReason: Sendable {
        case layout
        case contentChange(old: String, new: String)

        var debounce: Duration? {
            switch self {
            case .layout:
                return nil
            case .contentChange(let old, let new):
                return isIncrementalUpdate(from: old, to: new)
                    ? .milliseconds(35)
                    : .milliseconds(150)
            }
        }

        var reconciliationMode: MarkdownSnapshotReconciliationMode {
            switch self {
            case .layout:
                return .exact
            case .contentChange(let old, let new):
                return isIncrementalUpdate(from: old, to: new) ? .streaming : .exact
            }
        }

        var animatesSnapshotChange: Bool {
            switch self {
            case .layout:
                return false
            case .contentChange(let old, let new):
                return isIncrementalUpdate(from: old, to: new)
            }
        }

        private func isIncrementalUpdate(from old: String, to new: String) -> Bool {
            guard !old.isEmpty, new.count >= old.count else {
                return false
            }
            if new.hasPrefix(old) {
                return true
            }

            let commonPrefixCount = zip(old, new).prefix { $0 == $1 }.count
            let requiredPrefixCount = Int((Double(old.count) * 0.8).rounded(.down))
            return commonPrefixCount >= max(1, requiredPrefixCount)
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
