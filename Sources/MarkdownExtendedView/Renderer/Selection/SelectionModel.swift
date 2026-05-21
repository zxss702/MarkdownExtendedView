// SelectionModel.swift
//  MarkdownExtendedView
//
//  Created by OpenAI Codex on 2026-04-21.
// Licensed under MIT License

import Foundation
import Observation
import SwiftUI

private struct SelectionBuildResult: @unchecked Sendable {
    let document: SelectionDocument
    let cache: [SelectionLayoutSnapshotKey: SelectionLayoutSnapshot]
}

private struct SendableBaseLayouts: @unchecked Sendable {
    let items: [(layout: SwiftUI.Text.Layout, origin: CGPoint)]
}

private struct SendableFormulaData: @unchecked Sendable {
    let items: [(FormulaSelectionData, CGRect)]
}

enum SelectionAffinity: Int, Comparable {
    case downstream
    case upstream

    static func < (lhs: SelectionAffinity, rhs: SelectionAffinity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SelectionPosition: Hashable, Comparable {
    let offset: Int
    let affinity: SelectionAffinity

    static func < (lhs: SelectionPosition, rhs: SelectionPosition) -> Bool {
        if lhs.offset == rhs.offset {
            return lhs.affinity < rhs.affinity
        }
        return lhs.offset < rhs.offset
    }
}

struct SelectionRange: Hashable {
    let start: SelectionPosition
    let end: SelectionPosition

    var isCollapsed: Bool {
        start.offset == end.offset
    }

    init(start: SelectionPosition, end: SelectionPosition) {
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    init(from: SelectionPosition, to: SelectionPosition) {
        self.init(start: from, end: to)
    }

    func clamped(to textLength: Int) -> SelectionRange? {
        guard textLength > 0 else {
            return nil
        }

        let startOffset = min(max(start.offset, 0), textLength)
        let endOffset = min(max(end.offset, 0), textLength)

        return SelectionRange(
            start: SelectionPosition(offset: startOffset, affinity: start.affinity),
            end: SelectionPosition(offset: endOffset, affinity: end.affinity)
        )
    }
}

struct SelectionRect: Hashable {
    var rect: CGRect
    let layoutDirection: LayoutDirection
    var containsStart: Bool
    var containsEnd: Bool

    init(
        rect: CGRect,
        layoutDirection: LayoutDirection,
        containsStart: Bool = false,
        containsEnd: Bool = false
    ) {
        self.rect = rect
        self.layoutDirection = layoutDirection
        self.containsStart = containsStart
        self.containsEnd = containsEnd
    }
}

@MainActor
@Observable
final class SelectionModel {
    var selectedRange: SelectionRange? {
        willSet {
            selectionWillChange?()
        }
        didSet {
            selectionRects = selectedRange.map(document.selectionRects(for:)) ?? []
            selectionDidChange?()
        }
    }

    private(set) var selectionRects: [SelectionRect] = []

    @ObservationIgnored var selectionWillChange: (() -> Void)?
    @ObservationIgnored var selectionDidChange: (() -> Void)?

    @ObservationIgnored private var cachedTextHitRects: [CGRect] = []
    @ObservationIgnored private var cachedLayoutSnapshots: [SelectionLayoutSnapshotKey: SelectionLayoutSnapshot] = [:]
    @ObservationIgnored private var dragStartPoint: CGPoint?
    @ObservationIgnored private var dragCurrentPoint: CGPoint?
    @ObservationIgnored private var lastLayoutInput: SelectionLayoutInput?

    private var document = SelectionDocument.empty

    var hasText: Bool {
        document.textLength > 0
    }

    var hasNonCollapsedSelection: Bool {
        guard let selectedRange else { return false }
        return !selectedRange.isCollapsed
    }

    var isDraggingSelection: Bool {
        dragStartPoint != nil && dragCurrentPoint != nil
    }

    func updateLayout(_ input: SelectionLayoutInput) async {
        guard input != lastLayoutInput else {
            return
        }

        if !isDraggingSelection {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }

        // 1. Safely resolve all geometry bounds on MainActor
        let baseLayouts = SendableBaseLayouts(items: input.base.map { (layout: $0.layout, origin: input.geometry[$0.origin]) })
        let formulasData = SendableFormulaData(items: input.formulas.map { (formula: $0, rect: input.geometry[$0.bounds]) })
        let isDragging = self.isDraggingSelection
        let cachedSnapshots = self.cachedLayoutSnapshots
        
        // 2. Detach heavy string operations and layout building
        let result = await Task.detached(priority: .userInitiated) { () -> SelectionBuildResult in
            var snapshots: [SelectionLayoutSnapshot] = []
            
            snapshots.append(contentsOf: baseLayouts.items.compactMap {
                SelectionLayoutSnapshot(base: $0.layout, origin: $0.origin)
            })
            
            snapshots.append(contentsOf: SelectionDocumentBuilder.makeSnapshots(from: formulasData.items))
            
            var localCache = cachedSnapshots
            let document: SelectionDocument
            
            if isDragging {
                for snapshot in snapshots {
                    localCache[snapshot.key] = snapshot
                }
                document = SelectionDocumentBuilder.build(from: Array(localCache.values))
            } else {
                localCache.removeAll()
                document = SelectionDocumentBuilder.build(from: snapshots)
            }
            
            return SelectionBuildResult(document: document, cache: localCache)
        }.value

        guard !Task.isCancelled else {
            return
        }

        lastLayoutInput = input
        document = result.document
        cachedLayoutSnapshots = result.cache
        cachedTextHitRects = result.document.hitRects

        if isDraggingSelection {
            updateDraggedSelection()
        } else {
            selectedRange = nil
        }
    }

    func clearSelection() {
        dragStartPoint = nil
        dragCurrentPoint = nil
        cachedLayoutSnapshots.removeAll()
        selectedRange = nil
    }

    func selectAll() {
        guard hasText else {
            selectedRange = nil
            return
        }

        selectedRange = SelectionRange(
            start: document.startPosition,
            end: document.endPosition
        )
    }

    @discardableResult
    func beginSelectionDrag(at point: CGPoint) -> Bool {
        guard containsText(at: point), closestPosition(to: point) != nil else {
            clearSelection()
            return false
        }

        dragStartPoint = point
        dragCurrentPoint = point
        updateDraggedSelection()
        return true
    }

    func updateSelectionDrag(to point: CGPoint) {
        guard dragStartPoint != nil else {
            return
        }

        dragCurrentPoint = point
        updateDraggedSelection()
    }

    func endSelectionDrag() {
        dragStartPoint = nil
        dragCurrentPoint = nil

        if selectedRange?.isCollapsed == true {
            clearSelection()
        }
    }

    func closestPosition(to point: CGPoint) -> SelectionPosition? {
        document.closestPosition(to: point)
    }

    func closestPosition(to point: CGPoint, within range: SelectionRange) -> SelectionPosition? {
        guard let position = closestPosition(to: point) else { return nil }
        if position <= range.start { return range.start }
        if position >= range.end { return range.end }
        return position
    }

    func characterRange(at point: CGPoint) -> SelectionRange? {
        document.characterRange(at: point)
    }

    func position(from position: SelectionPosition, offset: Int) -> SelectionPosition? {
        document.position(from: position, offset: offset)
    }

    func offset(from: SelectionPosition, to: SelectionPosition) -> Int {
        to.offset - from.offset
    }

    var startPosition: SelectionPosition {
        document.startPosition
    }

    var endPosition: SelectionPosition {
        document.endPosition
    }

    func textHitRects() -> [CGRect] {
        cachedTextHitRects
    }

    func containsText(at point: CGPoint) -> Bool {
        cachedTextHitRects.contains { $0.contains(point) }
    }

    func selectedPlainText() -> String? {
        guard let selectedRange, !selectedRange.isCollapsed else {
            return nil
        }

        return text(in: selectedRange)
    }

    func text(in range: SelectionRange) -> String {
        document.plainText(in: range)
    }

    func attributedText(in range: SelectionRange) -> NSAttributedString {
        document.attributedText(in: range)
    }

    func firstRect(for range: SelectionRange) -> CGRect {
        document.firstRect(for: range)
    }

    func caretRect(for position: SelectionPosition) -> CGRect {
        document.caretRect(for: position)
    }

    func selectionRectsSync(for range: SelectionRange) -> [SelectionRect] {
        document.selectionRects(for: range)
    }

    private func buildDocument(from snapshots: [SelectionLayoutSnapshot]) -> SelectionDocument {
        // Now handled inside the detached task
        return SelectionDocument.empty
    }

    private func updateDraggedSelection() {
        guard
            let dragStartPoint,
            let dragCurrentPoint,
            let start = document.closestPosition(to: dragStartPoint),
            let end = document.closestPosition(to: dragCurrentPoint)
        else {
            return
        }

        selectedRange = SelectionRange(from: start, to: end)
    }
}
