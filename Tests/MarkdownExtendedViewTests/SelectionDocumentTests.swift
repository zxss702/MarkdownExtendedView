import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import MarkdownExtendedView

final class SelectionDocumentTests: XCTestCase {

    func testSelectionLayoutSnapshotKeyRejectsNonFiniteFrame() {
        let frame = CGRect(x: CGFloat.infinity, y: 0, width: 12, height: 16)

        XCTAssertNil(SelectionLayoutSnapshotKey(text: "Hello", frame: frame))
    }

    func testPlainTextAddsLineBreakBetweenSeparatedSections() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "HelloWorld"),
            sections: [
                .init(range: 0..<5, frame: CGRect(x: 0, y: 0, width: 40, height: 12)),
                .init(range: 5..<10, frame: CGRect(x: 0, y: 24, width: 40, height: 12))
            ],
            lines: [
                .init(rect: CGRect(x: 0, y: 0, width: 40, height: 12), sliceRange: 0..<1),
                .init(rect: CGRect(x: 0, y: 24, width: 40, height: 12), sliceRange: 1..<2)
            ],
            slices: [
                .init(range: 0..<5, rect: CGRect(x: 0, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 5..<10, rect: CGRect(x: 0, y: 24, width: 40, height: 12), lineIndex: 1, layoutDirection: .leftToRight)
            ]
        )

        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: 10, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "Hello\nWorld")
    }

    func testSelectionRectsCoverMultipleLines() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "HelloWorld"),
            sections: [
                .init(range: 0..<5, frame: CGRect(x: 0, y: 0, width: 40, height: 12)),
                .init(range: 5..<10, frame: CGRect(x: 0, y: 24, width: 40, height: 12))
            ],
            lines: [
                .init(rect: CGRect(x: 0, y: 0, width: 40, height: 12), sliceRange: 0..<1),
                .init(rect: CGRect(x: 0, y: 24, width: 40, height: 12), sliceRange: 1..<2)
            ],
            slices: [
                .init(range: 0..<5, rect: CGRect(x: 0, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 5..<10, rect: CGRect(x: 0, y: 24, width: 40, height: 12), lineIndex: 1, layoutDirection: .leftToRight)
            ]
        )

        let rects = document.selectionRects(
            for: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: 10, affinity: .upstream)
            )
        )

        XCTAssertEqual(rects.count, 2)
        XCTAssertTrue(rects[0].containsStart)
        XCTAssertTrue(rects[1].containsEnd)
        XCTAssertEqual(rects[0].rect, CGRect(x: 0, y: 0, width: 40, height: 12))
        XCTAssertEqual(rects[1].rect, CGRect(x: 0, y: 24, width: 40, height: 12))
    }

    func testPlainTextDoesNotInsertLineBreakForInlineSections() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "HelloWorld"),
            sections: [
                .init(range: 0..<5, frame: CGRect(x: 0, y: 0, width: 40, height: 12)),
                .init(range: 5..<10, frame: CGRect(x: 48, y: 0, width: 40, height: 12))
            ],
            lines: [
                .init(rect: CGRect(x: 0, y: 0, width: 88, height: 12), sliceRange: 0..<2)
            ],
            slices: [
                .init(range: 0..<5, rect: CGRect(x: 0, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 5..<10, rect: CGRect(x: 48, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight)
            ]
        )

        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: 10, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "HelloWorld")
    }

    // MARK: - Blockquote line prefix

    func testPlainTextAppliesLinePrefixToEachCopiedLine() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "first\nsecond"),
            sections: [
                .init(
                    range: 0..<12,
                    frame: CGRect(x: 16, y: 0, width: 80, height: 28),
                    linePrefix: "> "
                )
            ],
            lines: [
                .init(rect: CGRect(x: 16, y: 0, width: 80, height: 12), sliceRange: 0..<1),
                .init(rect: CGRect(x: 16, y: 14, width: 80, height: 12), sliceRange: 1..<2)
            ],
            slices: [
                .init(range: 0..<6, rect: CGRect(x: 16, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 6..<12, rect: CGRect(x: 16, y: 14, width: 50, height: 12), lineIndex: 1, layoutDirection: .leftToRight)
            ]
        )

        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: 12, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "> first\n> second")
    }

    func testPlainTextPartialQuoteSelectionStillPrefixes() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "quoted"),
            sections: [
                .init(
                    range: 0..<6,
                    frame: CGRect(x: 16, y: 0, width: 40, height: 12),
                    linePrefix: "> "
                )
            ],
            lines: [
                .init(rect: CGRect(x: 16, y: 0, width: 40, height: 12), sliceRange: 0..<1)
            ],
            slices: [
                .init(range: 0..<6, rect: CGRect(x: 16, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight)
            ]
        )

        // Select only "uote" — the prefix still applies to the partial line.
        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 1, affinity: .downstream),
                end: SelectionPosition(offset: 5, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "> uote")
    }

    // MARK: - Atomic snapshots

    func testAtomicAnchorSnapshotProducesSingleSlice() {
        let anchor = ResolvedSelectionAnchor(
            rect: CGRect(x: 10, y: 20, width: 60, height: 30),
            isBlock: true,
            blockText: "$x^2$",
            linePrefix: nil
        )
        let snapshot = SelectionLayoutSnapshot(anchor: anchor)

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.attributedString.string, "$x^2$")
        XCTAssertEqual(snapshot?.lines.count, 1)
        XCTAssertEqual(snapshot?.lines.first?.slices.count, 1)
        XCTAssertEqual(snapshot?.lines.first?.slices.first?.characterRange, 0..<5)
    }

    func testDocumentCopyFromAtomicSliceKeepsFullPayload() {
        let anchor = ResolvedSelectionAnchor(
            rect: CGRect(x: 0, y: 0, width: 60, height: 30),
            isBlock: true,
            blockText: "[image alt]",
            linePrefix: nil
        )
        guard let snapshot = SelectionLayoutSnapshot(anchor: anchor) else {
            return XCTFail("Snapshot should exist")
        }

        let document = SelectionDocumentBuilder.build(from: [snapshot])
        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: document.textLength, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "[image alt]")
    }

    // MARK: - No phantom trailing content

    func testPlainTextDoesNotAddTrailingNewlineAtSectionBoundary() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "AB"),
            sections: [
                .init(range: 0..<1, frame: CGRect(x: 0, y: 0, width: 40, height: 12)),
                .init(range: 1..<2, frame: CGRect(x: 0, y: 24, width: 40, height: 12))
            ],
            lines: [
                .init(rect: CGRect(x: 0, y: 0, width: 40, height: 12), sliceRange: 0..<1),
                .init(rect: CGRect(x: 0, y: 24, width: 40, height: 12), sliceRange: 1..<2)
            ],
            slices: [
                .init(range: 0..<1, rect: CGRect(x: 0, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 1..<2, rect: CGRect(x: 0, y: 24, width: 40, height: 12), lineIndex: 1, layoutDirection: .leftToRight)
            ]
        )

        // Selecting only the first section yields "A" — no trailing "\n".
        let text = document.plainText(
            in: SelectionRange(
                start: SelectionPosition(offset: 0, affinity: .downstream),
                end: SelectionPosition(offset: 1, affinity: .upstream)
            )
        )

        XCTAssertEqual(text, "A")
    }

    // MARK: - Link hit-testing

    func testLinkHitTestFindsLinkedSliceOnly() {
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "click here"),
            sections: [.init(range: 0..<10, frame: CGRect(x: 0, y: 0, width: 80, height: 12))],
            lines: [.init(rect: CGRect(x: 0, y: 0, width: 80, height: 12), sliceRange: 0..<2)],
            slices: [
                .init(range: 0..<5, rect: CGRect(x: 0, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight, link: "https://example.com"),
                .init(range: 5..<10, rect: CGRect(x: 40, y: 0, width: 40, height: 12), lineIndex: 0, layoutDirection: .leftToRight)
            ]
        )

        XCTAssertEqual(document.link(at: CGPoint(x: 20, y: 6)), "https://example.com")
        XCTAssertNil(document.link(at: CGPoint(x: 60, y: 6)))
        XCTAssertNil(document.link(at: CGPoint(x: -40, y: -40)))
    }

    // MARK: - Rich ("含图像") copy

    #if canImport(AppKit)
    func testRichTextEmbedsImageForFullySelectedRichSlice() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "ab$$x$$cd"),
            sections: [.init(range: 0..<9, frame: CGRect(x: 0, y: 0, width: 90, height: 12))],
            lines: [.init(rect: CGRect(x: 0, y: 0, width: 90, height: 12), sliceRange: 0..<3)],
            slices: [
                .init(range: 0..<2, rect: CGRect(x: 0, y: 0, width: 20, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(range: 2..<7, rect: CGRect(x: 20, y: 0, width: 50, height: 12), lineIndex: 0, layoutDirection: .leftToRight, rich: .image(image)),
                .init(range: 7..<9, rect: CGRect(x: 70, y: 0, width: 20, height: 12), lineIndex: 0, layoutDirection: .leftToRight)
            ]
        )

        let full = SelectionRange(
            start: SelectionPosition(offset: 0, affinity: .downstream),
            end: SelectionPosition(offset: 9, affinity: .upstream)
        )
        let rich = document.richText(in: full)
        // "ab" + image attachment (U+FFFC) + "cd"
        XCTAssertEqual(rich.string, "ab\u{FFFC}cd")
        XCTAssertNotNil(
            rich.attribute(.attachment, at: 2, effectiveRange: nil),
            "rich slice should embed an NSTextAttachment"
        )

        // Plain copy still yields the source payload.
        XCTAssertEqual(document.plainText(in: full), "ab$$x$$cd")

        // A PARTIAL selection of the rich slice degrades to plain text.
        let partial = SelectionRange(
            start: SelectionPosition(offset: 0, affinity: .downstream),
            end: SelectionPosition(offset: 4, affinity: .upstream)
        )
        let partialRich = document.richText(in: partial)
        XCTAssertEqual(partialRich.string, "ab$$")
    }

    func testRichTextCodeRefEmitsIconAndTintedLabel() {
        let icon = NSImage(size: NSSize(width: 12, height: 12))
        let document = SelectionDocument(
            attributedString: NSAttributedString(string: "see `/tmp/a.swift:<12>`"),
            sections: [.init(range: 0..<22, frame: CGRect(x: 0, y: 0, width: 200, height: 12))],
            lines: [.init(rect: CGRect(x: 0, y: 0, width: 200, height: 12), sliceRange: 0..<2)],
            slices: [
                .init(range: 0..<4, rect: CGRect(x: 0, y: 0, width: 30, height: 12), lineIndex: 0, layoutDirection: .leftToRight),
                .init(
                    range: 4..<22,
                    rect: CGRect(x: 30, y: 0, width: 170, height: 12),
                    lineIndex: 0,
                    layoutDirection: .leftToRight,
                    link: "file:///tmp/a.swift:12",
                    rich: .codeRef(icon: icon, label: "a.swift:12", link: "file:///tmp/a.swift:12")
                )
            ]
        )

        let full = SelectionRange(
            start: SelectionPosition(offset: 0, affinity: .downstream),
            end: SelectionPosition(offset: 22, affinity: .upstream)
        )
        let rich = document.richText(in: full)

        // "see " + icon attachment + tinted label.
        XCTAssertEqual(rich.string, "see \u{FFFC}a.swift:12")
        XCTAssertNotNil(rich.attribute(.attachment, at: 4, effectiveRange: nil))
        let color = rich.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, .systemBlue)
        let link = rich.attribute(.link, at: 5, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "file:///tmp/a.swift:12")
    }
    #endif
}
