// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownExtendedView",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MarkdownExtendedView",
            targets: ["MarkdownExtendedView"]
        ),
    ],
    dependencies: [
        // Apple's official Markdown parser (CommonMark + GFM extensions)
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/lukilabs/elk-swift", from: "1.0.2")
    ],
    targets: [
        .target(
            name: "BeautifulMermaid",
            dependencies: [
                .product(name: "ElkSwift", package: "elk-swift")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MarkdownExtendedView",
            dependencies: [
                "BeautifulMermaid",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            resources: [
                .copy("SwiftMath/mathFonts.bundle")
            ]
        ),
        .testTarget(
            name: "MarkdownExtendedViewTests",
            dependencies: ["MarkdownExtendedView"]
        ),
    ]
)
