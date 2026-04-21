// CodeReferenceTests.swift
//  MarkdownExtendedViewTests
//
//  Created by OpenAI Codex on 2026-04-21.
//

import XCTest
@testable import MarkdownExtendedView

final class CodeReferenceTests: XCTestCase {

    func testParsesEntireFileReference() {
        let reference = CodeReference("file:///tmp/example.swift")

        XCTAssertEqual(reference, .entire(url: URL(fileURLWithPath: "/tmp/example.swift")))
    }

    func testParsesSingleLineReference() {
        let reference = CodeReference("file:///tmp/example.swift:<12>")

        XCTAssertEqual(reference, .singleLine(url: URL(fileURLWithPath: "/tmp/example.swift"), line: 12))
    }

    func testParsesSingleLineReferenceWithoutAngleBrackets() {
        let reference = CodeReference("file:///tmp/example.swift:12")

        XCTAssertEqual(reference, .singleLine(url: URL(fileURLWithPath: "/tmp/example.swift"), line: 12))
    }

    func testParsesMultiLineReference() {
        let reference = CodeReference("file:///tmp/example.swift:<12>-<18>")

        XCTAssertEqual(reference, .multipleLines(url: URL(fileURLWithPath: "/tmp/example.swift"), start: 12, end: 18))
    }

    func testParsesMultiLineReferenceWithoutAngleBrackets() {
        let reference = CodeReference("file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58")

        XCTAssertEqual(
            reference,
            .multipleLines(
                url: URL(fileURLWithPath: "/Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift"),
                start: 46,
                end: 58
            )
        )
    }

    func testParsesMultipleSelectionsSeparatedByChineseDelimiter() {
        let reference = CodeReference("file:///tmp/a.swift:12-13、16-19")

        XCTAssertEqual(
            reference,
            .selections(
                url: URL(fileURLWithPath: "/tmp/a.swift"),
                ranges: [12...13, 16...19]
            )
        )
    }

    func testParsesMultipleSelectionsSeparatedByComma() {
        let reference = CodeReference("file:///tmp/a.swift:<12>-<13>,<16>-<19>")

        XCTAssertEqual(
            reference,
            .selections(
                url: URL(fileURLWithPath: "/tmp/a.swift"),
                ranges: [12...13, 16...19]
            )
        )
    }

    func testReferenceExposesDisplayMetadata() {
        let reference = CodeReference("file:///tmp/example.swift:<8>-<9>")

        XCTAssertEqual(reference?.fileName, "example.swift")
        XCTAssertEqual(reference?.lineDescription, "Lines 8-9")
        XCTAssertEqual(reference?.url, URL(fileURLWithPath: "/tmp/example.swift"))
    }

    func testSelectionsExposeLineDescription() {
        let reference = CodeReference("file:///tmp/a.swift:12-13、16-19")

        XCTAssertEqual(reference?.lineDescription, "Lines 12-13, 16-19")
    }

    func testParsesMultipleFileReferencesFromOneBlock() {
        let references = parseCodeReferences(from: "file:///tmp/a.swift:12-13、file:///tmp/b.swift:16-19")

        XCTAssertEqual(
            references,
            [
                .multipleLines(url: URL(fileURLWithPath: "/tmp/a.swift"), start: 12, end: 13),
                .multipleLines(url: URL(fileURLWithPath: "/tmp/b.swift"), start: 16, end: 19),
            ]
        )
    }

    func testParsesMultipleFileReferencesSeparatedByNewline() {
        let references = parseCodeReferences(from: """
        file:///tmp/a.swift:12-13
        file:///tmp/b.swift:16-19、file:///tmp/c.swift:20
        """)

        XCTAssertEqual(
            references,
            [
                .multipleLines(url: URL(fileURLWithPath: "/tmp/a.swift"), start: 12, end: 13),
                .multipleLines(url: URL(fileURLWithPath: "/tmp/b.swift"), start: 16, end: 19),
                .singleLine(url: URL(fileURLWithPath: "/tmp/c.swift"), line: 20),
            ]
        )
    }

    func testParsesFileReferencesWrappedInInlineCodeLines() {
        let references = [
            parseCodeReferences(from: "file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58"),
            parseCodeReferences(from: "file:///tmp/a.swift:12"),
        ]

        XCTAssertEqual(
            references,
            [
                [.multipleLines(
                    url: URL(fileURLWithPath: "/Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift"),
                    start: 46,
                    end: 58
                )],
                [.singleLine(url: URL(fileURLWithPath: "/tmp/a.swift"), line: 12)],
            ]
        )
    }

    func testInvalidReferenceReturnsNil() {
        XCTAssertNil(CodeReference("print(\"hello\")"))
        XCTAssertNil(CodeReference("https://example.com/file.swift"))
        XCTAssertNil(CodeReference("file:///tmp/example.swift:abc"))
        XCTAssertNil(CodeReference("file:///tmp/example.swift:12-"))
    }
}
