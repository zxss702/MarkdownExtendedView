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

    let viewWidth: CGFloat
    
    @State private var renderResult: MermaidRenderResult? = nil

    @State var showSheet = false
    
    @State var width: CGFloat? = nil
    var body: some View {
        let fontSize: CGFloat = 14
        
        ZStack {
            if let result = renderResult {
                let scale = min(1.0, viewWidth / result.width)
                let finalWidth = result.width * scale
                let finalHeight = result.height * scale
                
                MermaidSVGWebView(svg: result.svg)
                    .frame(width: finalWidth, height: finalHeight)
                    .allowsHitTesting(false)
                    .onTapGesture {
                        showSheet.toggle()
                    }
                    .sheet(isPresented: $showSheet) {
                        MermaidSVGWebView(svg: result.svg)
                            .frame(width: result.width, height: result.height)
                            .padding(.all, 32)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    showSheet = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .frame(width: 48, height: 48)
                                        .containerShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                    }
            }
        }
        .task(id: code, priority: .userInitiated) {
            do {
                let result = try await MermaidRenderer.shared.render(code: code, fontSize: fontSize)
                self.renderResult = result
            } catch {}
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
