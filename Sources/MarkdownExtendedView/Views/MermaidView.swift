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

private let mermaidHeightMessageName = "mermaidHeight"

/// A view that renders Mermaid diagrams using a WebView.
///
/// When the `.mermaid` feature is enabled, code blocks with language "mermaid"
/// are rendered using this view, which embeds the Mermaid.js library.
struct MermaidView: View {

    let code: String
    let theme: MarkdownTheme

    @State private var height: CGFloat = 0

    var body: some View {
        MermaidWebView(code: code, height: $height)
            .allowsHitTesting(false)
            .frame(height: height)
            .background(theme.codeBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Platform-Specific WebView

#if canImport(UIKit)

/// UIKit implementation of the Mermaid WebView.
struct MermaidWebView: UIViewRepresentable {

    let code: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidHeightMessageName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: mermaidHeightMessageName)
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
            // Get the content height after rendering
            webView.evaluateJavaScript(
                """
                (() => {
                    const root = document.getElementById('mermaid-root');
                    const svg = root ? root.querySelector('svg') : null;
                    if (!svg) {
                        return 0;
                    }
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const contentHeight = svg.getBoundingClientRect().height + bodyPaddingTop + bodyPaddingBottom;
                    return Math.max(Math.ceil(contentHeight), 100);
                })()
                """
            ) { [weak self] result, _ in
                self?.updateHeight(from: result)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == mermaidHeightMessageName else { return }
            updateHeight(from: message.body)
        }

        private func updateHeight(from value: Any?) {
            let parsedHeight: CGFloat?
            switch value {
            case let number as NSNumber:
                parsedHeight = CGFloat(truncating: number)
            case let doubleValue as Double:
                parsedHeight = CGFloat(doubleValue)
            case let intValue as Int:
                parsedHeight = CGFloat(intValue)
            case let cgValue as CGFloat:
                parsedHeight = cgValue
            default:
                parsedHeight = nil
            }

            guard let parsedHeight else { return }
            DispatchQueue.main.async {
                let newHeight = max(parsedHeight, 0)
                guard abs(self.parent.height - newHeight) > 0.5 else { return }
                self.parent.height = newHeight
            }
        }
    }
}

#elseif canImport(AppKit)

/// AppKit implementation of the Mermaid WebView.
struct MermaidWebView: NSViewRepresentable {

    let code: String
    @Binding var height: CGFloat
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidHeightMessageName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: mermaidHeightMessageName)
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
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
            // Get the content height after rendering
            webView.evaluateJavaScript(
                """
                (() => {
                    const root = document.getElementById('mermaid-root');
                    const svg = root ? root.querySelector('svg') : null;
                    if (!svg) {
                        return 0;
                    }
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const contentHeight = svg.getBoundingClientRect().height + bodyPaddingTop + bodyPaddingBottom;
                    return Math.max(Math.ceil(contentHeight), 100);
                })()
                """
            ) { [weak self] result, _ in
                self?.updateHeight(from: result)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == mermaidHeightMessageName else { return }
            updateHeight(from: message.body)
        }

        private func updateHeight(from value: Any?) {
            let parsedHeight: CGFloat?
            switch value {
            case let number as NSNumber:
                parsedHeight = CGFloat(truncating: number)
            case let doubleValue as Double:
                parsedHeight = CGFloat(doubleValue)
            case let intValue as Int:
                parsedHeight = CGFloat(intValue)
            case let cgValue as CGFloat:
                parsedHeight = cgValue
            default:
                parsedHeight = nil
            }

            guard let parsedHeight else { return }
            DispatchQueue.main.async {
                let newHeight = max(parsedHeight, 0)
                guard abs(self.parent.height - newHeight) > 0.5 else { return }
                self.parent.height = newHeight
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
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="./mermaid.js"></script>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
            html, body {
                overflow: hidden;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                padding: 16px;
                background: transparent;
            }
            #mermaid-root {
                width: 100%;
                max-width: 100%;
            }
            #mermaid-root svg {
                width: 100% !important;
                max-width: 100%;
                height: auto !important;
                display: block;
            }
        </style>
    </head>
    <body>
        <div id="mermaid-root"></div>
        <script>
            const mermaidDefinition = `\(escapedCode)`;
            let renderAttempt = 0;

            mermaid.initialize({
                startOnLoad: false,
                suppressErrorRendering: true,
                theme: 'neutral',
                securityLevel: 'loose',
                flowchart: {
                    useMaxWidth: true,
                    htmlLabels: true
                },
                sequence: {
                    useMaxWidth: true
                }
            });

            async function renderMermaidSafely() {
                const root = document.getElementById('mermaid-root');
                if (!root) {
                    reportHeight();
                    return;
                }

                const currentAttempt = ++renderAttempt;
                root.innerHTML = '';

                try {
                    const renderId = `mermaid-diagram-${Date.now()}-${currentAttempt}`;
                    const result = await mermaid.render(renderId, mermaidDefinition);

                    // Ignore stale render results if a newer attempt has started.
                    if (currentAttempt !== renderAttempt) {
                        return;
                    }

                    root.innerHTML = result.svg;
                    if (typeof result.bindFunctions === 'function') {
                        result.bindFunctions(root);
                    }
                    applyFullWidth();
                } catch (_) {
                    // Silent failure: no error diagram and no placeholder UI.
                    root.innerHTML = '';
                }

                refreshLayout();
            }

            function applyFullWidth() {
                const svg = document.querySelector('#mermaid-root svg');
                if (!svg) {
                    return;
                }
                svg.setAttribute('width', '100%');
                svg.style.width = '100%';
                svg.style.maxWidth = '100%';
                svg.style.height = 'auto';
                svg.removeAttribute('height');
            }

            function reportHeight() {
                const root = document.getElementById('mermaid-root');
                const svg = root ? root.querySelector('svg') : null;
                let height = 0;

                if (svg) {
                    const bodyStyle = window.getComputedStyle(document.body);
                    const bodyPaddingTop = parseFloat(bodyStyle.paddingTop) || 0;
                    const bodyPaddingBottom = parseFloat(bodyStyle.paddingBottom) || 0;
                    const contentHeight = svg.getBoundingClientRect().height + bodyPaddingTop + bodyPaddingBottom;
                    height = Math.max(Math.ceil(contentHeight), 100);
                }

                if (
                    window.webkit &&
                    window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.\(mermaidHeightMessageName)
                ) {
                    window.webkit.messageHandlers.\(mermaidHeightMessageName).postMessage(height);
                }
            }

            function refreshLayout() {
                applyFullWidth();
                reportHeight();
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

/// A placeholder view shown when mermaid is disabled.
struct MermaidPlaceholderView: View {

    let code: String
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(theme.secondaryTextColor)
                Text("Mermaid Diagram")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.secondaryTextColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.trimmingCharacters(in: .newlines))
                    .font(theme.codeBlockFont)
                    .foregroundColor(theme.textColor)
            }
        }
        .padding(theme.codeBlockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
