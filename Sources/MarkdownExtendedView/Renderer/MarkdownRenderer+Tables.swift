//
//  MarkdownRenderer+Tables.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Layout Keys

enum TableBorderRole: Equatable {
    case none
    case horizontal(row: Int)
}

struct TableBorderRoleKey: LayoutValueKey {
    static let defaultValue: TableBorderRole = .none
}

struct TableRowKey: LayoutValueKey {
    static let defaultValue: Int = 0
}

struct TableColumnKey: LayoutValueKey {
    static let defaultValue: Int = 0
}

struct TableColspanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

struct TableRowspanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

// MARK: - Custom Layout

struct MarkdownTableLayout: Layout {
    let columnAlignments: [Markdown.Table.ColumnAlignment?]
    let horizontalSpacing: CGFloat = 0
    let verticalSpacing: CGFloat = 0

    struct Cache {
        var columnWidths: [CGFloat] = []
        var rowHeights: [CGFloat] = []
        var size: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        computeLayout(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let finalWidths = cache.columnWidths
        let rowHeights = cache.rowHeights
        
        var xOffsets = [CGFloat](repeating: 0, count: finalWidths.count + 1)
        for i in 0..<finalWidths.count { xOffsets[i+1] = xOffsets[i] + finalWidths[i] }
        
        var yOffsets = [CGFloat](repeating: 0, count: rowHeights.count + 1)
        for i in 0..<rowHeights.count { yOffsets[i+1] = yOffsets[i] + rowHeights[i] }
        
        for subview in subviews {
            let role = subview[TableBorderRoleKey.self]
            switch role {
            case .none:
                let row = subview[TableRowKey.self]
                let col = subview[TableColumnKey.self]
                let colspan = subview[TableColspanKey.self]
                let rowspan = subview[TableRowspanKey.self]
                
                guard row < rowHeights.count && col < finalWidths.count else { continue }
                
                let actualColspan = min(colspan, finalWidths.count - col)
                let actualRowspan = min(rowspan, rowHeights.count - row)
                
                let x = bounds.minX + xOffsets[col]
                let y = bounds.minY + yOffsets[row]
                let width = finalWidths[col..<col+actualColspan].reduce(0, +)
                let height = rowHeights[row..<row+actualRowspan].reduce(0, +)
                
                subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: .init(width: width, height: height)
                )
                
            case .horizontal(let row):
                guard row + 1 < yOffsets.count else { continue }
                let y = bounds.minY + yOffsets[row + 1]
                subview.place(
                    at: CGPoint(x: bounds.minX, y: y),
                    anchor: .leading,
                    proposal: .init(width: cache.size.width, height: 0.5)
                )
            }
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var maxRow = -1
        var maxCol = -1
        
        for subview in subviews {
            if subview[TableBorderRoleKey.self] == .none {
                let row = subview[TableRowKey.self]
                let col = subview[TableColumnKey.self]
                let colspan = subview[TableColspanKey.self]
                let rowspan = subview[TableRowspanKey.self]
                maxRow = max(maxRow, row + rowspan - 1)
                maxCol = max(maxCol, col + colspan - 1)
            }
        }
        
        if maxRow < 0 || maxCol < 0 {
            cache.size = .zero
            return
        }
        
        let numCols = maxCol + 1
        let numRows = maxRow + 1
        
        var minWidths = Array(repeating: CGFloat(0), count: numCols)
        var idealWidths = Array(repeating: CGFloat(0), count: numCols)
        
        // 1. Calculate min and ideal widths from colspan=1 cells
        for subview in subviews where subview[TableBorderRoleKey.self] == .none && subview[TableColspanKey.self] == 1 {
            let col = subview[TableColumnKey.self]
            guard col < numCols else { continue }
            let minW = subview.sizeThatFits(.init(width: 0, height: nil)).width
            let idealW = subview.sizeThatFits(.unspecified).width
            minWidths[col] = max(minWidths[col], minW)
            idealWidths[col] = max(idealWidths[col], idealW)
        }
        
        // 2. Adjust for colspan > 1 cells
        for subview in subviews where subview[TableBorderRoleKey.self] == .none && subview[TableColspanKey.self] > 1 {
            let col = subview[TableColumnKey.self]
            let colspan = min(subview[TableColspanKey.self], numCols - col)
            guard colspan > 1 && col < numCols else { continue }
            
            let minW = subview.sizeThatFits(.init(width: 0, height: nil)).width
            let idealW = subview.sizeThatFits(.unspecified).width
            
            let currentMinSum = minWidths[col..<col+colspan].reduce(0, +)
            if currentMinSum < minW {
                let deficit = minW - currentMinSum
                for i in col..<col+colspan { minWidths[i] += deficit / CGFloat(colspan) }
            }
            
            let currentIdealSum = idealWidths[col..<col+colspan].reduce(0, +)
            if currentIdealSum < idealW {
                let deficit = idealW - currentIdealSum
                for i in col..<col+colspan { idealWidths[i] += deficit / CGFloat(colspan) }
            }
        }
        
        // 3. Distribute widths
        let availableWidth = proposal.width ?? idealWidths.reduce(0, +)
        let totalMin = minWidths.reduce(0, +)
        let totalIdeal = idealWidths.reduce(0, +)
        
        var finalWidths = Array(repeating: CGFloat(0), count: numCols)
        
        if availableWidth >= totalIdeal {
            finalWidths = idealWidths
        } else if availableWidth <= totalMin {
            finalWidths = minWidths
        } else {
            let extraWidth = max(0, availableWidth - totalMin)
            let totalFlex = max(1, totalIdeal - totalMin) // Prevent division by zero
            for i in 0..<numCols {
                let flex = idealWidths[i] - minWidths[i]
                finalWidths[i] = minWidths[i] + extraWidth * (flex / totalFlex)
            }
        }
        
        // 4. Calculate row heights
        var rowHeights = Array(repeating: CGFloat(0), count: numRows)
        
        // First pass: rowspan = 1
        for subview in subviews where subview[TableBorderRoleKey.self] == .none && subview[TableRowspanKey.self] == 1 {
            let row = subview[TableRowKey.self]
            let col = subview[TableColumnKey.self]
            let colspan = min(subview[TableColspanKey.self], numCols - col)
            guard row < numRows && col < numCols else { continue }
            let width = finalWidths[col..<col+colspan].reduce(0, +)
            let height = subview.sizeThatFits(.init(width: width, height: nil)).height
            rowHeights[row] = max(rowHeights[row], height)
        }
        
        // Second pass: rowspan > 1
        for subview in subviews where subview[TableBorderRoleKey.self] == .none && subview[TableRowspanKey.self] > 1 {
            let row = subview[TableRowKey.self]
            let col = subview[TableColumnKey.self]
            let colspan = min(subview[TableColspanKey.self], numCols - col)
            let rowspan = min(subview[TableRowspanKey.self], numRows - row)
            guard rowspan > 1 && row < numRows && col < numCols else { continue }
            
            let width = finalWidths[col..<col+colspan].reduce(0, +)
            let height = subview.sizeThatFits(.init(width: width, height: nil)).height
            
            let currentHeightSum = rowHeights[row..<row+rowspan].reduce(0, +)
            if currentHeightSum < height {
                let deficit = height - currentHeightSum
                for i in row..<row+rowspan { rowHeights[i] += deficit / CGFloat(rowspan) }
            }
        }
        
        cache.columnWidths = finalWidths
        cache.rowHeights = rowHeights
        cache.size = CGSize(width: finalWidths.reduce(0, +), height: rowHeights.reduce(0, +))
    }
}

// MARK: - Table Rendering

struct RenderTable: View {
    let table: Markdown.Table
    let context: MarkdownContext

    var body: some View {
        let cellArrays = extractTableCells(from: table)
        let alignments = table.columnAlignments
        
        var maxCol = 0
        if !cellArrays.header.isEmpty {
            maxCol = max(maxCol, cellArrays.header.last?.visualColumn ?? 0)
        }
        for row in cellArrays.body {
            maxCol = max(maxCol, row.last?.visualColumn ?? 0)
        }
        let numCols = maxCol + 1
        let numRows = (cellArrays.header.isEmpty ? 0 : 1) + cellArrays.body.count

        return MarkdownTableLayout(columnAlignments: alignments) {
            // Header
            if !cellArrays.header.isEmpty {
                ForEach(Array(cellArrays.header.enumerated()), id: \.offset) { _, gridCell in
                    RenderTableCell(
                        gridCell: gridCell,
                        isHeader: true,
                        row: 0,
                        alignments: alignments,
                        numRows: numRows,
                        numCols: numCols,
                        context: context
                    )
                }
                Color.primary.opacity(0.15)
                    .frame(height: 0.5)
                    .layoutValue(key: TableBorderRoleKey.self, value: .horizontal(row: 0))
            }
            
            // Body
            let rowOffset = cellArrays.header.isEmpty ? 0 : 1
            ForEach(Array(cellArrays.body.enumerated()), id: \.offset) { rowIndex, rowCells in
                ForEach(Array(rowCells.enumerated()), id: \.offset) { _, gridCell in
                    RenderTableCell(
                        gridCell: gridCell,
                        isHeader: false,
                        row: rowIndex + rowOffset,
                        alignments: alignments,
                        numRows: numRows,
                        numCols: numCols,
                        context: context
                    )
                }
                if rowIndex + rowOffset < numRows - 1 {
                    Color.primary.opacity(0.15)
                        .frame(height: 0.5)
                        .layoutValue(key: TableBorderRoleKey.self, value: .horizontal(row: rowIndex + rowOffset))
                }
            }
        }
        .padding(.vertical, 8)
        .selectionTextPassThrough()
    }
}

// MARK: - Table Cell Rendering

fileprivate func horizontalAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> HorizontalAlignment {
    switch alignment {
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    case .none, .some: return .leading
    }
}

fileprivate func textAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> Alignment {
    switch alignment {
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    case .none, .some: return .leading
    }
}

fileprivate func swiftUITextAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> TextAlignment {
    switch alignment {
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    case .none, .some: return .leading
    }
}

struct GridCell {
    let node: Markdown.Table.Cell
    let visualColumn: Int
}

fileprivate func extractGridCells(from cells: [Markdown.Table.Cell]) -> [GridCell] {
    var result = [GridCell]()
    var skipCount = 0
    var currentVisualColumn = 0
    for cell in cells {
        if skipCount > 0 {
            skipCount -= 1
            currentVisualColumn += 1
            continue
        }
        result.append(GridCell(node: cell, visualColumn: currentVisualColumn))
        if cell.colspan > 1 {
            skipCount = Int(cell.colspan) - 1
        }
        currentVisualColumn += 1
    }
    return result
}

fileprivate func extractTableCells(from table: Markdown.Table) -> (header: [GridCell], body: [[GridCell]]) {
    let header = extractGridCells(from: Array(table.head.cells))
    let body = Array(table.body.rows.map { extractGridCells(from: Array($0.cells)) })
    return (header, body)
}

struct RenderTableCell: View {
    let gridCell: GridCell
    let isHeader: Bool
    let row: Int
    let alignments: [Markdown.Table.ColumnAlignment?]
    let numRows: Int
    let numCols: Int
    let context: MarkdownContext

    var body: some View {
        let cell = gridCell.node
        let col = gridCell.visualColumn
        let colspan = max(1, Int(cell.colspan))
        let rowspan = max(1, Int(cell.rowspan))
        
        let colAlignment = col < alignments.count ? alignments[col] : nil
        let frameAlign: Alignment = textAlignment(for: colAlignment)
        let multilineAlign: TextAlignment = swiftUITextAlignment(for: colAlignment)
        
        Group {
            if cell.rowspan > 0 {
                BuildInlineText(
                    parent: cell,
                    features: computeInlineFeatures(cell),
                    context: context
                )
                .font(context.theme.bodySwiftUIFont)
                .fontWeight(isHeader ? .semibold : nil)
                .foregroundColor(context.theme.textColor)
                .multilineTextAlignment(multilineAlign)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign)
            } else {
                Color.clear
            }
        }
        .layoutValue(key: TableRowKey.self, value: row)
        .layoutValue(key: TableColumnKey.self, value: col)
        .layoutValue(key: TableColspanKey.self, value: colspan)
        .layoutValue(key: TableRowspanKey.self, value: rowspan)
        .overlay(
            ZStack {
                // Vertical Trailing Border
                if col + colspan - 1 < numCols - 1 {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Color.primary.opacity(0.15).frame(width: 0.5)
                    }
                }
            }
        )
    }
}
