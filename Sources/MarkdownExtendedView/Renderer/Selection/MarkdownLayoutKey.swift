// MarkdownLayoutKey.swift
//  MarkdownExtendedView
//

import SwiftUI

public struct MarkdownLayout: @unchecked Sendable {
    public let blockId: UUID
    public let bounds: Anchor<CGRect>
    public let isBlock: Bool // True for latex blocks, mermaid, etc. False for normal text.
    public let blockText: String // Optional text for block-level selection copying
    /// Per-line copy prefix contributed by enclosing blockquotes (e.g. "> ").
    public let linePrefix: String?
    /// Rendered image for rich ("含图像") copies — mermaid diagram,
    /// typeset block formula. Compared by identity so re-rendered
    /// anchors don't churn the selection document.
    public let richImage: MTImage?

    public init(
        blockId: UUID,
        bounds: Anchor<CGRect>,
        isBlock: Bool = false,
        blockText: String = "",
        linePrefix: String? = nil,
        richImage: MTImage? = nil
    ) {
        self.blockId = blockId
        self.bounds = bounds
        self.isBlock = isBlock
        self.blockText = blockText
        self.linePrefix = linePrefix
        self.richImage = richImage
    }
}

extension MarkdownLayout: Equatable {
    public static func == (lhs: MarkdownLayout, rhs: MarkdownLayout) -> Bool {
        lhs.blockId == rhs.blockId
            && lhs.bounds == rhs.bounds
            && lhs.isBlock == rhs.isBlock
            && lhs.blockText == rhs.blockText
            && lhs.linePrefix == rhs.linePrefix
            && lhs.richImage.map(ObjectIdentifier.init) == rhs.richImage.map(ObjectIdentifier.init)
    }
}

public struct MarkdownLayoutKey: PreferenceKey {
    public static var defaultValue: [MarkdownLayout] { [] }
    public static func reduce(value: inout [MarkdownLayout], nextValue: () -> [MarkdownLayout]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Selection line prefix environment

/// Accumulated copy prefix for nested blockquotes (`"> "`, `"> > "`…).
/// Injected by `RenderBlockQuote`; consumed by `MakeTextSelectable`.
private struct MarkdownSelectionLinePrefixKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var markdownSelectionLinePrefix: String {
        get { self[MarkdownSelectionLinePrefixKey.self] }
        set { self[MarkdownSelectionLinePrefixKey.self] = newValue }
    }
}
