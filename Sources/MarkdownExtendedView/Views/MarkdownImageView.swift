// MarkdownImageView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI
import Markdown

/// A view that displays an image from a markdown Image node.
struct MarkdownImageView: View {

    let image: Markdown.Image
    let theme: MarkdownTheme
    let baseURL: URL?
    
    var body: some View {
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
                        .accessibilityLabel(image.plainText)
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
        Text("[\(image.plainText)]")
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
}
