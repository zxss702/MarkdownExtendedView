// SelectionDocumentBuilder.swift
//  MarkdownExtendedView
//
//  Builds a SelectionDocument from collected `Text.LayoutKey` layouts and
//  `MarkdownLayoutKey` anchors. Markdown texts may carry a
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
}

/// The change-detection key for `.task(id:)` in `SelectableModifier`.
struct SelectionLayoutInputID: Equatable {
    let layouts: SwiftUI.Text.LayoutKey.Value
    let anchors: [MarkdownLayout]
    let size: CGSize
}

enum SelectionDocumentBuilder {

    // MARK: - Snapshot collection

    /// Produces snapshots for atomic anchors (formulas, images, cards,
    /// bullets) plus every `Text` whose center sits inside a non-atomic
    /// anchor. Texts inside atomic anchors, or outside all anchors, are
    /// excluded — selection is opt-in via `makeCanSelectable()`.
    static func makeSnapshots(
        textLayouts: SwiftUI.Text.LayoutKey.Value,
        anchors: [ResolvedSelectionAnchor],
        geometry: GeometryProxy
    ) -> [SelectionLayoutSnapshot] {
        var snapshots: [SelectionLayoutSnapshot] = []
        snapshots.reserveCapacity(anchors.count + textLayouts.count)

        for anchor in anchors where anchor.isBlock {
            if let snapshot = SelectionLayoutSnapshot(anchor: anchor) {
                snapshots.append(snapshot)
            }
        }

        for proxy in textLayouts {
            let origin = geometry[proxy.origin]
            guard let frame = textFrame(of: proxy.layout, origin: origin) else {
                continue
            }

            let center = CGPoint(x: frame.midX, y: frame.midY)
            if anchors.contains(where: { $0.isBlock && $0.rect.contains(center) }) {
                continue
            }
            guard let anchor = anchors.first(where: {
                !$0.isBlock && $0.rect.contains(center)
            }) else {
                continue
            }

            if let snapshot = SelectionLayoutSnapshot(
                base: proxy.layout,
                origin: origin,
                linePrefix: anchor.linePrefix
            ) {
                snapshots.append(snapshot)
            }
        }

        return snapshots
    }

    private static func textFrame(of layout: SwiftUI.Text.Layout, origin: CGPoint) -> CGRect? {
        var frame = CGRect.null
        for line in layout {
            let rect = line.typographicBounds.rect
            guard rect.isFiniteForSelection else { continue }
            frame = frame.union(rect)
        }
        guard !frame.isNull else { return nil }
        let offsetFrame = frame.offsetBy(dx: origin.x, dy: origin.y)
        return offsetFrame.isFiniteForSelection ? offsetFrame : nil
    }

    // MARK: - Document assembly

    static func build(from snapshots: [SelectionLayoutSnapshot]) -> SelectionDocument {
        let layouts = snapshots.sorted(by: areInDisplayOrder)

        let attributedString = NSMutableAttributedString()
        var sections: [SelectionSection] = []
        var lines: [SelectionLine] = []
        var slices: [SelectionSlice] = []

        for layout in layouts {
            let sectionStart = attributedString.length
            attributedString.append(layout.attributedString)
            let sectionRange = sectionStart..<attributedString.length

            if !layout.attributedString.string.isEmpty {
                sections.append(.init(
                    range: sectionRange,
                    frame: layout.frame,
                    linePrefix: layout.linePrefix
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
                            rich: slice.rich
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
            slices: slices
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
    let attributedString: NSAttributedString
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
            } else {
                guard let reflected = Self.makeReflectedLines(from: base, origin: origin) else {
                    return nil
                }
                self.lines = reflected.lines
                self.attributedString = reflected.attributedString
            }
        } else {
            guard let reflected = Self.makeReflectedLines(from: base, origin: origin) else {
                return nil
            }
            self.lines = reflected.lines
            self.attributedString = reflected.attributedString
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
    ) -> (lines: [SelectionLineSnapshot], attributedString: NSAttributedString)? {
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
                    lineSlices.append(
                        SelectionSliceSnapshot(
                            rect: CGRect(
                                x: lineRect.maxX, y: lineRect.minY,
                                width: 0, height: lineRect.height
                            ),
                            characterRange: start..<attributedString.length,
                            layoutDirection: .leftToRight
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
                        let rich: SelectionRichContent? = mapping.richImage
                            .flatMap { $0.resolve() }
                            .map {
                                .codeRef(
                                    icon: $0.image,
                                    label: mapping.richText ?? "",
                                    link: mapping.link
                                )
                            }
                        pendingSlice = SelectionSliceSnapshot(
                            rect: rect,
                            characterRange: start..<attributedString.length,
                            layoutDirection: run.layoutDirection,
                            link: mapping.link,
                            rich: rich
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
                    lineSlices.append(
                        SelectionSliceSnapshot(
                            rect: rect,
                            characterRange: start..<attributedString.length,
                            layoutDirection: run.layoutDirection,
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

        return (lines, attributedString)
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
    /// Resolved absolute link destination on this glyph/slice.
    var link: String? = nil
    /// Rich-copy content (inline formula/icon image, merged code
    /// reference, atomic block image).
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
