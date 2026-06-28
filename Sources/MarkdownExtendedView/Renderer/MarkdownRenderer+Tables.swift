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
    let table: Markdown.Table
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler
    
    var body: some View {
        let alignments = table.columnAlignments
        let headerCells = Array(table.head.cells)
        let rows: [[Markdown.Table.Cell]] = table.body.rows.map { Array($0.cells) }
        
        var maxCol = headerCells.count
        for row in rows { maxCol = max(maxCol, row.count) }
        let numCols = maxCol
        let rowCount: Int = rows.count
        
        return ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                if !headerCells.isEmpty {
                    GridRow {
                        ForEach(Array(headerCells.enumerated()), id: \.offset) { col, cell in
                            if col > 0 {
                                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                            }
                            RenderTableCell(
                                cell: cell,
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
                                cell: cell,
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
//            .frame(maxWidth: geometry.width)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

struct RenderTableCell: View {
    let cell: Markdown.Table.Cell
    let isHeader: Bool
    let alignment: Markdown.Table.ColumnAlignment?
    let isLastColumn: Bool
    
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownBaseURL) private var baseURL
    @Environment(\.markdownLinkHandler) private var linkHandler
    @Environment(\.markdownMCodeReferenceHandler) private var MCodeReferenceHandler

    var body: some View {
        let frameAlign: Alignment = textAlignment(for: alignment)
        let gridHorizontalAlign: HorizontalAlignment = horizontalAlignment(for: alignment)
        let multilineAlign: TextAlignment = swiftUITextAlignment(for: alignment)
        let features = computeInlineFeatures(cell)
        
        Group {
            if features.contains(.hasMCodeReferences) || features.contains(.hasImages) || features.contains(.hasLinks) {
                BuildInlineText(
                    parent: cell,
                    features: features,
                    baseFont: theme.bodySwiftUIFont,
                    baseFontSize: theme.bodyFont.pointSize
                )
            } else {
                MarkdownTextBuilder(theme: theme, baseURL: baseURL, baseFont: theme.bodySwiftUIFont, baseFontSize: theme.bodyFont.pointSize)
                    .build(from: cell)
                    .makeCanSelectable()
            }
        }
        .font(theme.bodySwiftUIFont)
        .fontWeight(isHeader ? .semibold : nil)
        .foregroundColor(theme.textColor)
        .multilineTextAlignment(multilineAlign)
        .padding(.all, 8)
        .frame(maxHeight: .infinity, alignment: frameAlign)
        .gridColumnAlignment(gridHorizontalAlign)
    }
}
