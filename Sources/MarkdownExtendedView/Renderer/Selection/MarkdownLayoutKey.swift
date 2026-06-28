// MarkdownLayoutKey.swift
// MarkdownExtendedView

import SwiftUI

public struct MarkdownLayout: Equatable, Sendable {
    public let blockId: UUID
    public let bounds: Anchor<CGRect>
    public let isBlock: Bool // True for latex blocks, mermaid, etc. False for normal text.
    public let blockText: String // Optional text for block-level selection copying
    
    public init(blockId: UUID, bounds: Anchor<CGRect>, isBlock: Bool = false, blockText: String = "") {
        self.blockId = blockId
        self.bounds = bounds
        self.isBlock = isBlock
        self.blockText = blockText
    }
}

public struct MarkdownLayoutKey: PreferenceKey {
    public static var defaultValue: [MarkdownLayout] { [] }
    public static func reduce(value: inout [MarkdownLayout], nextValue: () -> [MarkdownLayout]) {
        value.append(contentsOf: nextValue())
    }
}
