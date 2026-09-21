import XCTest
@testable import MarkdownExtendedView
import Markdown

final class MarkdownExtendedViewOptimizationAgentTests: XCTestCase {

    // MARK: - Flattened inline content tests

    @MainActor
    func test_agent_flattenDetectsLinks() throws {
        let content = "Check this [link](https://example.com) out."
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        guard case .text(let attributed)? = blocks.first?.content else {
            return XCTFail("Expected a text block")
        }
        let link = attributed.runs.first(where: { $0.link != nil })?.link
        XCTAssertEqual(link?.absoluteString, "https://example.com")
    }

    @MainActor
    func test_agent_flattenSplitsImagesIntoSiblingBlocks() throws {
        let content = "Here is ![alt](image.png) an image."
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        XCTAssertEqual(blocks.count, 3)
        guard case .text = blocks[0].content,
              case .image(let image) = blocks[1].content,
              case .text = blocks[2].content else {
            return XCTFail("Expected text | image | text, got \(blocks.map(\.kind))")
        }
        XCTAssertEqual(image.altText, "alt")
        XCTAssertEqual(image.source, "image.png")
    }

    @MainActor
    func test_agent_flattenDetectsInlineLaTeX() throws {
        let content = "The formula $x^2 + y^2 = z^2$ is inline."
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        guard case .text(let attributed)? = blocks.first?.content else {
            return XCTFail("Expected a text block")
        }
        // The formula is either an embedded image marker, or (when
        // typesetting fails) its literal `$..$` source — never dropped.
        let hasImage = attributed.runs.contains {
            $0.attributes[MarkdownInlineImageKey.self] != nil
        }
        let text = String(attributed.characters)
        if !hasImage {
            XCTAssertTrue(text.contains("$x^2 + y^2 = z^2$"))
        }
        let mappings = Self.mappings(of: attributed)
        let latexPayloads = mappings.filter { $0.char.hasPrefix("$") }
        XCTAssertEqual(latexPayloads.count, 1)
        XCTAssertEqual(latexPayloads.first?.char, "$x^2 + y^2 = z^2$")
    }

    @MainActor
    func test_agent_flattenSplitsBlockLaTeXIntoSiblingBlock() throws {
        let content = "Before.\n$$E = mc^2$$\nAfter."
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        XCTAssertTrue(blocks.contains {
            if case .latexBlock(let source) = $0.content { return source.contains("E = mc^2") }
            return false
        })
    }

    @MainActor
    func test_agent_codeReferenceStaysInline() throws {
        let content = "See `/tmp/test.swift:1-5` for reference."
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        // No line break: the reference is icon + filename inside the text.
        XCTAssertEqual(blocks.count, 1)
        guard case .text(let attributed)? = blocks.first?.content else {
            return XCTFail("Expected a single text block")
        }
        let link = attributed.runs.first(where: { $0.link != nil })?.link
        XCTAssertTrue(link?.isFileURL == true, "code ref label should link to the file URL")
        XCTAssertTrue(
            link?.absoluteString.contains(":1-5") == true,
            "link should carry the line range, got \(link?.absoluteString ?? "nil")"
        )
        XCTAssertTrue(String(attributed.characters).contains("test.swift:1-5"))
        // The icon occupies one glyph as a baked image marker.
        XCTAssertTrue(attributed.runs.contains {
            $0.attributes[MarkdownInlineImageKey.self] != nil
        })
        // Icon + label share one selection group → atomic selection;
        // the first member carries the canonical POSIX copy payload.
        // Mappings are run-length encoded: icon run (1 glyph) + one
        // label run covering every label glyph.
        let grouped = Self.mappings(of: attributed).filter { $0.group != nil }
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.first?.char, "`/tmp/test.swift:<1>-<5>`")
        XCTAssertEqual(grouped.first?.glyphCount, 1)
        XCTAssertEqual(grouped.last?.char, "")
        XCTAssertEqual(grouped.last?.glyphCount, "test.swift:1-5".count)
        // Link + rich payloads ride along for hover/copy-link/rich copy.
        XCTAssertTrue(grouped.allSatisfy { $0.link?.hasPrefix("file://") == true })
        XCTAssertNotNil(grouped.first?.richImage)
        XCTAssertEqual(grouped.first?.richText, "test.swift:1-5")
    }

    @MainActor
    func test_agent_codeReferenceInsideTableStaysInline() throws {
        let content = """
        | Name | Ref |
        |---|---|
        | a | `/tmp/x.swift:1` |
        """
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        guard case .table(let table)? = blocks.first?.content else {
            return XCTFail("Expected a table")
        }
        let cell = table.rows[0][1]
        let text = String(cell.characters)
        XCTAssertTrue(text.contains("x.swift:1"), "code refs render inline inside cells, got \(text)")
        XCTAssertTrue(cell.runs.contains { $0.link?.isFileURL == true })
    }

    /// The baked link must parse back into the same code reference.
    @MainActor
    func test_agent_codeReferenceLinkRoundTrips() throws {
        let blocks = MarkdownFlattener.flatten(
            "`/tmp/sub dir/a.swift:12-20`",
            baseURL: nil,
            previousBlocks: []
        )
        guard case .text(let attributed)? = blocks.first?.content,
              let url = attributed.runs.first(where: { $0.link != nil })?.link else {
            return XCTFail("Expected a linked code reference")
        }
        let parsed = MCodeReference(url.absoluteString)
        XCTAssertNotNil(parsed, "absoluteString \(url.absoluteString) must parse back")
        XCTAssertEqual(parsed?.lineRanges, [12...20])
        XCTAssertEqual(parsed?.url.path(percentEncoded: false), "/tmp/sub dir/a.swift")
    }

    // MARK: - Code highlight precomputation test

    @MainActor
    func test_agent_codeHighlightPrecomputed() throws {
        let content = """
        ```swift
        let x = 42
        func hello() {
            print("world")
        }
        ```
        """
        let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        guard case .codeBlock(let codeBlock)? = blocks.first?.content else {
            return XCTFail("Expected a codeBlock")
        }
        XCTAssertFalse(codeBlock.lines.isEmpty, "Code lines should be tokenized during flattening")
        XCTAssertGreaterThan(codeBlock.lines.count, 0)
    }

    // MARK: - Streaming id stability

    @MainActor
    func test_agent_blockIDsStayStableAcrossStreaming() throws {
        let prefix = "Hello **world**\n\n```swift\nlet a = 1\n```"
        let extended = prefix + "\n\nNew paragraph."

        let first = MarkdownFlattener.flatten(prefix, baseURL: nil, previousBlocks: [])
        let second = MarkdownFlattener.flatten(extended, baseURL: nil, previousBlocks: first)

        XCTAssertEqual(first.count + 1, second.count)
        XCTAssertEqual(first[0].id, second[0].id, "Text block id should survive append")
        XCTAssertEqual(first[1].id, second[1].id, "Code block id should survive append")
    }

    @MainActor
    func test_agent_inlineMappingsCoverEveryGlyph() throws {
        let blocks = MarkdownFlattener.flatten("Hello **世界** ok", baseURL: nil, previousBlocks: [])
        guard case .text(let attributed)? = blocks.first?.content else {
            return XCTFail("Expected a text block")
        }
        // Run-length encoded: far fewer entries than characters, but
        // the covered glyph total and the joined text are identical.
        let mappings = Self.mappings(of: attributed)
        let glyphTotal = mappings.reduce(0) { $0 + ($1.isLineBreak ? 0 : $1.glyphCount) }
        XCTAssertEqual(glyphTotal, attributed.characters.count)
        XCTAssertLessThan(mappings.count, attributed.characters.count)
        XCTAssertEqual(mappings.map(\.char).joined(), String(attributed.characters))
    }

    // MARK: - Benchmarks

    @MainActor
    func test_agent_flattenBenchmark() throws {
        let paragraph = String(repeating: "This is a sentence with **bold** and `code` and [a link](https://x.com). ", count: 100)
        let content = (0..<20).map { "\(paragraph)\n\n```swift\nlet x = \($0)\n```\n\n" }.joined()
        measure {
            _ = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        }
    }

    @MainActor
    func test_agent_flattenLongTextBenchmark() throws {
        let content = String(repeating: "word ", count: 2000) + "`code` tail"
        measure {
            _ = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
        }
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

    // MARK: - Helpers

    private static func mappings(
        of attributed: AttributedString
    ) -> [GlobalSelectionCache.CharacterMapping] {
        attributed.selectionMappings ?? []
    }
}
