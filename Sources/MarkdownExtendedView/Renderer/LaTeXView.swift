// LaTeXView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import ExtendedSwiftMath

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
        var error: NSError?
        guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error) else { return 0 }
        let fSize = isBlock ? theme.latexBlockFontSize : theme.latexInlineFontSize
        guard let font = MTFontManager.fontManager.defaultFont?.copy(withSize: fSize) else { return 0 }
        let style: MTLineStyle = isBlock ? .display : .text
        if let displayList = MTTypesetter.createLineForMathList(mathList, font: font, style: style, maxWidth: 0) {
            return displayList.ascent
        }
        return 0
    }
}

// MARK: - MathView (SwiftMath Wrapper)

/// A SwiftUI wrapper for SwiftMath's MTMathUILabel.
struct MathView {

    let latex: String

    fileprivate var fontSize: CGFloat = 16
    fileprivate var textColor: MTColor = .black
    fileprivate var textAlignment: MTTextAlignment = .right
    fileprivate var labelMode: MTMathUILabelMode = .display

    init(latex: String) {
        self.latex = latex
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

    func textAlignment(_ alignment: MTTextAlignment) -> MathView {
        var view = self
        view.textAlignment = alignment
        return view
    }
}

#if os(iOS)
extension MathView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = textColor
        label.textAlignment = textAlignment
        label.labelMode = labelMode
        label.backgroundColor = .clear
        return label
    }

    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.latex = latex
        uiView.fontSize = fontSize
        uiView.textColor = textColor
        uiView.textAlignment = textAlignment
        uiView.labelMode = labelMode
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        // ALWAYS pass 0 width to disable MTMathUILabel's buggy internal line wrapping.
        // This ensures the math formula stays on one line (or wraps cleanly as a single block in FlowLayout).
        uiView.sizeThatFits(CGSize(width: 0, height: 0))
    }
}
#elseif os(macOS)
extension MathView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = textColor
        label.textAlignment = textAlignment
        label.labelMode = labelMode
        // Note: backgroundColor not accessible on macOS, view is transparent by default
        
        return label
    }

    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        nsView.latex = latex
        nsView.fontSize = fontSize
        nsView.textColor = textColor
        nsView.textAlignment = textAlignment
        nsView.labelMode = labelMode
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        // ALWAYS pass 0 width to disable MTMathUILabel's buggy internal line wrapping.
        // This ensures the math formula stays on one line (or wraps cleanly as a single block in FlowLayout).
        nsView.sizeThatFits(CGSize(width: 0, height: 0))
    }
}
#endif

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
