// SelectableModifier.swift
// MarkdownExtendedView

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

import Observation

struct ResolvedLayout: Equatable {
    let blockId: UUID
    let rect: CGRect
    let isBlock: Bool
    let blockText: String
}

struct GlobalCharacter: Equatable {
    let blockId: UUID
    let charIndex: Int
    let char: String
    let globalRect: CGRect
}

struct SelectableModifier: ViewModifier {
    
    @State var selectionCache = GlobalSelectionCache()
    
    @State private var resolvedLayouts: [ResolvedLayout] = []
    @FocusState private var isFocused: Bool
    
    @State var globalCharacters: [GlobalCharacter] = []
    
    func updateGlobalCharacters() {
        var chars: [GlobalCharacter] = []
        
        // 1. 按 midY 排序 (行间)
        let sortedLayouts = resolvedLayouts.sorted { $0.rect.midY < $1.rect.midY }
        
        // 2. 分组为行 (midY 差值 < 8 视为同一行)
        var lines: [[ResolvedLayout]] = []
        var currentLine: [ResolvedLayout] = []
        var lastMidY: CGFloat?
        
        for layout in sortedLayouts {
            if let last = lastMidY, abs(layout.rect.midY - last) >= 8 {
                lines.append(currentLine)
                currentLine = []
            }
            currentLine.append(layout)
            lastMidY = layout.rect.midY
        }
        lines.append(currentLine)
        
        // 3. 每行内按 midX 排序，展开为字符
        for line in lines {
            let sortedLine = line.sorted { $0.rect.midX < $1.rect.midX }
            for layout in sortedLine {
                if layout.isBlock {
                    chars.append(GlobalCharacter(
                        blockId: layout.blockId,
                        charIndex: 0,
                        char: layout.blockText + "\n\n",
                        globalRect: layout.rect
                    ))
                } else {
                    if let runs = selectionCache.runs[layout.blockId] {
                        let sortedRuns = runs.sorted { $0.index < $1.index }
                        for run in sortedRuns {
                            let globalRect = run.rect.offsetBy(
                                dx: layout.rect.minX,
                                dy: layout.rect.minY
                            )
                            chars.append(GlobalCharacter(
                                blockId: layout.blockId,
                                charIndex: run.index,
                                char: run.char,
                                globalRect: globalRect
                            ))
                        }
                        if let lastChar = chars.last {
                            let newlineRect = CGRect(
                                x: lastChar.globalRect.maxX,
                                y: lastChar.globalRect.minY,
                                width: 0,
                                height: lastChar.globalRect.height
                            )
                            chars.append(GlobalCharacter(
                                blockId: layout.blockId,
                                charIndex: Int.max,
                                char: "\n\n",
                                globalRect: newlineRect
                            ))
                        }
                    }
                }
            }
        }
        
        self.globalCharacters = chars
    }
    
    /// 返回距离 point 最近的文本插入索引 (0...characters.count)
    func closestCharacterIndex(to point: CGPoint) -> Int? {
        guard !globalCharacters.isEmpty else { return nil }
        
        var bestIndex = 0
        var bestDistSq: CGFloat = .infinity
        var bestCharLeft: CGFloat = 0
        
        // 遍历所有字符，找到点到矩形距离最短的那个
        for (i, char) in globalCharacters.enumerated() where char.globalRect.minY < point.y {
            let rect = char.globalRect
            
            // 计算点到矩形的最短距离（平方）
            let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
            let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
            let distSq = dx * dx + dy * dy
            
            if distSq < bestDistSq {
                bestDistSq = distSq
                bestIndex = i
                bestCharLeft = rect.minX
            } else if distSq == bestDistSq {
                // 如果距离相等（例如点在两个字符正中间），优先选择更靠左的字符
                if rect.minX < bestCharLeft {
                    bestIndex = i
                    bestCharLeft = rect.minX
                }
            }
        }
        
        return bestIndex
    }
    
    @State var selectedRange: ClosedRange<Int>?
    
    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(MarkdownLayoutKey.self) { layouts in
                GeometryReader { proxy in
                    Color.clear
                        .task(id: layouts) {
                            resolvedLayouts = layouts.map {
                                ResolvedLayout(blockId: $0.blockId, rect: proxy[$0.bounds], isBlock: $0.isBlock, blockText: $0.blockText)
                            }
                            updateGlobalCharacters()
                        }
                }
            }
            .overlay {
                if let range = selectedRange {
                    Path { path in
                        for i in range {
                            let rect = globalCharacters[i].globalRect
                            if rect.width > 0 {
                                path.addPath(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 1, style: .continuous))
                            }
                        }
                    }
                    .fill(Color.blue.opacity(0.15))
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isFocused {
                            isFocused = true
                        }
                        
                        let start = value.startLocation
                        let current = value.location
                        
                        if globalCharacters.isEmpty {
                            updateGlobalCharacters()
                        }
                        
                        guard !globalCharacters.isEmpty else {
                            selectedRange = nil
                            return
                        }
                        
                        guard
                            let startIndex = closestCharacterIndex(to: start),
                            let endIndex = closestCharacterIndex(to: current)
                        else {
                            selectedRange = nil
                            return
                        }
                        
                        selectedRange = min(startIndex, endIndex) ... max(startIndex, endIndex)
                    }
            )
#if canImport(AppKit)
            .background(
                WindowDeselectHandler(
                    onDeselect: {
                        selectedRange = nil
                        globalCharacters = []
                    },
                    onCopy: {
                        if let range = selectedRange {
                            let selectedText = globalCharacters[range].map { $0.char }.joined()
                            if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(selectedText, forType: .string)
                                return true
                            }
                        }
                        return false
                    }
                )
            )
#endif
            .environment(selectionCache)
    }
    
    private func copyToPasteboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }
}

public extension View {
    func selectable() -> some View {
        self.modifier(SelectableModifier())
    }
}

public struct MakeTextSelectable: ViewModifier {
    @Environment(GlobalSelectionCache.self) private var selectionCache: GlobalSelectionCache?
    @State private var blockId = UUID()

    public let isBlock: Bool // True for latex blocks, mermaid, etc. False for normal text.
    public let blockText: String // Optional text for block-level selection copying
    
    public func body(content: Content) -> some View {
        if let selectionCache {
            if isBlock {
                content
                    .pointerStyle(.horizontalText)
                    .anchorPreference(key: MarkdownLayoutKey.self, value: .bounds) { bounds in
                        [MarkdownLayout(blockId: blockId, bounds: bounds, isBlock: isBlock, blockText: blockText)]
                    }
            } else {
                content
                    .textRenderer(SelectionLayoutTextRenderer(cache: selectionCache, blockId: blockId))
                    .pointerStyle(.horizontalText)
                    .anchorPreference(key: MarkdownLayoutKey.self, value: .bounds) { bounds in
                        [MarkdownLayout(blockId: blockId, bounds: bounds, isBlock: isBlock, blockText: blockText)]
                    }
            }
        } else {
            content
        }
        
    }
}

public extension View {
    func makeCanSelectable(isBlock: Bool = false, blockText: String = "") -> some View {
        self.modifier(MakeTextSelectable(isBlock: isBlock, blockText: blockText))
    }
}
