// LaTeXView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import Synchronization

#if canImport(AppKit)
import AppKit
#endif

struct LayoutWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A view that renders LaTeX equations using SwiftMath.
struct LaTeXView: View {

    let latex: String
    let isBlock: Bool
    let theme: MarkdownTheme
    var maxWidth: CGFloat? = nil
    var overrideFontSize: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var detectedWidth: CGFloat? = nil

    private var effectiveMaxWidth: CGFloat? {
        maxWidth ?? detectedWidth
    }

    var body: some View {
        if isBlock {
            mathView
        } else {
            // Inline math - flows with text
            mathView
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: LayoutWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(LayoutWidthPreferenceKey.self) { width in
                    if maxWidth == nil && width > 0 {
                        detectedWidth = width
                    }
                }
        }
    }

    @ViewBuilder
    private var mathView: some View {
        let ascent = calculatedAscent
        let fSize = overrideFontSize ?? (isBlock ? theme.latexBlockFontSize : theme.latexInlineFontSize)
        MathView(
            latex: latex,
            fontSize: fSize,
            textColor: textColor,
            labelMode: isBlock ? .display : .text,
            maxWidth: effectiveMaxWidth
        )
        .alignmentGuide(.firstTextBaseline) { _ in
            ascent
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
        let fSize = overrideFontSize ?? (isBlock ? theme.latexBlockFontSize : theme.latexInlineFontSize)
        let displayList = MathDisplayCache.shared.getList(latex: latex, fontSize: fSize, isBlock: isBlock)
        // Add half of the inkPadding (which is 8 for block, 0 for inline) to shift the baseline down properly.
        return (displayList?.ascent ?? 0) + (isBlock ? 4 : 0)
    }
}

// MARK: - Math Cache

final class MathDisplayCache: @unchecked Sendable {
    static let shared = MathDisplayCache()
    
    struct CacheKey: Hashable {
        let latex: String
        let fontSize: CGFloat
        let isBlock: Bool
        let maxWidth: CGFloat
    }
    
    private let listCache = Mutex<[CacheKey: MTMathListDisplay]>([:])
    
    struct CachedImage {
        let image: Image
        let ascent: CGFloat
        let descent: CGFloat
        let width: CGFloat
    }
    
    struct ImageCacheKey: Hashable {
        let latex: String
        let fontSize: CGFloat
        let isBlock: Bool
        let maxWidth: CGFloat
        let colorHash: Int
    }
    
    private let imageCache = Mutex<[ImageCacheKey: CachedImage]>([:])

    func getList(latex: String, fontSize: CGFloat, isBlock: Bool, maxWidth: CGFloat = 0) -> MTMathListDisplay? {
        let key = CacheKey(latex: latex, fontSize: fontSize, isBlock: isBlock, maxWidth: maxWidth)
        return listCache.withLock { $0[key] }
    }

    func getCachedImage(latex: String, fontSize: CGFloat, isBlock: Bool, maxWidth: CGFloat = 0, textColor: MTColor) -> CachedImage? {
        let key = ImageCacheKey(latex: latex, fontSize: fontSize, isBlock: isBlock, maxWidth: maxWidth, colorHash: textColor.hashValue)
        
        if let cached = imageCache.withLock({ $0[key] }) {
            return cached
        }
        
        let listKey = CacheKey(latex: latex, fontSize: fontSize, isBlock: isBlock, maxWidth: maxWidth)
        let displayList: MTMathListDisplay
        
        if let cachedList = listCache.withLock({ $0[listKey] }) {
            displayList = cachedList
        } else {
            var error: NSError?
            guard let mathList = MTMathListBuilder.build(fromString: latex, error: &error),
                  let font = MTFontManager.manager.defaultFont?.copy(withSize: fontSize) else {
                return nil
            }
            let style: MTLineStyle = isBlock ? .display : .text
            guard let list = MTTypesetter.createLineForMathList(mathList, font: font, style: style, maxWidth: maxWidth) else {
                return nil
            }
            displayList = list
            listCache.withLock { $0[listKey] = list }
        }
        
        let inkPadding: CGFloat = isBlock ? 8 : 0
        let size = CGSize(width: displayList.width + inkPadding, height: displayList.ascent + displayList.descent + inkPadding)
        displayList.textColor = textColor
        
        #if os(macOS)
        let scale = (NSScreen.main?.backingScaleFactor ?? 2.0) * 2.0
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: inkPadding/2, y: displayList.descent + inkPadding/2)
        displayList.draw(context)
        
        guard let cgImage = context.makeImage() else { return nil }
        let finalImage = Image(nsImage: NSImage(cgImage: cgImage, size: size))
        #else
        let scale = UIScreen.main.scale * 2.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let uiImage = renderer.image { ctx in
            let cgContext = ctx.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1.0, y: -1.0)
            cgContext.translateBy(x: inkPadding/2, y: displayList.descent + inkPadding/2)
            displayList.draw(cgContext)
            cgContext.restoreGState()
        }
        let finalImage = Image(uiImage: uiImage)
        #endif
        
        let cached = CachedImage(image: finalImage, ascent: displayList.ascent, descent: displayList.descent, width: displayList.width)
        imageCache.withLock { $0[key] = cached }
        return cached
    }
}

// MARK: - MathView (SwiftMath Wrapper)

/// A pure SwiftUI view that renders LaTeX using a baked cached Image.
struct MathView: View {
    let latex: String
    var fontSize: CGFloat = 16
    var textColor: MTColor = .textColor
    var labelMode: MTMathUILabelMode = .display
    var maxWidth: CGFloat? = nil

    private var cachedResult: MathDisplayCache.CachedImage? {
        MathDisplayCache.shared.getCachedImage(
            latex: latex,
            fontSize: fontSize,
            isBlock: labelMode == .display,
            maxWidth: maxWidth ?? 0,
            textColor: textColor
        )
    }
    
    private let inkPadding: CGFloat = 8

    var body: some View {
        if let cached = cachedResult {
            cached.image
                .makeCanSelectable(isBlock: true, blockText: "$\(latex)$")
        } else {
            // Fallback for parsing errors
            Text(latex)
                .font(.system(size: fontSize))
                .foregroundColor(Color(textColor))
                .makeCanSelectable()
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

    func maxWidth(_ w: CGFloat?) -> MathView {
        var view = self
        view.maxWidth = w
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
