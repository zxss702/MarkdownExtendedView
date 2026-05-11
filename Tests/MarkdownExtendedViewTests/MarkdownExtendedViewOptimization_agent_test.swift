import XCTest
@testable import MarkdownExtendedView
import Markdown

final class MarkdownExtendedViewOptimizationAgentTests: XCTestCase {

    // MARK: - Feature Mask Tests

    @MainActor
    func test_agent_featureMaskDetectsLinks() async throws {
        let content = "Check this [link](https://example.com) out."
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        let paragraph = snapshot.blocks.first!
        let features = paragraph.features
        XCTAssertTrue(features.contains(.hasLinks))
    }

    @MainActor
    func test_agent_featureMaskDetectsImages() async throws {
        let content = "Here is ![alt](image.png) an image."
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        let paragraph = snapshot.blocks.first!
        let features = paragraph.features
        XCTAssertTrue(features.contains(.hasImages))
    }

    @MainActor
    func test_agent_featureMaskDetectsLaTeX() async throws {
        let content = "The formula $x^2 + y^2 = z^2$ is inline."
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        let paragraph = snapshot.blocks.first!
        let features = paragraph.features
        XCTAssertTrue(features.contains(.hasLaTeX))
        // LaTeX segments are now computed inline at render time (no longer pre-cached)
    }

    @MainActor
    func test_agent_featureMaskDetectsMCodeReferences() async throws {
        let content = "See `file:///tmp/test.swift:1-5` for reference."
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        let paragraph = snapshot.blocks.first!
        let features = paragraph.features
        XCTAssertTrue(features.contains(.hasMCodeReferences))
    }

    // MARK: - Code Highlight Precomputation Test

    @MainActor
    func test_agent_codeHighlightPrecomputed() async throws {
        let content = """
        ```swift
        let x = 42
        func hello() {
            print("world")
        }
        ```
        """
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        guard let codeBlockNode = snapshot.blocks.first,
              codeBlockNode.markup is CodeBlock else {
            XCTFail("Expected a CodeBlock")
            return
        }
        let highlights = snapshot.codeHighlights[codeBlockNode.id]
        XCTAssertNotNil(highlights, "Code highlights should be precomputed during async parse")
        XCTAssertGreaterThan(highlights!.count, 0, "Should have at least one line of highlighted tokens")
    }

    // MARK: - Height Estimation Removal Test

    @MainActor
    func test_agent_heightEstimationRemoved() async throws {
        let content = """
        This is a paragraph that should be parsed.
        """
        let snapshot = await MarkdownRenderSnapshot.parse(content)
        // After height estimation removal, parse should still return blocks
        XCTAssertFalse(snapshot.blocks.isEmpty)
        // No estimatedHeight field exists anymore — this test just verifies parsing works
    }

    // MARK: - Cache Key Hash Test

    func test_agent_cacheKeyUsesHash() {
        let longCode = String(repeating: "abcdefghij", count: 1000) // 10000 chars
        let key = HighlightedCodeView.cacheKey(for: longCode, language: "swift")
        let originalStyleKeyLength = "swift::\(longCode)".count // ~10006 chars
        // The hashed key should be significantly shorter than the original full-code key
        XCTAssertLessThan(key.count, originalStyleKeyLength - 9000,
            "Cache key should use hash, not full code string. Key: \(key.prefix(50))... (len: \(key.count))")
    }
}
