// SelectableModifier.swift
// MarkdownExtendedView
//
//  `.selectable()` container: collects every descendant `Text` layout via
//  `Text.LayoutKey`, collects opt-in anchors via `MarkdownLayoutKey`, and
//  builds the `SelectionDocument` synchronously whenever layout changes.
//  Text selection only engages for views wrapped in
//  `makeCanSelectable()` — everything else stays non-selectable.
//
//  Interaction is a plain `DragGesture` (the proven approach): drags map
//  to selection positions via the document; links and buttons remain
//  tappable because a tap never crosses the drag threshold.

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct SelectableModifier: ViewModifier {

    @State private var model = SelectionModel()
    @State private var selectionCache = GlobalSelectionCache()
    @State private var textLayouts: SwiftUI.Text.LayoutKey.Value = []
    #if canImport(AppKit)
    @State private var hoverLocation: CGPoint?
    @State private var cursorPushed = false
    #endif

    func body(content: Content) -> some View {
        content
            .environment(selectionCache)
            .onPreferenceChange(SwiftUI.Text.LayoutKey.self) { layouts in
                textLayouts = layouts
            }
            .backgroundPreferenceValue(MarkdownLayoutKey.self) { anchors in
                GeometryReader { geometry in
                    Color.clear
                        .onChange(
                            of: SelectionLayoutInputID(
                                layouts: textLayouts,
                                anchors: anchors,
                                size: geometry.size
                            ),
                            initial: true
                        ) { _, _ in
                            model.updateLayout(
                                textLayouts: textLayouts,
                                anchors: anchors,
                                geometry: geometry
                            )
                        }
                }
            }
            .overlay {
                SelectionHighlightLayer(model: model)
                    .allowsHitTesting(false)
            }
            // Containers hit-test only where children do — rows using
            // `.allowsHitTesting(false)` would leave dead zones, so the
            // whole bounds must be an explicit hit region for the drag
            // gesture to engage.
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !model.isDraggingSelection {
                            model.beginSelectionDrag(at: value.startLocation)
                        }
                        model.updateSelectionDrag(to: value.location)
                    }
                    .onEnded { _ in
                        model.endSelectionDrag()
                    }
            )
#if canImport(AppKit)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    updateCursor(at: location)
                case .ended:
                    hoverLocation = nil
                    releaseCursor()
                }
            }
#endif
            .contextMenu {
                contextMenuContent
            }
#if canImport(AppKit)
            .background(
                WindowDeselectHandler(
                    onDeselect: { model.clearSelection() },
                    onCopy: copySelection,
                    onSelectAll: { model.selectAll() }
                )
            )
#endif
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        #if canImport(AppKit)
        let insideSelection = hoverLocation.map(model.isPointInsideSelection) ?? false
        if insideSelection {
            selectionMenuItems
        } else if let link = hoverLocation.flatMap({ model.link(at: $0) }) {
            Button("拷贝链接") { copyLink(link) }
        } else if model.hasNonCollapsedSelection {
            selectionMenuItems
        }
        #else
        if model.hasNonCollapsedSelection {
            selectionMenuItems
        }
        #endif
    }

    @ViewBuilder
    private var selectionMenuItems: some View {
        Button("拷贝") { copySelection() }
        Button("仅拷贝为文本") { copySelectionAsText() }
        Divider()
        Button("含图像拷贝") { copySelectionRich() }
    }

    // MARK: - Hover cursor

    #if canImport(AppKit)
    private func updateCursor(at point: CGPoint) {
        let overLink = model.link(at: point) != nil
        guard overLink != cursorPushed else {
            return
        }
        if overLink {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        cursorPushed = overLink
    }

    private func releaseCursor() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
    #endif

    // MARK: - Copy

    private func selectedText() -> String? {
        guard let text = model.selectedPlainText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// 拷贝 — attributed rich text (RTF) plus a plain string.
    @discardableResult
    private func copySelection() -> Bool {
        guard let attributed = model.selectedAttributedText(),
              !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([attributed])
        return true
        #elseif canImport(UIKit)
        UIPasteboard.general.string = attributed.string
        return true
        #else
        return false
        #endif
    }

    /// 仅拷贝为文本 — plain string only.
    private func copySelectionAsText() {
        guard let text = selectedText() else {
            return
        }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    /// 含图像拷贝 — RTFD carrying rendered images (formulas, mermaid,
    /// code-reference icons); the plain-text fallback keeps the normal
    /// payloads (raw references, `$…$`, alt text).
    private func copySelectionRich() {
        guard let rich = model.selectedRichText(), rich.length > 0 else {
            return
        }
        let fullRange = NSRange(location: 0, length: rich.length)
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if
            let rtfd = try? rich.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
        {
            pasteboard.setData(rtfd, forType: .rtfd)
        }
        if
            let rtf = try? rich.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let text = selectedText() {
            pasteboard.setString(text, forType: .string)
        }
        #elseif canImport(UIKit)
        var item: [String: Any] = [
            UTType.plainText.identifier: selectedText() ?? rich.string
        ]
        if
            let rtfd = try? rich.data(
                from: fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
        {
            item[UTType.flatRTFD.identifier] = rtfd
        }
        UIPasteboard.general.items = [item]
        #endif
    }

    /// 拷贝链接 — code references copy the canonical POSIX form
    /// (`` `/abs/path:<46>-<58>` ``); other links copy the URL verbatim.
    private func copyLink(_ link: String) {
        let text: String
        if
            let url = URL(string: link),
            url.isFileURL,
            let reference = MCodeReference(link)
        {
            text = "`\(reference.referenceString)`"
        } else {
            text = link
        }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

/// Line-merged highlight rectangles for the current selection.
private struct SelectionHighlightLayer: View {
    let model: SelectionModel

    var body: some View {
        Path { path in
            for selectionRect in model.selectionRects {
                let rect = selectionRect.rect.insetBy(dx: -1, dy: -1)
                guard rect.width > 0, rect.height > 0 else { continue }
                path.addPath(
                    Path(roundedRect: rect, cornerRadius: 2, style: .continuous)
                )
            }
        }
        .fill(Color.accentColor.opacity(0.2))
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }
}

public extension View {
    func selectable() -> some View {
        self.modifier(SelectableModifier())
    }
}

// MARK: - Opt-in anchor

/// Marks a view as selectable inside a `.selectable()` container.
/// - `isBlock: false` — the view contributes its laid-out `Text`s (their
///   center must fall inside this anchor's bounds).
/// - `isBlock: true` — the whole view is one atomic selection unit whose
///   copy payload is `blockText`; any `Text` inside is excluded.
public struct MakeTextSelectable: ViewModifier {
    @Environment(GlobalSelectionCache.self) private var selectionCache: GlobalSelectionCache?
    @Environment(\.markdownSelectionLinePrefix) private var linePrefix
    @State private var blockId = UUID()

    public let isBlock: Bool
    public let blockText: String
    /// Rendered image for rich copies (mermaid diagram, block formula).
    public let richImage: MTImage?

    public func body(content: Content) -> some View {
        if selectionCache != nil {
            content
                .selectionTextPassThrough()
                .anchorPreference(key: MarkdownLayoutKey.self, value: .bounds) { bounds in
                    [
                        MarkdownLayout(
                            blockId: blockId,
                            bounds: bounds,
                            isBlock: isBlock,
                            blockText: blockText,
                            linePrefix: linePrefix.isEmpty ? nil : linePrefix,
                            richImage: richImage
                        )
                    ]
                }
        } else {
            content
        }
    }
}

public extension View {
    func makeCanSelectable(
        isBlock: Bool = false,
        blockText: String = "",
        richImage: MTImage? = nil
    ) -> some View {
        self.modifier(
            MakeTextSelectable(
                isBlock: isBlock,
                blockText: blockText,
                richImage: richImage
            )
        )
    }
}
