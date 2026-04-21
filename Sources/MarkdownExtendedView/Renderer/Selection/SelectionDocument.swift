// SelectionDocument.swift
//  MarkdownExtendedView
//
//  Created by OpenAI Codex on 2026-04-21.
// Licensed under MIT License

import Foundation
import SwiftUI

struct SelectionSection {
    let range: Range<Int>
    let frame: CGRect
}

struct SelectionLine {
    let rect: CGRect
    let sliceRange: Range<Int>
}

struct SelectionSlice {
    let range: Range<Int>
    let rect: CGRect
    let lineIndex: Int
    let layoutDirection: LayoutDirection
}

struct SelectionDocument {
    @MainActor
    static let empty = SelectionDocument(
        attributedString: NSAttributedString(),
        sections: [],
        lines: [],
        slices: []
    )

    let attributedString: NSAttributedString
    let sections: [SelectionSection]
    let lines: [SelectionLine]
    let slices: [SelectionSlice]
    let hitRects: [CGRect]

    init(
        attributedString: NSAttributedString,
        sections: [SelectionSection],
        lines: [SelectionLine],
        slices: [SelectionSlice]
    ) {
        self.attributedString = attributedString
        self.sections = sections
        self.lines = lines
        self.slices = slices
        self.hitRects = lines.compactMap { line in
            guard line.rect.width > 0, line.rect.height > 0 else {
                return nil
            }

            return line.rect.insetBy(dx: -8, dy: -4)
        }
    }

    var textLength: Int {
        attributedString.length
    }

    var startPosition: SelectionPosition {
        SelectionPosition(
            offset: 0,
            affinity: textLength == 0 ? .upstream : .downstream
        )
    }

    var endPosition: SelectionPosition {
        SelectionPosition(offset: textLength, affinity: .upstream)
    }

    func plainText(in range: SelectionRange) -> String {
        let characterRange = selectedCharacterRange(for: range)
        guard characterRange.lowerBound < characterRange.upperBound else {
            return ""
        }

        var text = ""
        var previousSection: SelectionSection?

        for section in sections {
            let lowerBound = max(characterRange.lowerBound, section.range.lowerBound)
            let upperBound = min(characterRange.upperBound, section.range.upperBound)
            guard lowerBound < upperBound else {
                continue
            }

            let substring = attributedString.attributedSubstring(
                from: NSRange(lowerBound..<upperBound)
            ).string
            guard !substring.isEmpty else {
                continue
            }

            if
                let previousSection,
                shouldInsertLineBreak(
                    between: previousSection,
                    and: section,
                    existingText: text,
                    upcomingText: substring
                )
            {
                text += "\n"
            }

            text += substring
            previousSection = section
        }

        return text
    }

    func attributedText(in range: SelectionRange) -> NSAttributedString {
        let characterRange = selectedCharacterRange(for: range)
        guard characterRange.lowerBound < characterRange.upperBound else {
            return NSAttributedString()
        }

        return attributedString.attributedSubstring(from: NSRange(characterRange))
    }

    func closestPosition(to point: CGPoint) -> SelectionPosition? {
        guard let slice = closestSlice(to: point) else {
            return nil
        }

        let leadingDistance = abs(point.x - slice.rect.leadingEdgeX(for: slice.layoutDirection))
        let trailingDistance = abs(point.x - slice.rect.trailingEdgeX(for: slice.layoutDirection))

        if leadingDistance <= trailingDistance {
            return SelectionPosition(offset: slice.range.lowerBound, affinity: .downstream)
        }

        return SelectionPosition(offset: slice.range.upperBound, affinity: .upstream)
    }

    func characterRange(at point: CGPoint) -> SelectionRange? {
        guard let slice = closestSlice(to: point) else {
            return nil
        }

        return SelectionRange(
            start: SelectionPosition(offset: slice.range.lowerBound, affinity: .downstream),
            end: SelectionPosition(offset: slice.range.upperBound, affinity: .upstream)
        )
    }

    func position(from position: SelectionPosition, offset: Int) -> SelectionPosition? {
        let target = position.offset + offset
        guard (0...textLength).contains(target) else {
            return nil
        }

        return resolvedPosition(at: target)
    }

    func firstRect(for range: SelectionRange) -> CGRect {
        guard !range.isCollapsed else {
            return caretRect(for: range.start)
        }

        let characterRange = selectedCharacterRange(for: range)
        guard
            let firstSliceIndex = firstSelectedSliceIndex(in: characterRange),
            lines.indices.contains(slices[firstSliceIndex].lineIndex)
        else {
            return .zero
        }

        let firstLineIndex = slices[firstSliceIndex].lineIndex
        var rect = CGRect.null

        for slice in slices[firstSliceIndex...] {
            guard slice.lineIndex == firstLineIndex else {
                break
            }

            if slice.range.intersects(characterRange) {
                rect = rect.union(slice.rect)
            }
        }

        return rect.isNull ? .zero : rect
    }

    func caretRect(for position: SelectionPosition) -> CGRect {
        guard let slice = boundarySlice(for: position) else {
            return .zero
        }

        guard lines.indices.contains(slice.lineIndex) else {
            return .zero
        }

        let lineRect = lines[slice.lineIndex].rect
        let x: CGFloat

        switch position.affinity {
        case .downstream:
            x = slice.rect.leadingEdgeX(for: slice.layoutDirection)
        case .upstream:
            x = slice.rect.trailingEdgeX(for: slice.layoutDirection)
        }

        return CGRect(x: x, y: lineRect.minY, width: 1, height: lineRect.height)
    }

    func selectionRects(for range: SelectionRange) -> [SelectionRect] {
        guard !range.isCollapsed else {
            return []
        }

        let characterRange = selectedCharacterRange(for: range)
        let selectedSlices = slices.filter { $0.range.intersects(characterRange) }
        guard !selectedSlices.isEmpty else {
            return []
        }

        let startLineIndex = boundarySlice(for: range.start)?.lineIndex
        let endLineIndex = boundarySlice(for: range.end)?.lineIndex

        var builder = SelectionRectBuilder(
            startLineIndex: startLineIndex,
            endLineIndex: endLineIndex,
            startX: caretRect(for: range.start).minX,
            endX: caretRect(for: range.end).minX
        )

        for slice in selectedSlices {
            builder.appendRect(
                slice.rect,
                layoutDirection: slice.layoutDirection,
                lineIndex: slice.lineIndex
            )
        }

        var rects = builder.rects()
        guard !rects.isEmpty else {
            return []
        }

        rects[0].containsStart = true
        rects[rects.count - 1].containsEnd = true
        return rects
    }

    private func selectedCharacterRange(for range: SelectionRange) -> Range<Int> {
        let lowerBound = min(range.start.offset, range.end.offset)
        let upperBound = max(range.start.offset, range.end.offset)
        return lowerBound..<upperBound
    }

    private func resolvedPosition(at offset: Int) -> SelectionPosition {
        let clampedOffset = min(max(offset, 0), textLength)

        if clampedOffset == 0 {
            return SelectionPosition(offset: 0, affinity: .downstream)
        }

        if clampedOffset == textLength {
            return SelectionPosition(offset: clampedOffset, affinity: .upstream)
        }

        if let slice = slices.last(where: { $0.range.upperBound == clampedOffset }) {
            return SelectionPosition(offset: slice.range.upperBound, affinity: .upstream)
        }

        if let slice = slices.first(where: { $0.range.lowerBound == clampedOffset }) {
            return SelectionPosition(offset: slice.range.lowerBound, affinity: .downstream)
        }

        if let slice = slices.first(where: { $0.range.contains(clampedOffset) }) {
            return SelectionPosition(offset: slice.range.upperBound, affinity: .upstream)
        }

        if let nextSlice = slices.first(where: { $0.range.lowerBound > clampedOffset }) {
            return SelectionPosition(offset: nextSlice.range.lowerBound, affinity: .downstream)
        }

        if let previousSlice = slices.last(where: { $0.range.upperBound < clampedOffset }) {
            return SelectionPosition(offset: previousSlice.range.upperBound, affinity: .upstream)
        }

        return endPosition
    }

    private func firstSelectedSliceIndex(in range: Range<Int>) -> Int? {
        slices.firstIndex { $0.range.intersects(range) }
    }

    private func closestSlice(to point: CGPoint) -> SelectionSlice? {
        slices.min {
            $0.rect.distanceSquared(to: point) < $1.rect.distanceSquared(to: point)
        }
    }

    private func boundarySlice(for position: SelectionPosition) -> SelectionSlice? {
        guard !slices.isEmpty else {
            return nil
        }

        switch position.affinity {
        case .downstream:
            if let startingSlice = slices.first(where: { $0.range.lowerBound == position.offset }) {
                return startingSlice
            }

            if let containingSlice = slices.first(where: { $0.range.contains(position.offset) }) {
                return containingSlice
            }

            if let nextSlice = slices.first(where: { $0.range.lowerBound > position.offset }) {
                return nextSlice
            }

            return slices.last

        case .upstream:
            if let endingSlice = slices.last(where: { $0.range.upperBound == position.offset }) {
                return endingSlice
            }

            if let containingSlice = slices.first(where: { $0.range.contains(position.offset) }) {
                return containingSlice
            }

            if let previousSlice = slices.last(where: { $0.range.upperBound < position.offset }) {
                return previousSlice
            }

            return slices.first
        }
    }

    private func shouldInsertLineBreak(
        between previousSection: SelectionSection,
        and currentSection: SelectionSection,
        existingText: String,
        upcomingText: String
    ) -> Bool {
        guard
            let lastCharacter = existingText.last,
            let nextCharacter = upcomingText.first,
            !lastCharacter.isNewline,
            !nextCharacter.isNewline
        else {
            return false
        }

        return currentSection.frame.minY - previousSection.frame.maxY > 1
    }
}

private struct SelectionRectBuilder {
    let startLineIndex: Int?
    let endLineIndex: Int?
    let startX: CGFloat
    let endX: CGFloat

    private var lines: [[SelectionRect]] = []
    private var currentLineIndex: Int?
    private var currentLineRects: [SelectionRect] = []

    init(
        startLineIndex: Int?,
        endLineIndex: Int?,
        startX: CGFloat,
        endX: CGFloat
    ) {
        self.startLineIndex = startLineIndex
        self.endLineIndex = endLineIndex
        self.startX = startX
        self.endX = endX
    }

    mutating func appendRect(_ rect: CGRect, layoutDirection: LayoutDirection, lineIndex: Int) {
        if currentLineIndex != lineIndex {
            appendCurrentLine()
            currentLineIndex = lineIndex
        }

        if let last = currentLineRects.indices.last,
           currentLineRects[last].layoutDirection == layoutDirection {
            currentLineRects[last].rect = currentLineRects[last].rect.union(rect)
        } else {
            currentLineRects.append(.init(rect: rect, layoutDirection: layoutDirection))
        }
    }

    mutating func rects() -> [SelectionRect] {
        appendCurrentLine()
        guard !lines.isEmpty else {
            return []
        }

        return lines.flatMap(\.self)
    }

    private mutating func appendCurrentLine() {
        guard let activeLineIndex = currentLineIndex, !currentLineRects.isEmpty else {
            currentLineIndex = nil
            currentLineRects.removeAll(keepingCapacity: true)
            return
        }

        if startLineIndex == activeLineIndex {
            let span = currentLineRects.selectionIndex(containing: startX) ?? currentLineRects.startIndex
            currentLineRects[span].trimSelectionLeading(to: startX)
        }

        if endLineIndex == activeLineIndex {
            let span =
                currentLineRects.selectionIndex(containing: endX)
                ?? currentLineRects.index(before: currentLineRects.endIndex)
            currentLineRects[span].trimSelectionTrailing(to: endX)
        }

        lines.append(currentLineRects)
        currentLineIndex = nil
        currentLineRects.removeAll(keepingCapacity: true)
    }
}

private extension Range where Bound == Int {
    func intersects(_ other: Range<Int>) -> Bool {
        lowerBound < other.upperBound && other.lowerBound < upperBound
    }
}

private extension Array where Element == SelectionRect {
    func selectionIndex(containing caretX: CGFloat) -> Int? {
        firstIndex { ($0.rect.minX...$0.rect.maxX).contains(caretX) }
    }
}

private extension SelectionRect {
    mutating func trimSelectionLeading(to caretX: CGFloat) {
        if layoutDirection == .leftToRight {
            let minX = max(rect.minX, caretX)
            rect.size.width = max(0, rect.maxX - minX)
            rect.origin.x = minX
        } else {
            let maxX = max(rect.minX, caretX)
            rect.size.width = max(0, maxX - rect.minX)
        }
    }

    mutating func trimSelectionTrailing(to caretX: CGFloat) {
        if layoutDirection == .leftToRight {
            let maxX = max(rect.minX, caretX)
            rect.size.width = max(0, maxX - rect.minX)
        } else {
            let minX = min(rect.maxX, caretX)
            rect.size.width = max(0, rect.maxX - minX)
            rect.origin.x = minX
        }
    }
}

private extension CGRect {
    func leadingEdgeX(for layoutDirection: LayoutDirection) -> CGFloat {
        layoutDirection == .leftToRight ? minX : maxX
    }

    func trailingEdgeX(for layoutDirection: LayoutDirection) -> CGFloat {
        layoutDirection == .leftToRight ? maxX : minX
    }

    func verticalDistance(to y: CGFloat) -> CGFloat {
        if y < minY { return minY - y }
        if y > maxY { return y - maxY }
        return 0
    }

    func horizontalDistance(to x: CGFloat) -> CGFloat {
        if x < minX { return minX - x }
        if x > maxX { return x - maxX }
        return 0
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = horizontalDistance(to: point.x)
        let dy = verticalDistance(to: point.y)
        return dx * dx + dy * dy
    }
}
