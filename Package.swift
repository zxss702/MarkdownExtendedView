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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main")
    ],
    targets: [
        .target(
            name: "MarkdownExtendedView",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            resources: [
                .process("Views/mermaid.js"),
                .copy("SwiftMath/mathFonts.bundle")
            ]
        ),
        .testTarget(
            name: "MarkdownExtendedViewTests",
            dependencies: ["MarkdownExtendedView"]
        ),
    ]
)
