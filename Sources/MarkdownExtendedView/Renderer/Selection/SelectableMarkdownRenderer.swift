#if os(macOS) || os(iOS)
// SelectableMarkdownRenderer.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

public extension View {
    func selectable() -> some View {
        modifier(SelectableMarkdownRendererViewModifier())
    }
}

struct SelectableMarkdownRendererViewModifier: ViewModifier {
    @State private var model = SelectionModel()
    
    @State private var textLayouts: SwiftUI.Text.LayoutKey.Value = []
    @State private var formulas: [FormulaSelectionData] = []

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(SwiftUI.Text.LayoutKey.self) { layouts in
                self.textLayouts = layouts
            }
            .onPreferenceChange(FormulaSelectionKey.self) { formulas in
                self.formulas = formulas
            }
            .background {
                GeometryReader { geometry in
                    let input = SelectionLayoutInput(base: textLayouts, formulas: formulas, geometry: geometry, containerSize: geometry.size)
                    SelectionInteractionOverlay(model: model)
                        .task(id: input) {
                            await model.updateLayout(input)
                        }
                }
            }
            .overlay {
                SelectionHighlightLayer(model: model)
                    .allowsHitTesting(false)
            }
    }
}

private struct SelectionHighlightLayer: View {
    let model: SelectionModel

    #if canImport(AppKit)
    private let fillColor = Color(nsColor: .selectedTextBackgroundColor).opacity(0.5)
    #else
    private let fillColor = Color(uiColor: .systemBlue).opacity(0.28)
    #endif

    var body: some View {
        Canvas { context, _ in
            context.blendMode = .multiply
            for selectionRect in model.selectionRects {
                context.fill(
                    Path(selectionRect.rect),
                    with: .color(fillColor)
                )
            }
        }
    }
}
#endif
