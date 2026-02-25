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

private let mermaidSizeMessageName = "mermaidSize"

/// A view that renders Mermaid diagrams using a WebView.
///
/// When the `.mermaid` feature is enabled, code blocks with language "mermaid"
/// are rendered using this view, which embeds the Mermaid.js library.
struct MermaidView: View {

    let code: String
    let theme: MarkdownTheme

    @State private var contentSize: CGSize = .zero

    var body: some View {
        MermaidWebView(code: code, contentSize: $contentSize)
            .frame(maxWidth: contentSize.width > 0 ? contentSize.width : .infinity)
            .frame(height: contentSize.height > 0 ? contentSize.height : nil)
            .background(theme.codeBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Platform-Specific WebView

#if canImport(UIKit)

/// UIKit implementation of the Mermaid WebView.
struct MermaidWebView: UIViewRepresentable {

    let code: String
    @Binding var contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidSizeMessageName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: mermaidSizeMessageName)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedCode != code else { return }
        context.coordinator.lastLoadedCode = code
        let html = generateHTML(for: code)
        webView.loadHTMLString(html, baseURL: Bundle.module.resourceURL)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        var lastLoadedCode: String?

        init(_ parent: MermaidWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get the content size after rendering
            webView.evaluateJavaScript(
                """
                (() => {
                    const root = document.getElementById('mermaid-root');
                    const svg = root ? root.querySelector('svg') : null;
                    if (!svg) {
                        return {width: 0, height: 0};
                    }
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const bodyPaddingLeft = parseFloat(bodyStyle.paddingLeft) || 0;
                    const bodyPaddingRight = parseFloat(bodyStyle.paddingRight) || 0;
                    const rect = svg.getBoundingClientRect();
                    const contentHeight = rect.height + bodyPaddingTop + bodyPaddingBottom;
                    const contentWidth = rect.width + bodyPaddingLeft + bodyPaddingRight;
                    return {
                        width: Math.max(Math.ceil(contentWidth), 50),
                        height: Math.max(Math.ceil(contentHeight), 50)
                    };
                })()
                """
            ) { [weak self] result, _ in
                self?.updateSize(from: result)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == mermaidSizeMessageName else { return }
            updateSize(from: message.body)
        }

        private func updateSize(from value: Any?) {
            guard let dict = value as? [String: Any],
                  let width = dict["width"] as? NSNumber,
                  let height = dict["height"] as? NSNumber else {
                return
            }
            let w = CGFloat(truncating: width)
            let h = CGFloat(truncating: height)

            DispatchQueue.main.async {
                let newSize = CGSize(width: max(w, 0), height: max(h, 0))
                guard abs(self.parent.contentSize.width - newSize.width) > 0.5 || 
                      abs(self.parent.contentSize.height - newSize.height) > 0.5 else { return }
                self.parent.contentSize = newSize
            }
        }
    }
}

#elseif canImport(AppKit)

/// AppKit implementation of the Mermaid WebView.
struct MermaidWebView: NSViewRepresentable {

    let code: String
    @Binding var contentSize: CGSize
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> CustomWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidSizeMessageName)
        let webView = CustomWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Disable internal scrolling on macOS WKWebView to pass scroll events to SwiftUI parent
        if let scrollView = webView.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollsDynamically = false
        }
        
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    static func dismantleNSView(_ webView: CustomWKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: mermaidSizeMessageName)
    }
    
    func updateNSView(_ webView: CustomWKWebView, context: Context) {
        guard context.coordinator.lastLoadedCode != code else { return }
        context.coordinator.lastLoadedCode = code
        let html = generateHTML(for: code)
        webView.loadHTMLString(html, baseURL: Bundle.module.resourceURL)
    }

    class CustomWKWebView: WKWebView {
        // macOS AppKit: Bypass vertical scrolling entirely to parent view
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
            super.scrollWheel(with: event)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        var lastLoadedCode: String?

        init(_ parent: MermaidWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Get the content size after rendering
            webView.evaluateJavaScript(
                """
                (() => {
                    const root = document.getElementById('mermaid-root');
                    const svg = root ? root.querySelector('svg') : null;
                    if (!svg) {
                        return {width: 0, height: 0};
                    }
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const bodyPaddingLeft = parseFloat(bodyStyle.paddingLeft) || 0;
                    const bodyPaddingRight = parseFloat(bodyStyle.paddingRight) || 0;
                    const rect = svg.getBoundingClientRect();
                    const contentHeight = rect.height + bodyPaddingTop + bodyPaddingBottom;
                    const contentWidth = rect.width + bodyPaddingLeft + bodyPaddingRight;
                    return {
                        width: Math.max(Math.ceil(contentWidth), 50),
                        height: Math.max(Math.ceil(contentHeight), 50)
                    };
                })()
                """
            ) { [weak self] result, _ in
                self?.updateSize(from: result)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == mermaidSizeMessageName else { return }
            updateSize(from: message.body)
        }

        private func updateSize(from value: Any?) {
            guard let dict = value as? [String: Any],
                  let width = dict["width"] as? NSNumber,
                  let height = dict["height"] as? NSNumber else {
                return
            }
            let w = CGFloat(truncating: width)
            let h = CGFloat(truncating: height)

            DispatchQueue.main.async {
                let newSize = CGSize(width: max(w, 0), height: max(h, 0))
                guard abs(self.parent.contentSize.width - newSize.width) > 0.5 || 
                      abs(self.parent.contentSize.height - newSize.height) > 0.5 else { return }
                self.parent.contentSize = newSize
            }
        }
    }
}

#endif

// MARK: - HTML Generation

/// Generates the HTML document for rendering a Mermaid diagram.
private func generateHTML(for code: String) -> String {
    // Escape the code for use in HTML/JavaScript
    let escapedCode = code
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "</script>", with: "<\\/script>", options: .caseInsensitive, range: nil)

    return """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <script src="./mermaid.js"></script>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            html {
                overflow-x: auto;
                overflow-y: hidden;
                overscroll-behavior-y: none;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                padding: 16px;
                margin: 0;
                background: transparent;
                display: inline-block;
                min-width: 100%;
                min-height: 100vh;
            }
            #mermaid-root {
                width: max-content;
                min-width: 100%;
            }
            #mermaid-root svg {
                display: block;
            }
        </style>
    </head>
    <body>
        <div id="mermaid-root"></div>
        <script>
            // Intercept vertical wheel scrolling and prevent WebView from consuming it,
            // allowing the event to bubble up to the native macOS/iOS ScrollView.
            window.addEventListener('wheel', (e) => {
                if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
                    // It's a vertical scroll. Prevent default WebView scroll action.
                    e.preventDefault();
                    // We don't propagate manually in WKWebView by default, 
                    // preventDefault on body/html is enough to let AppKit/UIKit know 
                    // the scroll wasn't consumed by the web content block.
                }
            }, { passive: false });

            const mermaidDefinition = `\(escapedCode)`;
            let renderAttempt = 0;

            mermaid.initialize({
                startOnLoad: false,
                suppressErrorRendering: true,
                theme: 'neutral',
                themeVariables: {
                    fontSize: '14px'
                },
                securityLevel: 'loose',
                flowchart: {
                    useMaxWidth: false,
                    htmlLabels: true
                },
                sequence: {
                    useMaxWidth: false
                }
            });

            async function renderMermaidSafely() {
                const root = document.getElementById('mermaid-root');
                if (!root) {
                    reportSize();
                    return;
                }

                const currentAttempt = ++renderAttempt;
                root.innerHTML = '';

                try {
                    const renderId = `mermaid-diagram-${Date.now()}-${currentAttempt}`;
                    const result = await mermaid.render(renderId, mermaidDefinition);

                    if (currentAttempt !== renderAttempt) {
                        return;
                    }

                    root.innerHTML = result.svg;
                    if (typeof result.bindFunctions === 'function') {
                        result.bindFunctions(root);
                    }
                } catch (_) {
                    root.innerHTML = '';
                }

                refreshLayout();
            }

            function reportSize() {
                const root = document.getElementById('mermaid-root');
                const svg = root ? root.querySelector('svg') : null;
                let height = 0;
                let width = 0;

                if (svg) {
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const bodyPaddingLeft = parseFloat(bodyStyle.paddingLeft) || 0;
                    const bodyPaddingRight = parseFloat(bodyStyle.paddingRight) || 0;
                    const rect = svg.getBoundingClientRect();
                    const contentHeight = rect.height + bodyPaddingTop + bodyPaddingBottom;
                    const contentWidth = rect.width + bodyPaddingLeft + bodyPaddingRight;
                    height = Math.max(Math.ceil(contentHeight), 50);
                    width = Math.max(Math.ceil(contentWidth), 50);
                }

                if (
                    window.webkit &&
                    window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.\(mermaidSizeMessageName)
                ) {
                    window.webkit.messageHandlers.\(mermaidSizeMessageName).postMessage({width: width, height: height});
                }
            }

            function refreshLayout() {
                reportSize();
            }

            window.addEventListener('load', () => {
                renderMermaidSafely();
                refreshLayout();
                setTimeout(refreshLayout, 0);
                setTimeout(refreshLayout, 80);
            });

            window.addEventListener('resize', () => {
                refreshLayout();
                requestAnimationFrame(refreshLayout);
                setTimeout(refreshLayout, 80);
            });
        </script>
    </body>
    </html>
    """
}
