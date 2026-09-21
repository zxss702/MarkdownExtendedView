// SelectionModel.swift
// MarkdownExtendedView
//
//  Observable selection state for a selectable region. Document rebuilds
//  are synchronous; while a drag is in flight, incoming snapshots merge
//  into a cache keyed by stable identity so scrolling preserves the
//  selection — otherwise a rebuild replaces the document and clears the
//  selection.

import Foundation
import SwiftUI

enum SelectionAffinity {
    case upstream
    case downstream
}

struct SelectionPosition: Equatable {
    var offset: Int
    var affinity: SelectionAffinity
}

struct SelectionRange: Equatable {
    var start: SelectionPosition
    var end: SelectionPosition

    var isCollapsed: Bool {
        start == end
    }
}

struct SelectionRect {
    var rect: CGRect
    var layoutDirection: LayoutDirection
    var containsStart: Bool = false
    var containsEnd: Bool = false
}

@MainActor
@Observable
final class SelectionModel {

    var selectionRects: [SelectionRect] {
        guard let selectedRange else {
            return []
        }

        return document.selectionRects(for: selectedRange)
    }

    var selectedRange: SelectionRange?

    private(set) var selectionAnchor: SelectionPosition?
    private(set) var isDragging = false
    private var document = SelectionDocument.empty
    private var cachedLayoutSnapshots: [SelectionLayoutSnapshotKey: SelectionLayoutSnapshot] = [:]
    private var documentSourceKeys: Set<SelectionLayoutSnapshotKey> = []

    var selectionIsActive: Bool {
        selectedRange != nil || isDragging || selectionAnchor != nil
    }

    var hasText: Bool {
        document.textLength > 0
    }

    var hasNonCollapsedSelection: Bool {
        selectedRange.map { !$0.isCollapsed } ?? false
    }

    var isDraggingSelection: Bool {
        isDragging
    }

    // MARK: - Layout intake (synchronous)

    func updateLayout(
        textLayouts: SwiftUI.Text.LayoutKey.Value,
        anchors: [MarkdownLayout],
        geometry: GeometryProxy
    ) {
        let resolved = anchors.map {
            ResolvedSelectionAnchor(
                rect: geometry[$0.bounds],
                isBlock: $0.isBlock,
                blockText: $0.blockText,
                linePrefix: $0.linePrefix,
                richImage: $0.richImage
            )
        }

        let snapshots = SelectionDocumentBuilder.makeSnapshots(
            textLayouts: textLayouts,
            anchors: resolved,
            geometry: geometry
        )

        for snapshot in snapshots {
            cachedLayoutSnapshots[snapshot.key] = snapshot
        }

        if isDragging {
            // Merge with previously seen snapshots so scroll-caused
            // materialization changes don't lose the in-flight selection.
            let mergedKeys = Set(cachedLayoutSnapshots.keys)
            if mergedKeys != documentSourceKeys {
                document = SelectionDocumentBuilder.build(from: Array(cachedLayoutSnapshots.values))
                documentSourceKeys = mergedKeys
            }
        } else {
            // Rebuild only when the snapshot set actually changed —
            // identical key sets mean the visible layout is unchanged.
            let keys = Set(snapshots.map(\.key))
            if keys != documentSourceKeys {
                document = SelectionDocumentBuilder.build(from: snapshots)
                documentSourceKeys = keys
                selectedRange = nil
            }
        }
    }

    // MARK: - Selection lifecycle

    func clearSelection() {
        selectedRange = nil
        selectionAnchor = nil
        isDragging = false
    }

    @discardableResult
    func selectAll() -> Bool {
        guard document.textLength > 0 else {
            clearSelection()
            return false
        }

        let start = document.startPosition
        let end = document.endPosition

        selectionAnchor = start
        selectedRange = SelectionRange(start: start, end: end)
        isDragging = false
        return true
    }

    func updateSelection(to point: CGPoint, initialAnchor: SelectionPosition? = nil) {
        if let initialAnchor {
            selectionAnchor = initialAnchor
        }

        guard
            let anchor = selectionAnchor,
            let position = document.closestPosition(to: point)
        else {
            return
        }

        if anchor.offset <= position.offset {
            selectedRange = SelectionRange(start: anchor, end: position)
        } else {
            selectedRange = SelectionRange(start: position, end: anchor)
        }
    }

    func updateSelectionDrag(to point: CGPoint) {
        updateSelection(to: point)
    }

    func beginSelectionDrag(at point: CGPoint) {
        selectionAnchor = document.closestPosition(to: point)
        selectedRange = nil
        isDragging = true
    }

    func endSelectionDrag() {
        isDragging = false
    }

    // MARK: - Queries

    func selectedPlainText() -> String? {
        guard let selectedRange, !selectedRange.isCollapsed else {
            return nil
        }

        return document.plainText(in: selectedRange)
    }

    func selectedAttributedText() -> NSAttributedString? {
        guard let selectedRange, !selectedRange.isCollapsed else {
            return nil
        }

        return document.attributedText(in: selectedRange)
    }

    /// Rich "含图像" copy: selected formulas/mermaid/code references
    /// emit images and tinted icon+label instead of plain payloads.
    func selectedRichText() -> NSAttributedString? {
        guard let selectedRange, !selectedRange.isCollapsed else {
            return nil
        }

        return document.richText(in: selectedRange)
    }

    /// Resolved link destination under `point` (container coordinates).
    func link(at point: CGPoint) -> String? {
        document.link(at: point)
    }

    /// Whether `point` falls inside the current non-collapsed selection.
    func isPointInsideSelection(_ point: CGPoint) -> Bool {
        selectionRects.contains { $0.rect.insetBy(dx: -1, dy: -1).contains(point) }
    }
}
