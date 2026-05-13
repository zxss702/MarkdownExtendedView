//
//  FlowLayout.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Flow Layout Definitions

struct FlowLineBreakLayoutValueKey: LayoutValueKey {
    static let defaultValue = false
}

struct InlineTextStyle: OptionSet {
    let rawValue: Int

    static let bold = InlineTextStyle(rawValue: 1 << 0)
    static let italic = InlineTextStyle(rawValue: 1 << 1)
    static let strikethrough = InlineTextStyle(rawValue: 1 << 2)
    static let code = InlineTextStyle(rawValue: 1 << 3)
}

enum InlineFlowElement {
    case text(String, InlineTextStyle)
    case link(Markdown.Link)
    case codeReference(MCodeReference)
    case image(Markdown.Image)
    case latex(String, Bool)
    case lineBreak
}

// MARK: - Flow Layout

/// A simple flow layout for mixed text and views.
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var minimumLineHeight: CGFloat = 0

    struct CacheData {
        var size: CGSize
        var positions: [CGPoint]
        var measured: [MeasuredSubview]
        var proposal: ProposedViewSize?
    }

    func makeCache(subviews: Subviews) -> CacheData? {
        return nil
    }

    struct MeasuredSubview {
        let size: CGSize
        let baseline: CGFloat
        let proposal: ProposedViewSize
        let isForcedBreak: Bool
    }

    private struct Line {
        let indices: [Int]
        let width: CGFloat
        let maxAscent: CGFloat
        let maxDescent: CGFloat

        var height: CGFloat {
            maxAscent + maxDescent
        }

        func resolvedHeight(minimumLineHeight: CGFloat) -> CGFloat {
            max(height, minimumLineHeight)
        }

        func verticalInset(minimumLineHeight: CGFloat) -> CGFloat {
            max(0, resolvedHeight(minimumLineHeight: minimumLineHeight) - height) / 2
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) -> CGSize {
        if let cached = cache, cached.proposal == proposal {
            return cached.size
        }
        let result = computeLayout(proposal: proposal, subviews: subviews)
        cache = CacheData(size: result.size, positions: result.positions, measured: result.measured, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData?) {
        let result: (size: CGSize, positions: [CGPoint], measured: [MeasuredSubview])
        if let cached = cache, cached.proposal == proposal {
            result = (cached.size, cached.positions, cached.measured)
        } else {
            result = computeLayout(proposal: proposal, subviews: subviews)
            cache = CacheData(size: result.size, positions: result.positions, measured: result.measured, proposal: proposal)
        }

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                let measured = result.measured[index]
                subview.place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                    proposal: measured.proposal
                )
            }
        }
    }

    private func computeLayout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint], measured: [MeasuredSubview]) {
        guard !subviews.isEmpty else {
            return (.zero, [], [])
        }

        let maxWidth = max(proposal.width ?? .infinity, 1)
        let measured = subviews.map {
            measuredSubview(for: $0, maxWidth: maxWidth)
        }

        let lines = computeLines(measured: measured, maxWidth: maxWidth)
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0

        for line in lines {
            var currentX: CGFloat = 0
            let lineTopInset = line.verticalInset(minimumLineHeight: minimumLineHeight)

            for index in line.indices {
                let item = measured[index]
                let y = currentY + lineTopInset + (line.maxAscent - item.baseline)
                positions[index] = CGPoint(x: currentX, y: y)
                currentX += item.size.width + spacing
            }

            totalWidth = max(totalWidth, line.width)
            currentY += line.resolvedHeight(minimumLineHeight: minimumLineHeight) + lineSpacing
        }

        let totalHeight = max(0, currentY - lineSpacing)
        return (CGSize(width: totalWidth, height: totalHeight), positions, measured)
    }

    private func computeLines(measured: [MeasuredSubview], maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var currentIndices: [Int] = []
        var currentWidth: CGFloat = 0
        var currentAscent: CGFloat = 0
        var currentDescent: CGFloat = 0

        func flushCurrentLine() {
            guard !currentIndices.isEmpty else { return }
            lines.append(
                Line(
                    indices: currentIndices,
                    width: currentWidth,
                    maxAscent: currentAscent,
                    maxDescent: currentDescent
                )
            )
            currentIndices.removeAll(keepingCapacity: true)
            currentWidth = 0
            currentAscent = 0
            currentDescent = 0
        }

        for (index, item) in measured.enumerated() {
            if item.isForcedBreak {
                currentIndices.append(index)
                if currentIndices.count > 1 {
                    currentWidth += spacing
                }
                currentWidth += item.size.width
                currentAscent = max(currentAscent, item.baseline)
                currentDescent = max(currentDescent, item.size.height - item.baseline)
                flushCurrentLine()
                continue
            }

            if !currentIndices.isEmpty, currentWidth + spacing + item.size.width > maxWidth {
                flushCurrentLine()
            }

            currentIndices.append(index)
            if currentIndices.count > 1 {
                currentWidth += spacing
            }
            currentWidth += item.size.width
            currentAscent = max(currentAscent, item.baseline)
            currentDescent = max(currentDescent, item.size.height - item.baseline)
        }

        flushCurrentLine()
        return lines
    }

    private func measuredSubview(for subview: LayoutSubview, maxWidth: CGFloat) -> MeasuredSubview {
        let isBlockFormula = subview[BlockFormulaKey.self]
        let unspecifiedProposal = ProposedViewSize(width: nil, height: nil)
        let unspecifiedSize = subview.sizeThatFits(unspecifiedProposal)

        let measurementProposal: ProposedViewSize
        let size: CGSize
        if isBlockFormula {
            measurementProposal = ProposedViewSize(width: maxWidth, height: nil)
            size = CGSize(width: maxWidth, height: subview.sizeThatFits(measurementProposal).height)
        } else if maxWidth.isFinite, unspecifiedSize.width > maxWidth {
            measurementProposal = ProposedViewSize(width: maxWidth, height: nil)
            size = subview.sizeThatFits(measurementProposal)
        } else {
            measurementProposal = unspecifiedProposal
            size = unspecifiedSize
        }

        let dimensions = subview.dimensions(in: measurementProposal)
        return MeasuredSubview(
            size: size,
            baseline: resolvedBaseline(from: dimensions, size: size),
            proposal: measurementProposal,
            isForcedBreak: subview[FlowLineBreakLayoutValueKey.self]
        )
    }

    private func resolvedBaseline(from dimensions: ViewDimensions, size: CGSize) -> CGFloat {
        let first = dimensions[.firstTextBaseline]
        if first.isFinite, first > 0, first <= size.height {
            return first
        }

        let last = dimensions[.lastTextBaseline]
        if last.isFinite, last > 0, last <= size.height {
            return last
        }

        // For non-text views, use vertical center as a neutral fallback.
        return size.height / 2
    }
}
