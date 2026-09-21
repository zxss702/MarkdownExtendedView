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
    /// Section snapshot identity + offset inside that section, filled
    /// by the document — rebuild-stable so a selection survives lazy
    /// row materialization mid-drag.
    var sectionKey: SelectionSnapshotIdentity? = nil
    var localOffset: Int = 0
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
    /// Merged snapshots keyed by position-independent identity — during
    /// a drag, rematerialized rows overwrite their stale entry instead
    /// of accumulating duplicates.
    private var cachedLayoutSnapshots: [SelectionSnapshotIdentity: SelectionLayoutSnapshot] = [:]
    /// Content fingerprints (text + frame) of the document's sources —
    /// any change triggers a rebuild.
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
        anchors: [MarkdownLayout],
        geometry: GeometryProxy
    ) {
        let resolved = anchors.map {
            ResolvedSelectionAnchor(
                rect: geometry[$0.bounds],
                isBlock: $0.isBlock,
                blockText: $0.blockText,
                linePrefix: $0.linePrefix,
                richImage: $0.richImage,
                selectionID: $0.selectionID,
                textLayouts: $0.textLayouts
            )
        }

        let snapshots = SelectionDocumentBuilder.makeSnapshots(
            anchors: resolved,
            geometry: geometry
        )

        // Identity is position-independent — a row keeps it across
        // materialization and frame drift, so the cache overwrites in
        // place instead of accumulating per-frame duplicates.
        func cacheKey(_ snapshot: SelectionLayoutSnapshot) -> SelectionSnapshotIdentity {
            snapshot.identity ?? SelectionSnapshotIdentity(
                anchor: "", text: snapshot.key.text, ordinal: snapshot.key.minY
            )
        }

        // Merge every update into a rolling document model so selection
        // survives rows scrolling out of the lazy window — not just
        // during drags. Each update replaces the snapshots of the
        // anchors it claims atomically (a row's texts may change), while
        // anchors absent from this update keep their cached sections.
        let freshIdentities = Set(snapshots.map(cacheKey))
        let freshAnchors = Set(freshIdentities.map(\.anchor))
        let cachedAnchors = Set(cachedLayoutSnapshots.keys.map(\.anchor))
        if !freshAnchors.isEmpty, freshAnchors.isDisjoint(with: cachedAnchors) {
            // No overlap at all means the content was wholesale-replaced
            // (new document), not scrolled — drop everything stale.
            cachedLayoutSnapshots.removeAll()
        } else {
            cachedLayoutSnapshots = cachedLayoutSnapshots.filter { id, _ in
                !freshAnchors.contains(id.anchor) || freshIdentities.contains(id)
            }
        }
        for snapshot in snapshots {
            cachedLayoutSnapshots[cacheKey(snapshot)] = snapshot
        }

        let mergedKeys = Set(cachedLayoutSnapshots.values.map(\.key))
        guard mergedKeys != documentSourceKeys else { return }
        documentSourceKeys = mergedKeys
        document = SelectionDocumentBuilder.build(from: Array(cachedLayoutSnapshots.values))
        remapSelection()
    }

    /// Section ranges shift when the document rebuilds — remap positions
    /// through their rebuild-stable snapshot identities. Positions whose
    /// source snapshot is gone are dropped.
    private func remapSelection() {
        selectionAnchor = selectionAnchor.flatMap { document.translated($0) }
        if
            let range = selectedRange,
            let start = document.translated(range.start),
            let end = document.translated(range.end)
        {
            selectedRange = SelectionRange(start: start, end: end)
        } else {
            selectedRange = nil
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
