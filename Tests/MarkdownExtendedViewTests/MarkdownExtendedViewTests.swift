import XCTest
@testable import MarkdownExtendedView

final class MarkdownExtendedViewTests: XCTestCase {

    func testBasicMarkdownParsing() throws {
        // Basic test to verify the module compiles and links
        let content = "# Hello World"
        XCTAssertFalse(content.isEmpty)
    }

    func testLaTeXDelimiterDetection() throws {
        let inlineLatex = "The formula $x^2$ is simple"
        XCTAssertTrue(inlineLatex.contains("$"))

        let displayLatex = "$$E = mc^2$$"
        XCTAssertTrue(displayLatex.contains("$$"))
    }

    func testCJKWrappingGroupsCharactersIntoBoundedRuns() throws {
        let units = MarkdownInlineTextWrapping.units(in: "一二三四五六七八九十")

        XCTAssertEqual(units, ["一二三四五六七八", "九十"])
    }

    @MainActor
    func testWidthAwareSnapshotEstimatesWrappedParagraphHeight() async throws {
        let content = """
        它像这套 SwiftUI 应用的中枢神经。NavigationObserver 是一个运行在主线程、可被界面观察的全局状态对象，专门替 UI 统一保管工作区状态：当前项目目录、AI 通信记录、侧栏与编辑器状态、搜索、网页和 AI 对话。
        """
        let theme = MarkdownTheme.default
        let narrow = await MarkdownRenderSnapshot.parse(content, width: 180, theme: theme)
        let wide = await MarkdownRenderSnapshot.parse(content, width: 1200, theme: theme)

        let narrowHeight = try XCTUnwrap(narrow.estimatedHeight)
        let wideHeight = try XCTUnwrap(wide.estimatedHeight)

        XCTAssertGreaterThan(narrowHeight, wideHeight)
        XCTAssertGreaterThan(narrowHeight, theme.bodyFont.markdownLineHeight * 2)
    }

    @MainActor
    func testWidthAwareSnapshotWrapsParagraphsWithInlineCodeReferences() async throws {
        let content = """
        它像这套 SwiftUI 应用的中枢神经，专门替 UI 统一保管工作区状态：当前项目目录、AI 通信记录、侧栏与编辑器状态、搜索、网页和 AI 对话。`file:///tmp/NavigationObserver.swift:12` 再往里看，它管得很复杂，但脉络很清。
        """
        let theme = MarkdownTheme.default
        let narrow = await MarkdownRenderSnapshot.parse(content, width: 220, theme: theme)
        let wide = await MarkdownRenderSnapshot.parse(content, width: 1400, theme: theme)

        let narrowHeight = try XCTUnwrap(narrow.estimatedHeight)
        let wideHeight = try XCTUnwrap(wide.estimatedHeight)

        XCTAssertGreaterThan(narrowHeight, wideHeight)
        XCTAssertGreaterThan(narrowHeight, theme.bodyFont.markdownLineHeight * 3)
        XCTAssertGreaterThan(
            narrowHeight,
            theme.bodyFont.markdownLineHeight * 3 + theme.paragraphSpacing * 2
        )
    }

    @MainActor
    func testReconciledSnapshotKeepsUnchangedBlockIDsAfterMiddleInsertion() {
        let previous = MarkdownRenderSnapshot.parse("""
        # Title

        First

        Second
        """)
        let next = MarkdownRenderSnapshot.parse("""
        # Title

        Inserted

        First

        Second
        """)
        .reusingBlockIdentities(from: previous, mode: .exact)

        XCTAssertEqual(next.blocks[0].id, previous.blocks[0].id)
        XCTAssertEqual(next.blocks[2].id, previous.blocks[1].id)
        XCTAssertEqual(next.blocks[3].id, previous.blocks[2].id)
    }

    @MainActor
    func testStreamingReconcileReusesTailParagraphID() {
        let previous = MarkdownRenderSnapshot.parse("""
        Intro

        Streaming text
        """)
        let next = MarkdownRenderSnapshot.parse("""
        Intro

        Streaming text continues
        """)
        .reusingBlockIdentities(from: previous, mode: .streaming)

        XCTAssertEqual(next.blocks[0].id, previous.blocks[0].id)
        XCTAssertEqual(next.blocks[1].id, previous.blocks[1].id)
    }

    @MainActor
    func testStreamingReconcileReusesTailCodeBlockID() {
        let previous = MarkdownRenderSnapshot.parse("""
        ```swift
        let value = 1
        ```
        """)
        let next = MarkdownRenderSnapshot.parse("""
        ```swift
        let value = 1
        print(value)
        ```
        """)
        .reusingBlockIdentities(from: previous, mode: .streaming)

        XCTAssertEqual(next.blocks[0].id, previous.blocks[0].id)
    }

    @MainActor
    func testReconciledSnapshotKeepsDuplicateBlockIDsUnique() {
        let previous = MarkdownRenderSnapshot.parse("Repeat")
        let next = MarkdownRenderSnapshot.parse("""
        Repeat

        Repeat
        """)
        .reusingBlockIdentities(from: previous, mode: .exact)
        let ids = next.blocks.map(\.id)

        XCTAssertEqual(ids.first, previous.blocks.first?.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    @MainActor
    func testSnapshotClassifiesTextAndNonTextAnimationKinds() {
        let snapshot = MarkdownRenderSnapshot.parse("""
        Text

        ```swift
        print("hello")
        ```

        ```mermaid
        graph TD
            A --> B
        ```

        ![Alt](https://example.com/image.png)

        | A |
        | - |
        | B |

        $$x^2$$
        """)
        let kinds = snapshot.blocks.map(\.animationKind)

        XCTAssertEqual(kinds, [
            .text,
            .text,
            .nonText,
            .nonText,
            .nonText,
            .nonText,
        ])
    }
}
