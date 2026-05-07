// LaTeXView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import Synchronization

/// A view that renders LaTeX equations using SwiftMath.
struct LaTeXView: View {

    let latex: String
    let isBlock: Bool
    let theme: MarkdownTheme

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isBlock {
            // Display/block math - centered, larger
            HStack {
                Spacer()
                mathView
                    .padding(.vertical, 12)
                Spacer()
            }
        } else {
            // Inline math - flows with text
            mathView
        }
    }

    @ViewBuilder
    private var mathView: some View {
        MathView(latex: latex)
            .labelMode(isBlock ? .display : .text)
            .font(fontSize: isBlock ? theme.latexBlockFontSize : theme.latexInlineFontSize)
            .foregroundColor(textColor)
            .alignmentGuide(.firstTextBaseline) { _ in
                calculatedAscent
            }
    }

    private var textColor: MTColor {
        #if os(iOS)
        return colorScheme == .dark ? .white : .black
        #elseif os(macOS)
        return colorScheme == .dark ? .white : .black
        #endif
    }

    private var calculatedAscent: CGFloat {
        let fSize = isBlock ? theme.latexBlockFontSize : theme.latexInlineFontSize
        let displayList = MathDisplayCache.shared.getDisplay(latex: latex, fontSize: fSize, isBlock: isBlock)
        // Add half of the inkPadding (which is 8, so 4) to shift the baseline down properly.
        return (displayList?.ascent ?? 0) + 4
    }
}

// MARK: - Math Cache

final class MathDisplayCache: @unchecked Sendable {
    static let shared = MathDisplayCache()
    private let cache = Mutex<[String: MTMathListDisplay]>([:])

    func getDisplay(latex: String, fontSize: CGFloat, isBlock: Bool) -> MTMathListDisplay? {
        let key = "\(latex)_\(fontSize)_\(isBlock)"
        
        if let display = cache.withLock({ $0[key] }) {
            return display
        }
        
        var error: NSError?
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error),
              let font = MTFontManager.manager.defaultFont?.copy(withSize: fontSize) else {
            return nil
        }
        
        let style: MTLineStyle = isBlock ? .display : .text
        if let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: style, maxWidth: 0) {
            cache.withLock { $0[key] = displayList }
            return displayList
        }
        return nil
    }
}

// MARK: - MathView (SwiftMath Wrapper)

/// A pure SwiftUI view that renders LaTeX using a Canvas.
struct MathView: View {
    let latex: String
    var fontSize: CGFloat = 16
    var textColor: MTColor = .black
    var labelMode: MTMathUILabelMode = .display

    private var displayList: MTMathListDisplay? {
        MathDisplayCache.shared.getDisplay(latex: latex, fontSize: fontSize, isBlock: labelMode == .display)
    }
    
    // Padding to prevent clipping of tall ink bounds (e.g., italic L, integrals)
    private let inkPadding: CGFloat = 8

    var body: some View {
        if let displayList = displayList {
            Canvas { context, size in
                context.withCGContext { cgContext in
                    displayList.textColor = textColor
                    
                    // SwiftUI Canvas coordinate system is Y-down (0,0 is top-left)
                    // CoreText expects Y-up (0,0 is bottom-left).
                    cgContext.translateBy(x: 0, y: size.height)
                    cgContext.scaleBy(x: 1.0, y: -1.0)
                    
                    // MTDisplay is drawn with origin at the baseline.
                    // By shifting up by `descent + inkPadding/2`, the bottom of the display rests at Y=0 (bottom of the Canvas).
                    cgContext.translateBy(x: inkPadding/2, y: displayList.descent + inkPadding/2)
                    
                    displayList.draw(cgContext)
                }
            }
            .frame(width: displayList.width + inkPadding, height: displayList.ascent + displayList.descent + inkPadding)
            .anchorPreference(key: FormulaSelectionKey.self, value: .bounds) { bounds in
                [FormulaSelectionData(latex: "$\(latex)$", bounds: bounds)]
            }
        } else {
            // Fallback for parsing errors
            Text(latex)
                .font(.system(size: fontSize))
                .foregroundColor(Color(textColor))
        }
    }

    // MARK: - Modifiers

    func font(fontSize: CGFloat) -> MathView {
        var view = self
        view.fontSize = fontSize
        return view
    }

    func foregroundColor(_ color: MTColor) -> MathView {
        var view = self
        view.textColor = color
        return view
    }

    func labelMode(_ mode: MTMathUILabelMode) -> MathView {
        var view = self
        view.labelMode = mode
        return view
    }
}

// MARK: - Preview

#if DEBUG
struct LaTeXView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Inline LaTeX:")
            HStack {
                Text("The formula")
                LaTeXView(latex: "E = mc^2", isBlock: false, theme: .default)
                Text("is famous.")
            }

            Divider()

            Text("Block LaTeX:")
            LaTeXView(
                latex: "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}",
                isBlock: true,
                theme: .default
            )
        }
        .padding()
    }
}
#endif
