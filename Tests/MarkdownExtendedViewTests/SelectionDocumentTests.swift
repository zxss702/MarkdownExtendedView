import XCTest
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
}
