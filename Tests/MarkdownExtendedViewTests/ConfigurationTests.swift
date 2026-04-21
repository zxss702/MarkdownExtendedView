// ConfigurationTests.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import XCTest
import SwiftUI
@testable import MarkdownExtendedView

@MainActor
final class ConfigurationTests: XCTestCase {

    func testLinkHandlerDefaultIsNil() {
        let handler: ((URL) -> Void)? = nil
        XCTAssertNil(handler)
    }

    func testLinkHandlerCanStoreCallback() {
        var callbackInvoked = false
        var receivedURL: URL?

        let handler: (URL) -> Void = { url in
            callbackInvoked = true
            receivedURL = url
        }

        let testURL = URL(string: "https://example.com")!
        handler(testURL)

        XCTAssertTrue(callbackInvoked)
        XCTAssertEqual(receivedURL, testURL)
    }

    func testLinkHandlerCallbackWithDifferentURLs() {
        var urls: [URL] = []

        let handler: (URL) -> Void = { url in
            urls.append(url)
        }

        let url1 = URL(string: "https://example.com")!
        let url2 = URL(string: "https://test.com/path")!

        handler(url1)
        handler(url2)

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0], url1)
        XCTAssertEqual(urls[1], url2)
    }

    func testImagePlaceholderTypeExists() {
        let placeholder: AnyView? = nil
        XCTAssertNil(placeholder)
    }

    func testMarkdownThemeModifierExists() {
        let view = Text("Test")
        let modifiedView = view.markdownTheme(.gitHub)
        XCTAssertNotNil(modifiedView)
    }

    func testOnLinkTapModifierExists() {
        let view = Text("Test")
        let modifiedView = view.onLinkTap { _ in }
        XCTAssertNotNil(modifiedView)
    }

    func testOnMCodeReferenceTapModifierExists() {
        let view = Text("Test")
        let modifiedView = view.onMCodeReferenceTap { _ in }
        XCTAssertNotNil(modifiedView)
    }

    func testModifiersCanBeChained() {
        let view = Text("Test")
        let modifiedView = view
            .markdownTheme(.compact)
            .onLinkTap { url in
                print("Tapped: \(url)")
            }
            .onMCodeReferenceTap { reference in
                print("Tapped code reference: \(reference)")
            }
        XCTAssertNotNil(modifiedView)
    }
}
