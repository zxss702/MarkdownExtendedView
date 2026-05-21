// SelectionDocumentBuilder.swift
//  MarkdownExtendedView
//
//  Created by OpenAI Codex on 2026-04-21.
// Licensed under MIT License

import CoreText
import Foundation
import SwiftUI

public struct FormulaSelectionData: Equatable, Sendable {
    public let id: UUID
    public let latex: String
    public let bounds: Anchor<CGRect>
    
    public init(id: UUID = UUID(), latex: String, bounds: Anchor<CGRect>) {
        self.id = id
        self.latex = latex
        self.bounds = bounds
    }
}

public struct FormulaSelectionKey: PreferenceKey {
    public static var defaultValue: [FormulaSelectionData] { [] }
    public static func reduce(value: inout [FormulaSelectionData], nextValue: () -> [FormulaSelectionData]) {
        value.append(contentsOf: nextValue())
    }
}

struct SelectionLayoutInput: Equatable, @unchecked Sendable {
    let base: SwiftUI.Text.LayoutKey.Value
    let formulas: [FormulaSelectionData]
    let geometry: GeometryProxy
    let containerSize: CGSize

    static func == (lhs: SelectionLayoutInput, rhs: SelectionLayoutInput) -> Bool {
        lhs.base == rhs.base && lhs.formulas == rhs.formulas && lhs.containerSize == rhs.containerSize
    }

    func buildSnapshots() -> [SelectionLayoutSnapshot] {
        var snapshots = SelectionDocumentBuilder.makeSnapshots(from: base, geometry: geometry)
        snapshots.append(contentsOf: SelectionDocumentBuilder.makeSnapshots(from: formulas.map { ($0, geometry[$0.bounds]) }))
        return snapshots
    }

    func buildDocument() -> SelectionDocument {
        SelectionDocumentBuilder.build(from: buildSnapshots())
    }
}

enum SelectionDocumentBuilder {
    static func makeSnapshots(
        from base: SwiftUI.Text.LayoutKey.Value,
        geometry: GeometryProxy
    ) -> [SelectionLayoutSnapshot] {
        base.compactMap {
            SelectionLayoutSnapshot(
                base: $0.layout,
                origin: geometry[$0.origin]
            )
        }
    }

    static func makeSnapshots(
        from formulas: [(FormulaSelectionData, CGRect)]
    ) -> [SelectionLayoutSnapshot] {
        formulas.compactMap {
            SelectionLayoutSnapshot(formula: $0.0, rect: $0.1)
        }
    }

    static func build(from snapshots: [SelectionLayoutSnapshot]) -> SelectionDocument {
        let layouts = snapshots.sorted(by: SelectionDocumentBuilder.areInDisplayOrder)

        let attributedString = NSMutableAttributedString()
        var sections: [SelectionSection] = []
        var lines: [SelectionLine] = []
        var slices: [SelectionSlice] = []

        for layout in layouts {
            let sectionStart = attributedString.length
            attributedString.append(layout.attributedString)
            let sectionRange = sectionStart..<attributedString.length

            if !layout.attributedString.string.isEmpty {
                sections.append(.init(range: sectionRange, frame: layout.frame))
            }

            for line in layout.lines {
                let sliceStart = slices.count

                for slice in line.slices {
                    slices.append(
                        SelectionSlice(
                            range: slice.characterRange.offsetBySelection(by: sectionStart),
                            rect: slice.rect,
                            lineIndex: lines.count,
                            layoutDirection: slice.layoutDirection
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

struct SelectionLayoutSnapshot: @unchecked Sendable {
    let key: SelectionLayoutSnapshotKey
    let attributedString: NSAttributedString
    let frame: CGRect
    let lines: [SelectionLineSnapshot]

    init?(base: SwiftUI.Text.Layout, origin: CGPoint) {
        let contents = base.materializeSelectionContents()
        let joinedAttributedString = contents.attributedStrings.joinedForSelection()
        guard joinedAttributedString.joined.length > 0 else {
            return nil
        }

        self.attributedString = joinedAttributedString.joined
        guard
            let frame = SelectionLayoutSnapshot.makeFrame(from: base, origin: origin),
            let key = SelectionLayoutSnapshotKey(text: self.attributedString.string, frame: frame)
        else {
            return nil
        }

        self.frame = frame
        self.key = key
        self.lines = SelectionLayoutSnapshot.makeLines(
            from: base,
            contents: contents,
            origin: origin
        )
    }

    init?(formula: FormulaSelectionData, rect: CGRect) {
        let text = formula.latex
        self.attributedString = NSAttributedString(string: text)
        self.frame = rect
        guard let key = SelectionLayoutSnapshotKey(text: text, frame: rect) else {
            return nil
        }
        self.key = key
        
        let slice = SelectionSliceSnapshot(rect: rect, characterRange: 0..<text.count, layoutDirection: .leftToRight)
        self.lines = [SelectionLineSnapshot(rect: rect, slices: [slice])]
    }

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

    private static func makeLines(
        from base: SwiftUI.Text.Layout,
        contents: SelectionLayoutContents,
        origin: CGPoint
    ) -> [SelectionLineSnapshot] {
        guard contents.attributedStrings.count > 1 else {
            return base.map {
                SelectionLineSnapshot(
                    base: $0,
                    lineFragment: $0.selectionLineFragment,
                    offset: 0,
                    origin: origin
                )
            }
        }

        let (_, offsets) = contents.layoutAttributedStrings.joinedForSelection()

        return zip(base, contents.lineFragments).compactMap { line, lineFragment in
            guard let offset = offsets[ObjectIdentifier(lineFragment.attributedString)] else {
                return nil
            }

            return SelectionLineSnapshot(
                base: line,
                lineFragment: lineFragment,
                offset: offset,
                origin: origin
            )
        }
    }
}

struct SelectionLayoutSnapshotKey: Hashable, @unchecked Sendable {
    let text: String
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int

    init?(text: String, frame: CGRect) {
        self.text = text
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

    init(
        base: SwiftUI.Text.Layout.Line,
        lineFragment: NSTextLineFragment?,
        offset: Int,
        origin: CGPoint
    ) {
        self.rect = base.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)

        var allSlices = [SelectionSliceSnapshot]()
        for run in base {
            let layoutDir = run.layoutDirection
            let renderedSlices = zip(run, run.selectionCharacterRanges).map { slice, characterRange in
                SelectionSliceSnapshot(
                    rect: slice.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y),
                    characterRange: characterRange.offsetBySelection(by: offset),
                    layoutDirection: layoutDir
                )
            }
            if !renderedSlices.isEmpty {
                allSlices.append(contentsOf: renderedSlices)
            } else if let fallbackRange = run.selectionCharacterRange, !fallbackRange.isEmpty {
                allSlices.append(SelectionSliceSnapshot(
                    rect: run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y),
                    characterRange: fallbackRange.offsetBySelection(by: offset),
                    layoutDirection: layoutDir
                ))
            }
        }

        if !allSlices.isEmpty {
            self.slices = allSlices
        } else {
            let fallbackLength = lineFragment?.attributedString.length ?? 0
            if fallbackLength > 0 {
                self.slices = [
                    SelectionSliceSnapshot(
                        rect: rect,
                        characterRange: offset..<(offset + fallbackLength),
                        layoutDirection: .leftToRight
                    )
                ]
            } else {
                self.slices = []
            }
        }
    }

    init(rect: CGRect, slices: [SelectionSliceSnapshot]) {
        self.rect = rect
        self.slices = slices
    }
}

struct SelectionSliceSnapshot: @unchecked Sendable {
    let rect: CGRect
    let characterRange: Range<Int>
    let layoutDirection: LayoutDirection
}

private struct SelectionLayoutContents {
    let lineFragments: [NSTextLineFragment]
    let layoutAttributedStrings: [NSAttributedString]
    let attributedStrings: [NSAttributedString]
}

private extension SwiftUI.Text.Layout {
    func materializeSelectionContents() -> SelectionLayoutContents {
        let lineFragments = compactMap(\.selectionLineFragment)
        let layoutAttributedStrings = lineFragments
            .map(\.attributedString)
            .removingSelectionIdenticalDuplicates()

        return .init(
            lineFragments: lineFragments,
            layoutAttributedStrings: layoutAttributedStrings,
            attributedStrings: layoutAttributedStrings
        )
    }
}

private extension SwiftUI.Text.Layout.Line {
    var selectionLineFragment: NSTextLineFragment? {
        let mirror = Mirror(reflecting: self)
        if let fragment = mirror.descendant("_line", "nsLine", 0) as? NSTextLineFragment {
            return fragment
        }

        return mirror.descendant("_line", "nsLine") as? NSTextLineFragment
    }
}

private extension SwiftUI.Text.Layout.Run {
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

    private var selectionCTRun: CTRun? {
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
