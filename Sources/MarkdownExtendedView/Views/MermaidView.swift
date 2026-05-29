// MermaidView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// A view that renders Mermaid diagrams by leveraging a global headless renderer.
struct MermaidView: View {

    let code: String
    let theme: MarkdownTheme

    @State private var renderResult: MermaidRenderResult? = nil
    @State private var containerWidth: CGFloat = 0
    @State private var errorMessage: String? = nil

    var body: some View {
        let fontSize: CGFloat = 14
        
        ZStack(alignment: .leading) {
            // Background to measure available width
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in containerWidth = newWidth }
            }
            .frame(height: 0)

            if let result = renderResult {
                let scale = result.width > 0 && containerWidth > 0 ? min(1.0, containerWidth / result.width) : 1.0
                let finalWidth = result.width > 0 ? result.width * scale : (containerWidth > 0 ? containerWidth : 300)
                let finalHeight = result.height > 0 ? result.height * scale : 200

                MermaidSVGWebView(svg: result.svg)
                    .frame(width: finalWidth, height: finalHeight)
                    .background(theme.codeBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMsg = errorMessage {
                Text("Error: \(errorMsg)")
                    .font(.system(size: fontSize))
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.codeBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Empty state while loading instantly
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: code) {
            do {
                let result = try await MermaidRenderer.shared.render(code: code, fontSize: fontSize)
                self.renderResult = result
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Platform-Specific SVG WebView

#if canImport(UIKit)

struct MermaidSVGWebView: UIViewRepresentable {
    let svg: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(generateSVGHTML(svg: svg), baseURL: nil)
    }
}

#elseif canImport(AppKit)

struct MermaidSVGWebView: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> CustomWKWebView {
        let webView = CustomWKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: CustomWKWebView, context: Context) {
        webView.loadHTMLString(generateSVGHTML(svg: svg), baseURL: nil)
    }

    final class CustomWKWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
            super.scrollWheel(with: event)
        }
    }
}

#endif

// MARK: - HTML Generation for SVG

/// Generates a minimal HTML document for rendering pure SVG.
private func generateSVGHTML(svg: String) -> String {
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            html, body {
                width: 100%;
                height: 100%;
                overflow: hidden;
                overscroll-behavior: none;
                background: transparent;
                display: flex;
                align-items: center;
                justify-content: center;
            }
            svg {
                display: block;
                max-width: 100%;
                max-height: 100%;
                width: auto !important;
                height: auto !important;
            }
        </style>
    </head>
    <body>
        \(svg)
        <script>
            window.addEventListener('wheel', (e) => {
                if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
                    e.preventDefault();
                }
            }, { passive: false });
        </script>
    </body>
    </html>
    """
}
