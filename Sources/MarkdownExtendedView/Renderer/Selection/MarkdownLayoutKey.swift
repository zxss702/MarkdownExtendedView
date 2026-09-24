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
    /// Caller-supplied stable identity (e.g. a data-model id). Unlike
    /// `blockId` — view state that dies when a lazy stack dematerializes
    /// its children — this survives rematerialization, which is what
    /// lets the selection document dedupe and remap correctly.
    public let selectionID: String?
    /// The `Text` layouts of THIS anchor's own subtree, captured by
    /// `MakeTextSelectable` via `backgroundPreferenceValue`. Texts
    /// travel with their anchor instead of being matched geometrically,
    /// so a lazy stack remeasuring mid-scroll can never mis-assign a
    /// text to a neighbouring row.
    public let textLayouts: SwiftUI.Text.LayoutKey.Value
    /// Markdown-source wrapper emitted around this anchor's copied
    /// sections (e.g. code-block fences): `sourcePrefix` attaches to
    /// the first section, `sourceSuffix` to the last — each only when
    /// the selection covers that boundary.
    public let sourcePrefix: String?
    public let sourceSuffix: String?

    public init(
        blockId: UUID,
        bounds: Anchor<CGRect>,
        isBlock: Bool = false,
        blockText: String = "",
        linePrefix: String? = nil,
        richImage: MTImage? = nil,
        selectionID: String? = nil,
        textLayouts: SwiftUI.Text.LayoutKey.Value = [],
        sourcePrefix: String? = nil,
        sourceSuffix: String? = nil
    ) {
        self.blockId = blockId
        self.bounds = bounds
        self.isBlock = isBlock
        self.blockText = blockText
        self.linePrefix = linePrefix
        self.richImage = richImage
        self.selectionID = selectionID
        self.textLayouts = textLayouts
        self.sourcePrefix = sourcePrefix
        self.sourceSuffix = sourceSuffix
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
            && lhs.selectionID == rhs.selectionID
            && lhs.textLayouts == rhs.textLayouts
            && lhs.sourcePrefix == rhs.sourcePrefix
            && lhs.sourceSuffix == rhs.sourceSuffix
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

/// Data-level stable identity for selection anchors — injected by the
/// renderer per `MDBlock`, or passed explicitly to `makeCanSelectable`.
private struct MarkdownSelectionIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var markdownSelectionLinePrefix: String {
        get { self[MarkdownSelectionLinePrefixKey.self] }
        set { self[MarkdownSelectionLinePrefixKey.self] = newValue }
    }

    var markdownSelectionID: String? {
        get { self[MarkdownSelectionIDKey.self] }
        set { self[MarkdownSelectionIDKey.self] = newValue }
    }
}
