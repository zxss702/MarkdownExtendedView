// SafariView.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

#if canImport(UIKit)
import SwiftUI
import SafariServices

/// A SwiftUI wrapper for SFSafariViewController to display web content in-app.
///
/// This view is used internally by MarkdownView when the `.links` feature is enabled
/// to open links in an in-app browser rather than switching to Safari.
struct SafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safariViewController = SFSafariViewController(url: url, configuration: configuration)
        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}
#endif
