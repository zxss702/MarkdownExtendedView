// SelectionDocumentBuilder.swift
//  MarkdownExtendedView
//
//  Builds a SelectionDocument from `MarkdownLayoutKey` anchor payloads —
//  each anchor arrives with the `Text.LayoutKey` layouts of its own
//  subtree already attached. Markdown texts may carry a
//  `MarkdownBlockMappingsAttribute` for direct run-encoded extraction;
//  every other text (including all external `Text` views) is mapped via
//  guarded Core Text reflection, so nothing here can crash on layout
//  internals changing.

import CoreText
import Foundation
import SwiftUI

/// An anchor rect resolved into the container's coordinate space.
struct ResolvedSelectionAnchor {
    let rect: CGRect
    let isBlock: Bool
    let blockText: String
    let linePrefix: String?
    /// Rendered image for rich copies (mermaid diagram, block formula).
    var richImage: MTImage? = nil
    /// Caller-supplied data-level identity — survives lazy
    /// dematerialization, unlike view-state ids.
    var selectionID: String? = nil
    /// Text layouts captured inside this anchor's own subtree —
    /// structural binding, no geometric matching.
    var textLayouts: SwiftUI.Text.LayoutKey.Value = []
    /// Markdown-source wrappers around the anchor's copied sections
    /// (code-block fences) — attached to the first/last snapshot.
    var sourcePrefix: String? = nil
    var sourceSuffix: String? = nil
}

/// The change-detection key for `.task(id:)` in `SelectableModifier`.
struct SelectionLayoutInputID: Equatable {
    let anchors: [MarkdownLayout]
    let size: CGSize
}

enum SelectionDocumentBuilder {

    // MARK: - Snapshot collection

    /// Produces snapshots for atomic anchors (formulas, images, cards,
    /// bullets) plus every `Text` bundled inside a non-atomic anchor's
    /// own payload. Texts outside anchors never arrive here — selection
    /// is opt-in via `makeCanSelectable()`, and each anchor captures its
    /// subtree's layouts structurally rather than by frame containment.
    static func makeSnapshots(
        anchors: [ResolvedSelectionAnchor],
        geometry: GeometryProxy
    ) -> [SelectionLayoutSnapshot] {
        var snapshots: [SelectionLayoutSnapshot] = []
        snapshots.reserveCapacity(anchors.count * 2)

        for anchor in anchors {
            let anchorStart = snapshots.count
            if anchor.isBlock {
                if var snapshot = SelectionLayoutSnapshot(anchor: anchor) {
                    snapshot.anchorID = anchor.selectionID
                    snapshots.append(snapshot)
                }
            } else {
                for proxy in anchor.textLayouts {
                    let origin = geometry[proxy.origin]
                    if var snapshot = SelectionLayoutSnapshot(
                        base: proxy.layout,
                        origin: origin,
                        linePrefix: anchor.linePrefix
                    ) {
                        snapshot.anchorID = anchor.selectionID
                        snapshots.append(snapshot)
                    }
                }
            }

            // The anchor's source wrapper (code fences) rides on its
            // first/last section in display order — a selection that
            // doesn't reach the boundary drops the fence.
            if anchor.sourcePrefix != nil || anchor.sourceSuffix != nil {
                snapshots[anchorStart...].sort(by: areInDisplayOrder)
                if anchorStart < snapshots.count {
                    snapshots[anchorStart].sourcePrefix = anchor.sourcePrefix
                    snapshots[snapshots.count - 1].sourceSuffix = anchor.sourceSuffix
                }
            }
        }

        // Assign position-independent identities in display order. An
        // anchor's injected `selectionID` fully disambiguates the row,
        // so the ordinal only separates same-text snapshots sharing an
        // anchor (or un-IDed content, where it falls back to text order).
        // Frames deliberately play no part — they drift while a lazy
        // stack remeasures during scroll.
        snapshots.sort(by: areInDisplayOrder)
        var ordinals: [SnapshotOrdinalKey: Int] = [:]
        for index in snapshots.indices {
            let key = SnapshotOrdinalKey(
                anchor: snapshots[index].anchorID ?? "",
                text: snapshots[index].attributedString.string
            )
            let ordinal = ordinals[key, default: 0]
            ordinals[key] = ordinal + 1
            snapshots[index].identity = SelectionSnapshotIdentity(
                anchor: key.anchor, text: key.text, ordinal: ordinal
            )
        }

        return snapshots
    }

    // MARK: - Document assembly

    static func build(from snapshots: [SelectionLayoutSnapshot]) -> SelectionDocument {
        let layouts = snapshots.sorted(by: areInDisplayOrder)

        let attributedString = NSMutableAttributedString()
        let sourceString = NSMutableAttributedString()
        var sections: [SelectionSection] = []
        var lines: [SelectionLine] = []
        var slices: [SelectionSlice] = []

        for layout in layouts {
            let sectionStart = attributedString.length
            attributedString.append(layout.attributedString)
            let sectionRange = sectionStart..<attributedString.length
            let sectionSourceStart = sourceString.length
            sourceString.append(layout.source)

            if !layout.attributedString.string.isEmpty {
                sections.append(.init(
                    range: sectionRange,
                    frame: layout.frame,
                    linePrefix: layout.linePrefix,
                    key: layout.identity,
                    sourcePrefix: layout.sourcePrefix,
                    sourceSuffix: layout.sourceSuffix
                ))
            }

            for line in layout.lines {
                let sliceStart = slices.count

                for slice in line.slices {
                    slices.append(
                        SelectionSlice(
                            range: slice.characterRange.offsetBySelection(by: sectionStart),
                            rect: slice.rect,
                            lineIndex: lines.count,
                            layoutDirection: slice.layoutDirection,
                            link: slice.link,
                            rich: slice.rich,
                            sourceRange: (slice.sourceRange ?? slice.characterRange)
                                .offsetBySelection(by: sectionSourceStart)
                        )
                    )
                }

                if sliceStart < slices.count {
                    lines.append(
                        SelectionLine(
                            rect: line.rect,
                            sliceRange: sliceStart..<slices.count
                        )
                    )
                }
            }
        }

        return SelectionDocument(
            attributedString: attributedString,
            sections: sections,
            lines: lines,
            slices: slices,
            sourceString: sourceString
        )
    }

    private static func areInDisplayOrder(
        _ lhs: SelectionLayoutSnapshot,
        _ rhs: SelectionLayoutSnapshot
    ) -> Bool {
        let overlapY = min(lhs.frame.maxY, rhs.frame.maxY) - max(lhs.frame.minY, rhs.frame.minY)
        let minHeight = min(lhs.frame.height, rhs.frame.height)

        // If they overlap significantly vertically, they are on the same line
        if overlapY > 0 && overlapY > minHeight * 0.3 {
            return lhs.frame.minX < rhs.frame.minX
        }

        // Otherwise, they are on different lines
        if lhs.frame.minY != rhs.frame.minY {
            return lhs.frame.minY < rhs.frame.minY
        }

        return lhs.frame.minX < rhs.frame.minX
    }
}

// MARK: - Layout snapshot

struct SelectionLayoutSnapshot: @unchecked Sendable {
    let key: SelectionLayoutSnapshotKey
    /// Containing anchor's injected `selectionID`, if any.
    var anchorID: String?
    /// Assigned in `makeSnapshots` once display order is known.
    var identity: SelectionSnapshotIdentity?
    let attributedString: NSAttributedString
    /// Parallel markdown-source string — slices carry `sourceRange`
    /// into it. Equals `attributedString` when source == rendered.
    let source: NSAttributedString
    /// Source wrappers inherited from the anchor (code fences) — set
    /// on the anchor's first/last snapshot in display order.
    var sourcePrefix: String? = nil
    var sourceSuffix: String? = nil
    let frame: CGRect
    let lines: [SelectionLineSnapshot]
    let linePrefix: String?

    /// Atomic block (formula, image, card, bullet): one slice covering the
    /// whole rect whose text is the copy payload.
    init?(anchor: ResolvedSelectionAnchor) {
        let text = anchor.blockText
        let length = (text as NSString).length
        guard length > 0, anchor.rect.isFiniteForSelection, !anchor.rect.isNull else {
            return nil
        }

        self.attributedString = NSAttributedString(string: text)
        self.source = self.attributedString
        self.frame = anchor.rect
        self.linePrefix = anchor.linePrefix
        guard
            let key = SelectionLayoutSnapshotKey(
                text: text,
                frame: anchor.rect,
                hasRich: anchor.richImage != nil
            )
        else {
            return nil
        }
        self.key = key

        let slice = SelectionSliceSnapshot(
            rect: anchor.rect,
            characterRange: 0..<length,
            layoutDirection: .leftToRight,
            link: nil,
            rich: anchor.richImage.map { .image($0) }
        )
        self.lines = [SelectionLineSnapshot(rect: anchor.rect, slices: [slice])]
    }

    /// Text layout. Prefers the baked per-character mappings attribute
    /// when it is consistent with the laid-out slice count; otherwise
    /// falls back to Core Text reflection of the real character ranges.
    init?(base: SwiftUI.Text.Layout, origin: CGPoint, linePrefix: String?) {
        self.linePrefix = linePrefix

        let mappings = Self.firstMappings(in: base)
        if let mappings {
            if let mapped = Self.makeMappedLines(from: base, mappings: mappings, origin: origin) {
                self.lines = mapped.lines
                self.attributedString = mapped.attributedString
                self.source = mapped.source
            } else {
                guard let reflected = Self.makeReflectedLines(from: base, origin: origin) else {
                    return nil
                }
                self.lines = reflected.lines
                self.attributedString = reflected.attributedString
                self.source = reflected.attributedString
            }
        } else {
            guard let reflected = Self.makeReflectedLines(from: base, origin: origin) else {
                return nil
            }
            self.lines = reflected.lines
            self.attributedString = reflected.attributedString
            self.source = reflected.attributedString
        }

        guard self.attributedString.length > 0 else {
            return nil
        }

        guard
            let frame = SelectionLayoutSnapshot.makeFrame(from: base, origin: origin),
            let key = SelectionLayoutSnapshotKey(text: self.attributedString.string, frame: frame)
        else {
            return nil
        }
        self.frame = frame
        self.key = key
    }

    // MARK: Mapping-attribute extraction

    private static func firstMappings(
        in layout: SwiftUI.Text.Layout
    ) -> [GlobalSelectionCache.CharacterMapping]? {
        for line in layout {
            for run in line {
                if let attr = run[MarkdownBlockMappingsAttribute.self] {
                    return attr.mappings
                }
            }
        }
        return nil
    }

    /// Builds lines from baked mappings. Requires the total slice count
    /// to equal the mapped glyph count — otherwise returns nil so the
    /// caller can fall back to reflection. Mappings are run-length
    /// encoded; `MDGlyphCursor` expands them lazily in order.
    private static func makeMappedLines(
        from base: SwiftUI.Text.Layout,
        mappings: [GlobalSelectionCache.CharacterMapping],
        origin: CGPoint
    ) -> (lines: [SelectionLineSnapshot], attributedString: NSAttributedString, source: NSAttributedString)? {
        // Preflight: every glyph positionally consumes one mapping,
        // including `Text(Image)` slices, which legitimately carry no
        // attributes of their own. `\n` mappings own no slice — they
        // are consumed separately at line boundaries.
        var totalSlices = 0
        for line in base {
            for run in line {
                totalSlices += run.count
            }
        }
        var cursor = GlobalSelectionCache.MDGlyphCursor(mappings)
        guard totalSlices == cursor.glyphCount else {
            return nil
        }

        let attributedString = NSMutableAttributedString()
        let sourceString = NSMutableAttributedString()
        var lines: [SelectionLineSnapshot] = []
        var pendingGroup: String? = nil
        var pendingSlice: SelectionSliceSnapshot? = nil

        for line in base {
            let lineRect = line.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
            var lineSlices: [SelectionSliceSnapshot] = []

            // A line break occupies a mapping but renders no glyph —
            // emit a zero-width slice at the line's trailing edge so it
            // stays selectable and copies as `\n`.
            func consumeLineBreaks() {
                while let lineBreak = cursor.nextLineBreak() {
                    let start = attributedString.length
                    attributedString.append(NSAttributedString(string: String(lineBreak.char)))
                    let sourceStart = sourceString.length
                    sourceString.append(NSAttributedString(string: String(lineBreak.char)))
                    lineSlices.append(
                        SelectionSliceSnapshot(
                            rect: CGRect(
                                x: lineRect.maxX, y: lineRect.minY,
                                width: 0, height: lineRect.height
                            ),
                            characterRange: start..<attributedString.length,
                            layoutDirection: .leftToRight,
                            sourceRange: sourceStart..<sourceString.length
                        )
                    )
                }
            }

            for run in line {
                for slice in run {
                    consumeLineBreaks()
                    guard let mapping = cursor.nextGlyph() else { return nil }
                    let rect = slice.typographicBounds.rect
                        .offsetBy(dx: origin.x, dy: origin.y)

                    if let group = mapping.group {
                        // Grouped glyphs (e.g. an inline code reference)
                        // merge into one slice — selecting any part
                        // selects the whole unit and copies once.
                        if group == pendingGroup, let merged = pendingSlice {
                            pendingSlice = SelectionSliceSnapshot(
                                rect: merged.rect.union(rect),
                                characterRange: merged.characterRange,
                                layoutDirection: merged.layoutDirection,
                                sourceRange: merged.sourceRange,
                                link: merged.link,
                                rich: merged.rich
                            )
                            continue
                        }
                        if let slice = pendingSlice {
                            lineSlices.append(slice)
                            pendingSlice = nil
                            pendingGroup = nil
                        }
                        pendingGroup = group
                        let start = attributedString.length
                        if !mapping.char.isEmpty {
                            attributedString.append(NSAttributedString(string: String(mapping.char)))
                        }
                        let sourceStart = sourceString.length
                        if let source = mapping.source, !source.isEmpty {
                            sourceString.append(NSAttributedString(string: String(source)))
                        } else if !mapping.char.isEmpty {
                            sourceString.append(NSAttributedString(string: String(mapping.char)))
                        }
                        // Grouped slices (code references) copy their
                        // raw source — rich never replaces it.
                        pendingSlice = SelectionSliceSnapshot(
                            rect: rect,
                            characterRange: start..<attributedString.length,
                            layoutDirection: run.layoutDirection,
                            sourceRange: sourceStart..<sourceString.length,
                            link: mapping.link
                        )
                        continue
                    }

                    if let slice = pendingSlice {
                        lineSlices.append(slice)
                        pendingSlice = nil
                        pendingGroup = nil
                    }

                    let charLength = mapping.char.utf16.count
                    guard charLength > 0 else { continue }

                    let start = attributedString.length
                    attributedString.append(NSAttributedString(string: String(mapping.char)))
                    let sourceStart = sourceString.length
                    sourceString.append(
                        NSAttributedString(string: String(mapping.source ?? mapping.char))
                    )
                    lineSlices.append(
                        SelectionSliceSnapshot(
                            rect: rect,
                            characterRange: start..<attributedString.length,
                            layoutDirection: run.layoutDirection,
                            sourceRange: sourceStart..<sourceString.length,
                            link: mapping.link,
                            rich: mapping.richImage
                                .flatMap { $0.resolve() }
                                .map { .image($0.image) }
                        )
                    )
                }
            }

            consumeLineBreaks()

            if let slice = pendingSlice {
                lineSlices.append(slice)
                pendingSlice = nil
                pendingGroup = nil
            }
            lines.append(SelectionLineSnapshot(rect: lineRect, slices: lineSlices))
        }

        return (lines, attributedString, sourceString)
    }

    // MARK: Reflection extraction (guarded)

    /// Character indices from Core Text are positions in the line
    /// fragment's `attributedString` — a string shared by every line of a
    /// text (and deduplicated across concatenated `Text` pieces). The
    /// section string is the join of the unique fragment strings; each
    /// slice's range is offset by its fragment's position in that join.
    private static func makeReflectedLines(
        from base: SwiftUI.Text.Layout,
        origin: CGPoint
    ) -> (lines: [SelectionLineSnapshot], attributedString: NSAttributedString)? {
        var lineFragments: [NSTextLineFragment?] = []
        for line in base {
            lineFragments.append(line.selectionLineFragment)
        }

        let uniqueStrings = lineFragments
            .compactMap { $0?.attributedString }
            .removingSelectionIdenticalDuplicates()
        let (joined, offsets) = uniqueStrings.joinedForSelection()
        guard joined.length > 0 else {
            return nil
        }

        var lines: [SelectionLineSnapshot] = []
        var index = 0
        for line in base {
            defer { index += 1 }
            let fragment = lineFragments[index]
            let lineRect = line.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
            let offset = fragment.flatMap {
                offsets[ObjectIdentifier($0.attributedString)]
            } ?? 0

            var lineSlices: [SelectionSliceSnapshot] = []
            for run in line {
                let renderedSlices = zip(run, run.selectionCharacterRanges).map { slice, characterRange in
                    SelectionSliceSnapshot(
                        rect: slice.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y),
                        characterRange: characterRange.offsetBySelection(by: offset),
                        layoutDirection: run.layoutDirection
                    )
                }
                if !renderedSlices.isEmpty {
                    lineSlices.append(contentsOf: renderedSlices)
                } else if let fallbackRange = run.selectionCharacterRange, !fallbackRange.isEmpty {
                    lineSlices.append(
                        SelectionSliceSnapshot(
                            rect: run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y),
                            characterRange: fallbackRange.offsetBySelection(by: offset),
                            layoutDirection: run.layoutDirection
                        )
                    )
                }
            }

            if lineSlices.isEmpty, let fragment {
                let fallbackLength = fragment.attributedString.length
                if fallbackLength > 0 {
                    lineSlices = [
                        SelectionSliceSnapshot(
                            rect: lineRect,
                            characterRange: offset..<(offset + fallbackLength),
                            layoutDirection: .leftToRight
                        )
                    ]
                }
            }

            lines.append(SelectionLineSnapshot(rect: lineRect, slices: lineSlices))
        }

        return (lines, joined)
    }

    // MARK: Frame

    private static func makeFrame(from base: SwiftUI.Text.Layout, origin: CGPoint) -> CGRect? {
        var frame = CGRect.null

        for line in base {
            let rect = line.typographicBounds.rect
            guard rect.isFiniteForSelection else {
                continue
            }

            frame = frame.union(rect)
        }

        guard !frame.isNull else {
            return nil
        }

        let offsetFrame = frame.offsetBy(dx: origin.x, dy: origin.y)
        guard offsetFrame.isFiniteForSelection else {
            return nil
        }

        return offsetFrame
    }
}

// MARK: - Supporting types

/// Position-independent identity of a snapshot. `anchor` carries the
/// caller-injected `selectionID` ("" when none); `ordinal` separates
/// same-text snapshots sharing an anchor. Survives lazy
/// materialization and frame drift — the cache key for merging and
/// the payload that lets selection positions remap across rebuilds.
struct SelectionSnapshotIdentity: Hashable {
    let anchor: String
    let text: String
    let ordinal: Int
}

/// Hash key used when numbering duplicate (anchor, text) snapshots.
private struct SnapshotOrdinalKey: Hashable {
    let anchor: String
    let text: String
}

/// Content fingerprint — frame included, so a moved or relaid-out
/// snapshot registers as changed and the document rebuilds.
struct SelectionLayoutSnapshotKey: Hashable, @unchecked Sendable {
    let text: String
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
    /// Part of identity so an anchor gaining its image (an async-loaded
    /// markdown image) rebuilds the document and lands the rich payload.
    let hasRich: Bool

    init?(text: String, frame: CGRect, hasRich: Bool = false) {
        self.text = text
        self.hasRich = hasRich
        guard
            let minX = Self.rounded(frame.minX),
            let minY = Self.rounded(frame.minY),
            let width = Self.rounded(frame.width),
            let height = Self.rounded(frame.height)
        else {
            return nil
        }

        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    private static func rounded(_ value: CGFloat) -> Int? {
        let scaled = (value * 2).rounded(.toNearestOrEven)
        guard
            scaled.isFinite,
            scaled >= CGFloat(Int.min),
            scaled <= CGFloat(Int.max)
        else {
            return nil
        }

        return Int(scaled)
    }
}

struct SelectionLineSnapshot: @unchecked Sendable {
    let rect: CGRect
    let slices: [SelectionSliceSnapshot]
}

struct SelectionSliceSnapshot: @unchecked Sendable {
    let rect: CGRect
    let characterRange: Range<Int>
    let layoutDirection: LayoutDirection
    /// This slice's span inside the snapshot's `source` string — equal
    /// to `characterRange` when copy source and rendered text coincide.
    var sourceRange: Range<Int>? = nil
    /// Resolved absolute link destination on this glyph/slice.
    var link: String? = nil
    /// Rich-copy content (inline formula image, atomic block image).
    var rich: SelectionRichContent? = nil
}

// MARK: - Guarded reflection helpers

extension SwiftUI.Text.Layout.Line {
    /// `NSTextLineFragment` backing this laid-out line, reached via
    /// reflection. Returns nil when internals change — the caller falls
    /// back gracefully.
    var selectionLineFragment: NSTextLineFragment? {
        let mirror = Mirror(reflecting: self)
        if let fragment = mirror.descendant("_line", "nsLine", 0) as? NSTextLineFragment {
            return fragment
        }

        return mirror.descendant("_line", "nsLine") as? NSTextLineFragment
    }
}

extension SwiftUI.Text.Layout.Run {
    /// The run's full character range within its line fragment string.
    var selectionCharacterRange: Range<Int>? {
        guard let ctRun = selectionCTRun else {
            return nil
        }

        let runRange = CTRunGetStringRange(ctRun)
        let lowerBound = runRange.location
        let upperBound = lowerBound + runRange.length
        guard lowerBound < upperBound else {
            return nil
        }

        return lowerBound..<upperBound
    }

    /// Per-slice character ranges (one entry per glyph/slice of the run).
    var selectionCharacterRanges: [Range<Int>] {
        guard let ctRun = selectionCTRun else { return [] }

        let runRange = CTRunGetStringRange(ctRun)
        let start = runRange.location
        let end = start + runRange.length

        let characterIndices: [CFIndex]
        if let pointer = CTRunGetStringIndicesPtr(ctRun) {
            characterIndices = Array(UnsafeBufferPointer(start: pointer, count: count))
        } else {
            var temp = Array(repeating: 0 as CFIndex, count: count)
            CTRunGetStringIndices(ctRun, .init(), &temp)
            characterIndices = temp
        }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(count)

        for index in 0..<count {
            let characterIndex = characterIndices[index]
            let boundary: CFIndex

            if layoutDirection == .leftToRight {
                var nextIndex = index + 1
                while nextIndex < count, characterIndices[nextIndex] == characterIndex {
                    nextIndex += 1
                }
                boundary = nextIndex < count ? characterIndices[nextIndex] : end
            } else {
                var previousIndex = index - 1
                while previousIndex >= 0, characterIndices[previousIndex] == characterIndex {
                    previousIndex -= 1
                }
                boundary = previousIndex >= 0 ? characterIndices[previousIndex] : end
            }

            let lowerBound = Swift.max(Swift.min(characterIndex, boundary), start)
            let upperBound = Swift.min(Swift.max(characterIndex, boundary), end)
            ranges.append(lowerBound..<upperBound)
        }

        return ranges
    }

    var selectionCTRun: CTRun? {
        let mirror = Mirror(reflecting: self)
        guard
            let index = mirror.descendant("index") as? Int,
            let lineRef = mirror.descendant("line") as? CFTypeRef,
            CFGetTypeID(lineRef) == CTLineGetTypeID()
        else {
            return nil
        }

        let ctLine = unsafeDowncast(lineRef, to: CTLine.self)
        guard let ctRuns = CTLineGetGlyphRuns(ctLine) as? [CTRun], ctRuns.indices.contains(index) else {
            return nil
        }

        return ctRuns[index]
    }
}

private extension Array where Element: AnyObject {
    func removingSelectionIdenticalDuplicates() -> Self {
        var identifiers: Set<ObjectIdentifier> = []
        var result: Self = []

        result.reserveCapacity(underestimatedCount)

        for element in self {
            if identifiers.insert(.init(element)).inserted {
                result.append(element)
            }
        }

        return result
    }
}

private extension Array where Element == NSAttributedString {
    func joinedForSelection() -> (joined: NSAttributedString, characterOffsets: [ObjectIdentifier: Int]) {
        guard !isEmpty else {
            let attributedString = NSAttributedString()
            return (attributedString, [ObjectIdentifier(attributedString): 0])
        }

        guard count > 1 else {
            return (self[0], [ObjectIdentifier(self[0]): 0])
        }

        let joined = NSMutableAttributedString()
        var characterOffsets: [ObjectIdentifier: Int] = [:]
        characterOffsets.reserveCapacity(underestimatedCount)

        var offset = 0
        for element in self {
            joined.append(element)
            characterOffsets[ObjectIdentifier(element)] = offset
            offset += element.length
        }

        return (joined, characterOffsets)
    }
}

private extension Range where Bound == Int {
    func offsetBySelection(by value: Int) -> Range<Int> {
        (lowerBound + value)..<(upperBound + value)
    }
}

private extension CGRect {
    var isFiniteForSelection: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite
    }
}
