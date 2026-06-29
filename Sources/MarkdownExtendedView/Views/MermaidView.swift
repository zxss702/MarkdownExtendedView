// MermaidView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import BeautifulMermaid

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Global cache to store synchronously parsed Mermaid images to avoid re-parsing during view re-evaluation.
@MainActor
final class MermaidImageCache {
    static let shared = MermaidImageCache()
    private let cache = NSCache<NSString, BMImage>()
    
    private init() {
        cache.countLimit = 100
    }
    
    func getImage(for code: String, theme: DiagramTheme) -> BMImage? {
        // We use a simple hash of the code as the key.
        // If theme properties change significantly, you might want to include theme hash in the key.
        let key = NSString(string: "\(code.hashValue)")
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        let renderer = MermaidImageRenderer(
            theme: theme,
            config: LayoutConfig(
                padding: 0,
                nodeSpacing: 32,
                layerSpacing: 48,
                componentSpacing: 24
            )
        )
        // Parse and render synchronously on the current thread
        if let image = try? renderer.renderImage(from: code, scale: (NSScreen.main?.backingScaleFactor ?? 2)) {
            cache.setObject(image, forKey: key)
            return image
        }
        return nil
    }
}

/// A view that renders Mermaid diagrams using the native BeautifulMermaidSwift library.
struct MermaidView: View {
    let code: String
    let theme: MarkdownTheme
    let viewWidth: CGFloat
    
    @State private var diagramImage: BMImage? = nil
    
    init(code: String, theme: MarkdownTheme, viewWidth: CGFloat) {
        self.code = code
        self.theme = theme
        self.viewWidth = viewWidth
        
        // 1. Convert MarkdownTheme to DiagramTheme
        #if canImport(AppKit)
        let fg = NSColor(theme.textColor)
        let sg = NSColor(theme.secondaryTextColor)
        #elseif canImport(UIKit)
        let fg = UIColor(theme.textColor)
        let sg = UIColor(theme.secondaryTextColor)
        #endif
        
        let diagramTheme = DiagramTheme(
            background: .windowBackgroundColor,
            foreground: fg,
            line: fg,
            accent: fg,
            muted: sg,
            surface: .windowBackgroundColor,
            border: .clear,
            font: .systemFont(ofSize: 14, weight: .light),
            lineWidth: 1,
            cornerRadius: 16,
            transparent: true
        )
        
        // 2. Synchronously fetch or parse the image
        if let image = MermaidImageCache.shared.getImage(for: code, theme: diagramTheme) {
            self._diagramImage = State(initialValue: image)
        } else {
            self._diagramImage = State(initialValue: nil)
        }
    }
    
    var body: some View {
        if let image = diagramImage {
            #if canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .makeCanSelectable(isBlock: true, blockText: code)
            
                .frame(maxWidth: image.size.width) // Use logical size
                .frame(maxWidth: .infinity, alignment: .center)
            #elseif canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .makeCanSelectable(isBlock: true, blockText: code)
            
                .frame(maxWidth: image.size.width)
                .frame(maxWidth: .infinity, alignment: .center)
            #endif
        } else {
            SwiftUI.Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(theme.secondaryTextColor)
            
                .makeCanSelectable()
            
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
