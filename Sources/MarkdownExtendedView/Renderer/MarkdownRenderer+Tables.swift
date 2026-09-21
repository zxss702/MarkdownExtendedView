//
//  MarkdownRenderer+Tables.swift
//  MarkdownExtendedView
//

import SwiftUI
import Markdown

fileprivate func textAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> Alignment {
    switch alignment {
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    case .none, .some: return .leading
    }
}

fileprivate func horizontalAlignment(for alignment: Markdown.Table.ColumnAlignment?) -> HorizontalAlignment {
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

// MARK: - Table Rendering

struct RenderTable: View {
    let table: MDTable

    var body: some View {
        let alignments = table.alignments
        let headerCells = table.head
        let rows = table.rows

        let numCols = max(headerCells.count, rows.map(\.count).max() ?? 0)
        let rowCount = rows.count

        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                if !headerCells.isEmpty {
                    GridRow {
                        ForEach(Array(headerCells.enumerated()), id: \.offset) { col, cell in
                            if col > 0 {
                                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                            }
                            RenderTableCell(
                                inline: cell,
                                isHeader: true,
                                alignment: col < alignments.count ? alignments[col] : nil,
                                isLastColumn: col == numCols - 1
                            )
                        }
                    }
                    Divider()
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowCells in
                    GridRow {
                        ForEach(Array(rowCells.enumerated()), id: \.offset) { col, cell in
                            if col > 0 {
                                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                            }
                            RenderTableCell(
                                inline: cell,
                                isHeader: false,
                                alignment: col < alignments.count ? alignments[col] : nil,
                                isLastColumn: col == numCols - 1
                            )
                        }
                        // Fill remaining empty columns if the row is short
                        if rowCells.count < numCols {
                            ForEach(rowCells.count..<numCols, id: \.self) { col in
                                if col > 0 {
                                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                                }
                                Color.clear
                                    .frame(maxHeight: .infinity)
                            }
                        }
                    }
                    if rowIndex < rowCount - 1 {
                        Divider()
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

struct RenderTableCell: View {
    let inline: AttributedString
    let isHeader: Bool
    let alignment: Markdown.Table.ColumnAlignment?
    let isLastColumn: Bool

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        InlineContentView(attributed: inline)
            .font(theme.bodySwiftUIFont)
            .fontWeight(isHeader ? .semibold : nil)
            .foregroundColor(theme.textColor)
            .multilineTextAlignment(swiftUITextAlignment(for: alignment))
            .padding(.all, 8)
            .frame(maxHeight: .infinity, alignment: textAlignment(for: alignment))
            .gridColumnAlignment(horizontalAlignment(for: alignment))
    }
}
