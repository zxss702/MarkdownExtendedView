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
        MarkdownRenderer(
            snapshot: snapshot,
            theme: theme,
            baseURL: baseURL
        )
#if os(macOS) || os(iOS)
        .selectable()
#endif
        .onChange(of: content) { _, newValue in
            scheduleSnapshotUpdate(for: newValue)
        }
        .onDisappear {
            updateTask?.cancel()
            updateTask = nil
        }
    }

    private func scheduleSnapshotUpdate(for content: String) {
        updateTask?.cancel()

        updateTask = Task.detached(priority: .utility) { [content] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let nextSnapshot = MarkdownRenderSnapshot.parse(content)

            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) {
                    snapshot = nextSnapshot
                }
                updateTask = nil
            }
        }
    }
}


public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}

#if DEBUG
struct MarkdownView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            MarkdownView("""
                # Welcome to MarkdownView

                This is a **native SwiftUI** Markdown renderer with *LaTeX* support.

                ## Features

                - GitHub Flavored Markdown
                - LaTeX equations: $E = mc^2$
                - Fenced code blocks
                - Tables and lists

                ## Math Example

                The quadratic formula:

                $$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$

                ## Code Example

                ```swift
                let greeting = "Hello, World!"
                print(greeting)
                ```

                ## Table Example

                | Scale | Purpose |
                |-------|---------|
                | C/D   | Multiply |
                | A/B   | Squares |

                > This is a block quote with **formatting**.
                """)
            .padding()
        }
    }
}
#endif
