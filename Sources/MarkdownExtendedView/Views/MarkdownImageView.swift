// MarkdownImageView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License
//

import SwiftUI
import Markdown

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A view that displays an image from a flattened `MDImage` value.
struct MarkdownImageView: View {

    let image: MDImage
    let theme: MarkdownTheme
    let baseURL: URL?

    var body: some View {
        content
            .makeCanSelectable(
                isBlock: true,
                blockText: "[\(image.altText)]",
                richImage: loadedPlatformImage
            )
            .contextMenu { imageMenu }
    }

    @ViewBuilder
    private var content: some View {
        if let url = resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: MarkdownLayoutMetrics.fixedImageSize.width,
                            height: MarkdownLayoutMetrics.fixedImageSize.height
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(image.altText)
                default:
                    Color.white
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(
                            width: MarkdownLayoutMetrics.fixedImageSize.width,
                            height: MarkdownLayoutMetrics.fixedImageSize.height
                        )
                }
            }
            .frame(
                width: MarkdownLayoutMetrics.fixedImageSize.width,
                height: MarkdownLayoutMetrics.fixedImageSize.height
            )
        } else {
            altTextView
        }
    }

    /// The alt text fallback when images are disabled or unavailable.
    private var altTextView: some View {
        Text("[\(image.altText)]")
            .font(theme.bodySwiftUIFont)
            .foregroundColor(theme.secondaryTextColor)
    }

    /// Resolves the image URL from the source string.
    private var resolvedURL: URL? {
        guard let source = image.source else { return nil }

        // Try to create URL directly
        if let url = URL(string: source) {
            // If it's a relative URL and we have a base URL, resolve it
            if url.scheme == nil, let base = baseURL {
                return URL(string: source, relativeTo: base)?.absoluteURL
            }
            return url
        }

        return nil
    }

    /// The already-fetched image for rich/"拷贝为图像" copies — resolved
    /// synchronously from `URLCache` (the same store `AsyncImage` reads)
    /// or from disk for file URLs. No network access.
    private var loadedPlatformImage: MTImage? {
        guard let url = resolvedURL else { return nil }

        if
            let response = URLCache.shared.cachedResponse(for: URLRequest(url: url)),
            let image = MTImage(data: response.data)
        {
            return image
        }

        if url.isFileURL {
            #if canImport(AppKit)
            return NSImage(contentsOf: url)
            #elseif canImport(UIKit)
            if let data = try? Data(contentsOf: url) {
                return UIImage(data: data)
            }
            #endif
        }

        return nil
    }

    @ViewBuilder
    private var imageMenu: some View {
        Button("拷贝为图像") {
            if let platformImage = loadedPlatformImage {
                MarkdownCopy.image(platformImage)
            }
        }
        .disabled(loadedPlatformImage == nil)
        Button("拷贝为 Markdown") {
            MarkdownCopy.text("![\(image.altText)](\(image.source ?? ""))")
        }
    }
}
