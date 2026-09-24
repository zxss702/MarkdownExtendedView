import XCTest
import SwiftUI
@testable import MarkdownExtendedView

#if canImport(AppKit)
import AppKit

/// Diagnostics for the selection extraction pipeline: does
/// `Text.LayoutKey` deliver layouts, does the baked mappings attribute
/// survive into layout runs, and does the Core Text reflection fallback
/// produce real character ranges on this platform?
private final class LayoutBox {
    var layouts: Text.LayoutKey.Value = []
}

final class SelectionReflectionTests: XCTestCase {

    @MainActor
    private func captureLayouts<V: View>(
        _ view: V,
        timeout: TimeInterval = 2
    ) -> Text.LayoutKey.Value {
        let box = LayoutBox()

        let hosted = view.onPreferenceChange(Text.LayoutKey.self) { layouts in
            box.layouts = layouts
        }
        let hosting = NSHostingView(rootView: AnyView(hosted))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        let deadline = Date().addingTimeInterval(timeout)
        while box.layouts.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }
        window.orderOut(nil)
        return box.layouts
    }

    /// `Text.LayoutKey` must deliver laid-out text for selection to work.
    @MainActor
    func test_layoutKeyDeliversLayouts() throws {
        let layouts = captureLayouts(Text("Hello selection"))
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")
        XCTAssertGreaterThan(layouts.first?.layout.reduce(0) { $0 + $1.count } ?? 0, 0)
    }

    /// The baked mappings attribute must reach `Text.Layout` runs — that
    /// is the reflection-free extraction path markdown text relies on.
    @MainActor
    func test_mappingsAttributeSurvivesIntoLayout() throws {
        let mappings = "Hello".enumerated().map {
            GlobalSelectionCache.CharacterMapping(char: Substring(String($0.element)))
        }
        var attr = AttributedString("Hello")
        var container = AttributeContainer()
        container[MarkdownBakedMappingsKey.self] = mappings
        attr.mergeAttributes(container)
        // Same path as `InlineContentView`: the string carries the
        // payload; the view re-publishes it as a `TextAttribute`.
        var text = Text(attr)
        if let baked = attr.selectionMappings {
            text = text.customAttribute(MarkdownBlockMappingsAttribute(mappings: baked))
        }

        let layouts = captureLayouts(text)
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        var found = false
        for proxy in layouts {
            for line in proxy.layout {
                for run in line where run[MarkdownBlockMappingsAttribute.self] != nil {
                    found = true
                }
            }
        }
        XCTAssertTrue(found, "MarkdownBlockMappingsAttribute did not reach Text.Layout runs")
    }

    /// CTRun reflection must yield per-glyph character ranges — the
    /// fallback path that external (non-markdown) Text relies on.
    @MainActor
    func test_reflectionProducesCharacterRanges() throws {
        let layouts = captureLayouts(Text("External text"))
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        var totalRanges = 0
        var fragments = 0
        for proxy in layouts {
            for line in proxy.layout {
                if line.selectionLineFragment != nil { fragments += 1 }
                for run in line {
                    totalRanges += run.selectionCharacterRanges.count
                }
            }
        }
        XCTAssertGreaterThan(fragments, 0, "NSTextLineFragment reflection failed")
        XCTAssertGreaterThan(totalRanges, 0, "CTRun character-range reflection failed")
    }

    /// `Text` does NOT draw foreign `NSTextAttachment`s — measured on
    /// this platform a 40pt attachment occupies only the default ~8pt
    /// FFFC slot. Inline images therefore go through `Text(Image)`
    /// concatenation, which produces a real glyph slot. This test pins
    /// that contract.
    @MainActor
    func test_interpolatedImageOccupiesGlyphSlot() throws {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        image.unlockFocus()

        let layouts = captureLayouts(
            Text("a") + Text(Image(nsImage: image)) + Text("b")
        )
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        var widestSlice: CGFloat = 0
        var total = 0
        for proxy in layouts {
            for line in proxy.layout {
                for run in line {
                    for slice in run {
                        total += 1
                        widestSlice = max(widestSlice, slice.typographicBounds.rect.width)
                    }
                }
            }
        }
        XCTAssertEqual(total, 3, "a + image + b should lay out as 3 slices")
        XCTAssertGreaterThanOrEqual(
            widestSlice, 39,
            "image slice should be ~40pt wide — got \(widestSlice); Text(Image) interpolation is not rendering"
        )
    }

    /// `Text.Layout` produces one slice per glyph — for latin words and
    /// embedded `Text(Image)` alike — so the mapped selection path can
    /// rely on slices == per-character mappings.
    @MainActor
    func test_layoutSlicesArePerGlyph() throws {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()

        let label = "ModelContext.swift:46-58"
        let layouts = captureLayouts(
            Text(Image(nsImage: image)) + Text(label)
        )
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        var slices = 0
        for proxy in layouts {
            for line in proxy.layout {
                for run in line {
                    slices += run.count
                }
            }
        }
        XCTAssertEqual(slices, label.count + 1, "expected one slice per glyph plus the image slot")
    }

    /// End-to-end: flatten a standalone code-reference paragraph, render
    /// through the `InlineContentView` pipeline, and verify the
    /// selection snapshot merges icon + label into ONE slice.
    @MainActor
    func test_standaloneCodeRefMergesIntoOneSlice() throws {
        let blocks = MarkdownFlattener.flatten(
            "`file:///Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:46-58`",
            baseURL: nil,
            previousBlocks: []
        )
        guard case .text(let attributed) = blocks.first?.content else {
            XCTFail("expected a text block"); return
        }

        // Mirror InlineContentView's assembly.
        var combined: Text? = nil
        var segment = AttributedString()
        func flush() {
            guard !segment.characters.isEmpty else { return }
            let piece = Text(segment)
            segment = AttributedString()
            combined = combined.map { $0 + piece } ?? piece
        }
        for run in attributed.runs {
            if let baked = run.attributes[MarkdownInlineImageKey.self] {
                flush()
                if let rendered = baked.rendered(
                    for: .monospacedSystemFont(ofSize: 14, weight: .light)
                ) {
                    combined = (combined ?? Text("")) + Text(Image(nsImage: rendered.image))
                        .baselineOffset(-rendered.descent)
                } else if let fallback = baked.fallbackText {
                    segment.append(AttributedString(fallback))
                }
            } else {
                segment.append(attributed[run.range])
            }
        }
        flush()
        var text = combined ?? Text("")
        if let mappings = attributed.selectionMappings {
            text = text.customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
        }

        let layouts = captureLayouts(
            text
                .font(Font(NSFont.monospacedSystemFont(ofSize: 14, weight: .light)))
                .foregroundColor(.black)
                .tint(.blue)
        )
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        let snapshot = SelectionLayoutSnapshot(
            base: layouts[0].layout,
            origin: .zero,
            linePrefix: nil
        )
        XCTAssertNotNil(snapshot)
        let allSlices = snapshot?.lines.flatMap(\.slices) ?? []
        XCTAssertEqual(allSlices.count, 1, "icon + label must merge into one atomic slice")
        XCTAssertEqual(
            snapshot?.attributedString.string,
            "`/Volumes/知阳/开发/Packges/JsonData/Sources/JsonData/ModelContext.swift:<46>-<58>`"
        )
    }

    /// Full pipeline: a real `MarkdownView` inside `.selectable()` —
    /// collect layouts AND anchors, run `makeSnapshots`, and inspect the
    /// slices produced for the standalone code-reference paragraph.
    @MainActor
    func test_fullPipelineStandaloneCodeRef() throws {
        let box = LayoutBox()
        var anchors: [MarkdownLayout] = []

        let view = MarkdownView(
            "前文\n\n`file:///tmp/ModelContext.swift:46-58`\n\n后文"
        )
        .markdownTheme(.default)
        .environment(GlobalSelectionCache())
        .onPreferenceChange(Text.LayoutKey.self) { box.layouts = $0 }
        .onPreferenceChange(MarkdownLayoutKey.self) { anchors = $0 }

        let hosting = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()

        let deadline = Date().addingTimeInterval(2)
        while (box.layouts.isEmpty || anchors.isEmpty), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
        }
        window.orderOut(nil)

        try XCTSkipIf(box.layouts.isEmpty, "no text layouts")

        var codeRefSlices = -1
        for proxy in box.layouts {
            guard let snap = SelectionLayoutSnapshot(
                base: proxy.layout,
                origin: .zero,
                linePrefix: nil
            ) else { continue }
            if snap.attributedString.string.contains("ModelContext.swift:<46>") {
                codeRefSlices = snap.lines.flatMap(\.slices).count
            }
        }
        XCTAssertEqual(
            codeRefSlices, 1,
            "standalone code reference must merge into one atomic selection slice"
        )
    }

    /// A soft line break (`这是表格：\n` + code reference) shares one
    /// paragraph: `\n` owns a mapping but no glyph. The mapped path must
    /// still engage — the code reference stays one atomic slice and the
    /// break copies as `\n`.
    @MainActor
    func test_softBreakCodeRefMergesIntoOneSlice() throws {
        let blocks = MarkdownFlattener.flatten(
            "这是表格：\n`file:///tmp/a.swift:12`",
            baseURL: nil,
            previousBlocks: []
        )
        guard case .text(let attributed) = blocks.first?.content else {
            XCTFail("expected a text block"); return
        }

        // Mirror InlineContentView's assembly.
        var combined: Text? = nil
        var segment = AttributedString()
        func flush() {
            guard !segment.characters.isEmpty else { return }
            let piece = Text(segment)
            segment = AttributedString()
            combined = combined.map { $0 + piece } ?? piece
        }
        for run in attributed.runs {
            if let baked = run.attributes[MarkdownInlineImageKey.self] {
                flush()
                if let rendered = baked.rendered(
                    for: .monospacedSystemFont(ofSize: 14, weight: .light)
                ) {
                    combined = (combined ?? Text("")) + Text(Image(nsImage: rendered.image))
                        .baselineOffset(-rendered.descent)
                } else if let fallback = baked.fallbackText {
                    segment.append(AttributedString(fallback))
                }
            } else {
                segment.append(attributed[run.range])
            }
        }
        flush()
        var text = combined ?? Text("")
        if let mappings = attributed.selectionMappings {
            text = text.customAttribute(MarkdownBlockMappingsAttribute(mappings: mappings))
        }

        let layouts = captureLayouts(
            text
                .font(Font(NSFont.monospacedSystemFont(ofSize: 14, weight: .light)))
                .foregroundColor(.black)
                .tint(.blue)
        )
        try XCTSkipIf(layouts.isEmpty, "Hosting environment did not publish text layouts")

        let snapshot = SelectionLayoutSnapshot(
            base: layouts[0].layout,
            origin: .zero,
            linePrefix: nil
        )
        XCTAssertNotNil(snapshot)
        guard let snapshot else { return }

        // Line 1: 5 glyphs + 1 zero-width `\n` slice. Line 2: merged ref.
        XCTAssertEqual(snapshot.lines.count, 2)
        XCTAssertEqual(snapshot.lines[0].slices.count, 6)
        XCTAssertEqual(snapshot.lines[1].slices.count, 1)
        XCTAssertEqual(
            snapshot.attributedString.string,
            "这是表格：\n`/tmp/a.swift:<12>`"
        )
        let breakSlice = snapshot.lines[0].slices[5]
        XCTAssertEqual(breakSlice.rect.width, 0)
    }

    /// Plain copy emits Markdown source: boundary glyphs carry the
    /// markers (`**`, backticks, link syntax, heading `#`) so the
    /// concatenated `source` payload reconstructs the original text.
    @MainActor
    func test_flattenerEmitsSourcePayloads() throws {
        func source(of content: String) throws -> String {
            let blocks = MarkdownFlattener.flatten(content, baseURL: nil, previousBlocks: [])
            var mappings: [GlobalSelectionCache.CharacterMapping]
            switch blocks.first?.content {
            case .text(let attributed), .heading(_, let attributed):
                mappings = attributed.selectionMappings ?? []
            default:
                throw NSError(domain: "test", code: 1)
            }
            return mappings.map { $0.source ?? $0.char }.joined()
        }

        try XCTAssertEqual(source(of: "这是**加粗**的 `code`"), "这是**加粗**的 `code`")
        try XCTAssertEqual(source(of: "# 标题"), "# 标题")
        try XCTAssertEqual(source(of: "见 [link](https://example.com) 完"), "见 [link](https://example.com) 完")
        // Soft line break: rendered `\n` and source `\n` must both appear.
        try XCTAssertEqual(source(of: "第一行\n第二行"), "第一行\n第二行")
        // Code reference: raw payload is the source.
        try XCTAssertEqual(source(of: "`/tmp/a.swift:12`"), "`/tmp/a.swift:<12>`")
    }
}
#endif
