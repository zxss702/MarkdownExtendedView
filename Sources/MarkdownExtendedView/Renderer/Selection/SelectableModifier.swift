// SelectableModifier.swift
// MarkdownExtendedView
//
//  `.selectable()` container: collects `MarkdownLayoutKey` anchor
//  payloads — each `makeCanSelectable()` anchor bundles its own
//  subtree's `Text` layouts — and builds the `SelectionDocument`
//  synchronously whenever layout changes.
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
    /// Latest drag location in container space — the auto-scroll timer
    /// re-feeds it on platforms without a cursor position.
    @State private var dragPoint: CGPoint = .zero
    #if canImport(AppKit)
    @State private var hoverLocation: CGPoint?
    @State private var cursorPushed = false
    #endif

    func body(content: Content) -> some View {
        content
            .environment(selectionCache)
            .backgroundPreferenceValue(MarkdownLayoutKey.self) { anchors in
                GeometryReader { geometry in
                    Color.clear
                        .onChange(
                            of: SelectionLayoutInputID(
                                anchors: anchors,
                                size: geometry.size
                            ),
                            initial: true
                        ) { _, _ in
                            model.updateLayout(
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
                        dragPoint = value.location
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
            .background(
                SelectionAutoScrollBridge(
                    isDragging: model.isDragging,
                    dragPoint: dragPoint,
                    onDrag: { model.updateSelectionDrag(to: $0) }
                )
                .allowsHitTesting(false)
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

    /// 拷贝 / Cmd+C — the Markdown source of the selection.
    @discardableResult
    private func copySelection() -> Bool {
        guard let text = selectedText() else {
            return false
        }
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        return true
        #else
        return false
        #endif
    }

    /// 含图像拷贝 — RTFD carrying the rendered look: images for
    /// formulas/mermaid/pictures; code references always copy their
    /// raw source. The plain-text fallback is the Markdown source.
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
    @Environment(\.markdownSelectionID) private var environmentSelectionID
    @State private var blockId = UUID()

    public let isBlock: Bool
    public let blockText: String
    /// Rendered image for rich copies (mermaid diagram, block formula).
    public let richImage: MTImage?
    /// Explicit stable identity — wins over the environment value.
    public let selectionID: String?
    /// Markdown-source wrappers copied around this anchor's sections —
    /// code-block fences (` ```swift ` … ` ``` `). Emitted only when
    /// the selection covers the anchor's first/last section boundary.
    public let sourcePrefix: String?
    public let sourceSuffix: String?

    public func body(content: Content) -> some View {
        if selectionCache != nil {
            content
                .selectionTextPassThrough()
                // Capture this subtree's own text layouts so the payload
                // binds texts to their anchor structurally — geometric
                // matching races when lazy stacks remeasure mid-scroll.
                .backgroundPreferenceValue(SwiftUI.Text.LayoutKey.self) { layouts in
                    Color.clear
                        .backgroundPreferenceValue(MarkdownLayoutKey.self) { nested in
                            // Texts claimed by nested anchors belong to
                            // them — the innermost anchor wins.
                            let nestedTexts = nested.flatMap { $0.textLayouts }
                            Color.clear.anchorPreference(
                                key: MarkdownLayoutKey.self, value: .bounds
                            ) { bounds in
                                [
                                    MarkdownLayout(
                                        blockId: blockId,
                                        bounds: bounds,
                                        isBlock: isBlock,
                                        blockText: blockText,
                                        linePrefix: linePrefix.isEmpty ? nil : linePrefix,
                                        richImage: richImage,
                                        selectionID: selectionID ?? environmentSelectionID,
                                        textLayouts: layouts.filter { !nestedTexts.contains($0) },
                                        sourcePrefix: sourcePrefix,
                                        sourceSuffix: sourceSuffix
                                    )
                                ]
                            }
                        }
                }
        } else {
            content
        }
    }
}

public extension View {
    /// - Parameter selectionID: stable data-level identity for the
    ///   anchor (e.g. a row/model id). Inside lazy containers this is
    ///   what lets the selection document dedupe rematerialized copies
    ///   of the same logical row instead of accumulating duplicates.
    ///   Defaults to the `markdownSelectionID` environment value.
    func makeCanSelectable(
        isBlock: Bool = false,
        blockText: String = "",
        richImage: MTImage? = nil,
        selectionID: String? = nil,
        sourcePrefix: String? = nil,
        sourceSuffix: String? = nil
    ) -> some View {
        self.modifier(
            MakeTextSelectable(
                isBlock: isBlock,
                blockText: blockText,
                richImage: richImage,
                selectionID: selectionID,
                sourcePrefix: sourcePrefix,
                sourceSuffix: sourceSuffix
            )
        )
    }
}
