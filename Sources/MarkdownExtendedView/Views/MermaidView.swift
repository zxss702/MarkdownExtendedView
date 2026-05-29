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
struct MermaidView: View {

    let code: String
    let theme: MarkdownTheme

    @State private var contentSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        let fontSize: CGFloat = 14
        let scale = contentSize.width > 0 && containerWidth > 0 ? min(1.0, containerWidth / contentSize.width) : 1.0
        let finalWidth = contentSize.width > 0 ? contentSize.width * scale : (containerWidth > 0 ? containerWidth : 300)
        let finalHeight = contentSize.height > 0 ? contentSize.height * scale : 200

        MermaidWebView(code: code, fontSize: fontSize, contentSize: $contentSize)
            .frame(width: finalWidth, height: finalHeight)
            .background(theme.codeBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in containerWidth = newWidth }
                }
            )
    }
}

// MARK: - Platform-Specific WebView

#if canImport(UIKit)

struct MermaidWebView: UIViewRepresentable {

    let code: String
    let fontSize: CGFloat
    @Binding var contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(contentSize: $contentSize)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidSizeMessageName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
        let payload = Payload(code: code, fontSize: fontSize)
        guard context.coordinator.lastPayload != payload else { return }
        context.coordinator.lastPayload = payload
        webView.loadHTMLString(generateHTML(for: code, fontSize: fontSize), baseURL: Bundle.module.resourceURL)
    }
}

#elseif canImport(AppKit)

struct MermaidWebView: NSViewRepresentable {

    let code: String
    let fontSize: CGFloat
    @Binding var contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(contentSize: $contentSize)
    }

    func makeNSView(context: Context) -> CustomWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: mermaidSizeMessageName)
        let webView = CustomWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    static func dismantleNSView(_ webView: CustomWKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: mermaidSizeMessageName)
    }

    func updateNSView(_ webView: CustomWKWebView, context: Context) {
        let payload = Payload(code: code, fontSize: fontSize)
        guard context.coordinator.lastPayload != payload else { return }
        context.coordinator.lastPayload = payload
        webView.loadHTMLString(generateHTML(for: code, fontSize: fontSize), baseURL: Bundle.module.resourceURL)
    }

    final class CustomWKWebView: WKWebView {
        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
            super.scrollWheel(with: event)
        }
    }
}

#endif

struct Payload: Equatable {
    let code: String
    let fontSize: CGFloat
}

final class Coordinator: NSObject, WKNavigationDelegate {
    private let contentSize: Binding<CGSize>
    var lastPayload: Payload?

    init(contentSize: Binding<CGSize>) {
        self.contentSize = contentSize
    }
}

extension Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == mermaidSizeMessageName,
              let value = message.body as? [String: Any],
              let width = value["width"] as? NSNumber,
              let height = value["height"] as? NSNumber else {
            return
        }

        let newSize = CGSize(
            width: max(CGFloat(truncating: width), 1),
            height: max(CGFloat(truncating: height), 1)
        )

        DispatchQueue.main.async {
            guard abs(self.contentSize.wrappedValue.width - newSize.width) > 0.5 ||
                    abs(self.contentSize.wrappedValue.height - newSize.height) > 0.5 else {
                return
            }
            self.contentSize.wrappedValue = newSize
        }
    }
}

// MARK: - HTML Generation

/// Generates the HTML document for rendering a Mermaid diagram.
private func generateHTML(for code: String, fontSize: CGFloat) -> String {
    let escapedCode = code
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "</script>", with: "<\\/script>", options: .caseInsensitive, range: nil)

    let cssFontSize = Int(fontSize.rounded())

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
            html, body {
                width: 100%;
                height: 100%;
                overflow: hidden;
                overscroll-behavior: none;
                background: transparent;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                padding: 12px 16px;
                display: flex;
                align-items: center;
                justify-content: center;
            }
            #mermaid-root {
                width: 100%;
                height: 100%;
                display: flex;
                align-items: center;
                justify-content: center;
                overflow: hidden;
            }
            #mermaid-root svg {
                display: block;
                max-width: 100%;
                max-height: 100%;
                width: auto !important;
                height: auto !important;
            }
            .mermaid-error {
                width: 100%;
                color: rgba(60, 60, 67, 0.85);
                font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
                white-space: pre-wrap;
                word-break: break-word;
            }
        </style>
    </head>
    <body>
        <div id="mermaid-root"></div>
        <script>
            window.addEventListener('wheel', (e) => {
                if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
                    e.preventDefault();
                }
            }, { passive: false });

            const mermaidDefinition = `\(escapedCode)`;
            let renderAttempt = 0;

            mermaid.initialize({
                startOnLoad: false,
                suppressErrorRendering: true,
                theme: 'neutral',
                themeVariables: {
                    fontSize: '\(cssFontSize)px'
                },
                securityLevel: 'loose',
                flowchart: {
                    useMaxWidth: true,
                    htmlLabels: true
                },
                sequence: {
                    useMaxWidth: true
                }
            });

            function fitSVG() {
                const root = document.getElementById('mermaid-root');
                const svg = root ? root.querySelector('svg') : null;
                if (!svg) {
                    return;
                }

                svg.style.maxWidth = '100%';
                svg.style.maxHeight = '100%';
                svg.style.width = 'auto';
                svg.style.height = 'auto';
                svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
            }

            function reportNaturalSize() {
                const root = document.getElementById('mermaid-root');
                const svg = root ? root.querySelector('svg') : null;
                if (!svg) {
                    return;
                }

                const bodyStyle = window.getComputedStyle(document.body);
                const paddingX = (parseFloat(bodyStyle.paddingLeft) || 0) + (parseFloat(bodyStyle.paddingRight) || 0);
                const paddingY = (parseFloat(bodyStyle.paddingTop) || 0) + (parseFloat(bodyStyle.paddingBottom) || 0);

                let width = 0;
                let height = 0;

                const viewBox = svg.viewBox && svg.viewBox.baseVal ? svg.viewBox.baseVal : null;
                if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
                    width = viewBox.width;
                    height = viewBox.height;
                } else {
                    const widthAttr = parseFloat(svg.getAttribute('width') || '0');
                    const heightAttr = parseFloat(svg.getAttribute('height') || '0');
                    if (widthAttr > 0 && heightAttr > 0) {
                        width = widthAttr;
                        height = heightAttr;
                    }
                }

                if (width <= 0 || height <= 0) {
                    const rect = svg.getBoundingClientRect();
                    width = rect.width;
                    height = rect.height;
                }

                const fittedWidth = Math.ceil(width + paddingX);
                const fittedHeight = Math.ceil(height + paddingY);

                if (
                    window.webkit &&
                    window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.\(mermaidSizeMessageName)
                ) {
                    window.webkit.messageHandlers.\(mermaidSizeMessageName).postMessage({
                        width: fittedWidth,
                        height: fittedHeight
                    });
                }
            }

            async function renderMermaidSafely() {
                const root = document.getElementById('mermaid-root');
                if (!root) {
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
                    fitSVG();
                    reportNaturalSize();
                } catch (error) {
                    const message = error && error.message ? error.message : String(error);
                    root.innerHTML = `<pre class="mermaid-error">${message}</pre>`;
                }
            }

            window.addEventListener('load', () => {
                renderMermaidSafely();
            });

            window.addEventListener('resize', () => {
                fitSVG();
                reportNaturalSize();
            });
        </script>
    </body>
    </html>
    """
}
