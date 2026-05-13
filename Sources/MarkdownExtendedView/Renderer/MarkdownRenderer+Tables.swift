//
//  MarkdownRenderer+Tables.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

// MARK: - Table Rendering

struct RenderTable: View {
    let table: Markdown.Table
    let context: MarkdownContext

    var body: some View {
        let cellArrays = extractTableCells(from: table)
        let alignments = table.columnAlignments
        
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            if !cellArrays.header.isEmpty {
                GridRow {
                    RenderGridCells(cells: cellArrays.header, isHeader: true, alignments: alignments, context: context)
                }
                // Horizontal line below header
                if !cellArrays.body.isEmpty {
                    RenderHorizontalLine(rowCells: cellArrays.body[0], alignments: alignments)
                } else {
                    RenderSolidHorizontalLine(alignments: alignments)
                }
            }

            // Body rows
            ForEach(Array(cellArrays.body.enumerated()), id: \.offset) { rowIndex, rowCells in
                GridRow {
                    RenderGridCells(cells: rowCells, isHeader: false, alignments: alignments, context: context)
                }
                // Horizontal line between rows
                if rowIndex < cellArrays.body.count - 1 {
                    RenderHorizontalLine(rowCells: cellArrays.body[rowIndex + 1], alignments: alignments)
                }
            }
        }
        .padding(.vertical, 8)
        .selectionTextPassThrough()
    }
}

fileprivate struct RenderSolidHorizontalLine: View {
    let alignments: [Markdown.Table.ColumnAlignment?]

    var body: some View {
        let totalCols = alignments.count
        GridRow {
            Color.primary.opacity(0.15).frame(height: 0.5)
                .gridCellUnsizedAxes([.horizontal])
                .gridCellColumns(max(1, totalCols * 2 - 1))
        }
    }
}

fileprivate struct RenderHorizontalLine: View {
    let rowCells: [GridCell]
    let alignments: [Markdown.Table.ColumnAlignment?]

    var body: some View {
        GridRow {
            // We can't mutate variables in a @ViewBuilder natively, so we must compute the segments first.
            let segments = computeHorizontalSegments(rowCells: rowCells, totalCols: alignments.count)
            ForEach(segments) { segment in
                if segment.isClear {
                    Color.clear.frame(height: 0.5)
                        .gridCellUnsizedAxes([.horizontal])
                        .gridCellColumns(segment.gridSpan)
                } else {
                    Color.primary.opacity(0.15).frame(height: 0.5)
                        .gridCellUnsizedAxes([.horizontal])
                        .gridCellColumns(segment.gridSpan)
                }
            }
        }
    }
}

fileprivate struct HorizontalSegment: Identifiable {
    let id = UUID()
    let isClear: Bool
    let gridSpan: Int
}

fileprivate func computeHorizontalSegments(rowCells: [GridCell], totalCols: Int) -> [HorizontalSegment] {
    var segments: [HorizontalSegment] = []
    var currentVisualCol = 0
    
    for gridCell in rowCells {
        let colIdx = gridCell.visualColumn
        let displayColspan = max(1, Int(gridCell.node.colspan))
        
        if currentVisualCol < colIdx {
            let missingCols = colIdx - currentVisualCol
            segments.append(HorizontalSegment(isClear: false, gridSpan: missingCols * 2))
        }
        
        segments.append(HorizontalSegment(isClear: gridCell.node.rowspan == 0, gridSpan: displayColspan * 2 - 1))
        
        if colIdx + displayColspan < totalCols {
            segments.append(HorizontalSegment(isClear: false, gridSpan: 1)) // Intersection
        }
        
        currentVisualCol = colIdx + displayColspan
    }
    
    if currentVisualCol < totalCols {
        let missingCols = totalCols - currentVisualCol
        if currentVisualCol == 0 {
            segments.append(HorizontalSegment(isClear: false, gridSpan: totalCols * 2 - 1))
        } else {
            segments.append(HorizontalSegment(isClear: false, gridSpan: missingCols * 2 - 1))
        }
    }
    
    return segments
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

/// Extracts cells from a table into arrays for easier SwiftUI rendering.
fileprivate func extractTableCells(from table: Markdown.Table) -> (header: [GridCell], body: [[GridCell]]) {
    let header = extractGridCells(from: Array(table.head.cells))
    let body = Array(table.body.rows.map { extractGridCells(from: Array($0.cells)) })
    return (header, body)
}

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

fileprivate struct RenderGridCells: View {
    let cells: [GridCell]
    let isHeader: Bool
    let alignments: [Markdown.Table.ColumnAlignment?]
    let context: MarkdownContext

    var body: some View {
        ForEach(Array(cells.enumerated()), id: \.offset) { index, gridCell in
            let cell = gridCell.node
            let colIdx = gridCell.visualColumn
            let colAlignment = colIdx < alignments.count ? alignments[colIdx] : nil
            
            let frameAlign: Alignment = textAlignment(for: colAlignment)
            let multilineAlign: TextAlignment = swiftUITextAlignment(for: colAlignment)
            let hAlign: HorizontalAlignment = horizontalAlignment(for: colAlignment)
            
            let displayColspan = max(1, cell.colspan)
            let finalColspan = displayColspan * 2 - 1

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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxHeight: .infinity, alignment: frameAlign)
                .gridColumnAlignment(hAlign)
                .gridCellColumns(Int(finalColspan))
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .gridCellColumns(Int(finalColspan))
            }
            
            // Render vertical line if not the last visual column
            if colIdx + Int(displayColspan) < alignments.count {
                Color.primary.opacity(0.15).frame(width: 0.5)
                    .gridCellUnsizedAxes([.vertical])
            }
        }
    }
}
