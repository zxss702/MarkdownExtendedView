// MermaidRenderer.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import Foundation
import WebKit

/// The rendering result of a Mermaid diagram containing pure SVG and its natural size.
struct MermaidRenderResult: Equatable, Sendable {
    let svg: String
    let width: CGFloat
    let height: CGFloat
}

/// A global singleton that maintains a single headless WKWebView to parse and render Mermaid syntax to SVG.
/// By maintaining one instance, we avoid repeatedly loading the massive 6.2MB mermaid.js file for every diagram.
@MainActor
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    
    static let shared = MermaidRenderer()
    
    private let webView: WKWebView
    private var isReady = false
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    
    // In-memory cache to prevent re-rendering the same Mermaid code.
    private let cache = NSCache<NSString, MermaidRendererCacheBox>()
    
    private override init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        self.loadRendererHTML()
    }
    
    private func loadRendererHTML() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <script src="./mermaid.js"></script>
        </head>
        <body>
            <div id="mermaid-root"></div>
            <script>
                async function renderToSVG(id, code, fontSize) {
                    try {
                        mermaid.initialize({
                            startOnLoad: false,
                            suppressErrorRendering: true,
                            theme: 'neutral',
                            themeVariables: { fontSize: fontSize + 'px' },
                            securityLevel: 'loose',
                            flowchart: { useMaxWidth: true, htmlLabels: true },
                            sequence: { useMaxWidth: true }
                        });
                        
                        const result = await mermaid.render(id, code);
                        
                        // We inject the SVG into DOM briefly to measure its natural size accurately
                        const root = document.getElementById('mermaid-root');
                        root.innerHTML = result.svg;
                        const svg = root.querySelector('svg');
                        
                        if (!svg) {
                            return JSON.stringify({ error: "No SVG generated" });
                        }
                        
                        // Standardize attributes for the display webview later
                        svg.style.maxWidth = '100%';
                        svg.style.maxHeight = '100%';
                        svg.style.width = 'auto';
                        svg.style.height = 'auto';
                        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
                        
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
                        
                        const finalSvgString = root.innerHTML;
                        root.innerHTML = ''; // Clean up
                        
                        return JSON.stringify({ 
                            svg: finalSvgString, 
                            width: Math.ceil(width + paddingX), 
                            height: Math.ceil(height + paddingY) 
                        });
                    } catch (e) {
                        const message = e && e.message ? e.message : String(e);
                        // Return the error message inside an SVG-like pre tag for display
                        const errorSvg = `<pre class="mermaid-error" style="color: rgba(60, 60, 67, 0.85); font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; white-space: pre-wrap; word-break: break-word;">${message}</pre>`;
                        return JSON.stringify({ error: message, svg: errorSvg });
                    }
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: Bundle.module.resourceURL)
    }
    
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isReady = true
            for continuation in pendingContinuations {
                continuation.resume()
            }
            pendingContinuations.removeAll()
        }
    }
    
    private func waitForReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }
    
    /// Renders the Mermaid code to SVG or fetches it from cache.
    func render(code: String, fontSize: CGFloat) async throws -> MermaidRenderResult {
        let cacheKey = "\(code)_\(fontSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.result
        }
        
        await waitForReady()
        
        let id = "mermaid-diagram-\(UUID().uuidString.lowercased())"
        
        let jsBody = """
        return await renderToSVG(id, code, fontSize);
        """
        
        let jsResult = try await webView.callAsyncJavaScript(
            jsBody,
            arguments: [
                "id": id,
                "code": code,
                "fontSize": fontSize
            ],
            contentWorld: .page
        )
        
        guard let jsonString = jsResult as? String,
              let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let resultDesc = (jsResult != nil) ? String(describing: jsResult!) : "nil"
            throw NSError(domain: "MermaidRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response. jsResult: \(resultDesc)"])
        }
        
        if let errorMsg = dict["error"] as? String {
            if let fallbackSvg = dict["svg"] as? String {
                // Display the error directly as SVG/HTML
                let errResult = MermaidRenderResult(svg: fallbackSvg, width: 300, height: 100)
                return errResult
            } else {
                throw NSError(domain: "MermaidRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
        
        guard let svg = dict["svg"] as? String,
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
            throw NSError(domain: "MermaidRenderer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing SVG or dimensions"])
        }
        
        let renderResult = MermaidRenderResult(svg: svg, width: width, height: height)
        cache.setObject(MermaidRendererCacheBox(result: renderResult), forKey: cacheKey)
        
        return renderResult
    }
}

/// A class wrapper to store value types in NSCache
private final class MermaidRendererCacheBox: NSObject {
    let result: MermaidRenderResult
    init(result: MermaidRenderResult) {
        self.result = result
    }
}
