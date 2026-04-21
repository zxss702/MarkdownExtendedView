#if os(macOS) || os(iOS)
// SelectionInteractionView.swift
//  MarkdownExtendedView
//
//  Created by OpenAI Codex on 2026-04-21.
// Licensed under MIT License

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
struct SelectionInteractionOverlay: NSViewRepresentable {
    let model: SelectionModel

    func makeNSView(context: Context) -> SelectionInteractionView {
        SelectionInteractionView(model: model)
    }

    func updateNSView(_ nsView: SelectionInteractionView, context: Context) {
        nsView.model = model
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class SelectionInteractionView: NSView {
    var model: SelectionModel

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(model: SelectionModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        var hasCursorRect = false

        for rect in model.textHitRects() {
            let visibleRect = rect.intersection(bounds)
            guard !visibleRect.isNull, !visibleRect.isEmpty else {
                continue
            }

            addCursorRect(visibleRect, cursor: .iBeam)
            hasCursorRect = true
        }

        if !hasCursorRect {
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)

        _ = model.beginSelectionDrag(at: location)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard model.isDraggingSelection else {
            return
        }

        model.updateSelectionDrag(to: location)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        model.endSelectionDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu()
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func selectAll(_ sender: Any?) {
        model.selectAll()
    }

    @objc func copy(_ sender: Any?) {
        guard let text = model.selectedPlainText(), !text.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        guard model.hasNonCollapsedSelection else { return menu }

        menu.addItem(
            NSMenuItem(
                title: NSLocalizedString("Copy", bundle: .main, comment: ""),
                action: #selector(copy(_:)),
                keyEquivalent: ""
            )
        )

        return menu
    }
}

extension SelectionInteractionView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(selectAll(_:)):
            return model.hasText
        case #selector(copy(_:)):
            return model.hasNonCollapsedSelection
        default:
            return true
        }
    }
}
#endif

#if canImport(UIKit)
struct SelectionInteractionOverlay: UIViewRepresentable {
    let model: SelectionModel

    func makeUIView(context: Context) -> SelectionInteractionView {
        SelectionInteractionView(model: model)
    }

    func updateUIView(_ uiView: SelectionInteractionView, context: Context) {
        uiView.model = model
    }
}

final class SelectionInteractionView: UIView {
    override var canBecomeFirstResponder: Bool { true }

    var model: SelectionModel {
        didSet {
            wireModelCallbacks()
        }
    }

    weak var inputDelegate: (any UITextInputDelegate)?

    private lazy var tokenizerImpl = UITextInputStringTokenizer(textInput: self)
    private let selectionInteraction: UITextInteraction = .init(for: .nonEditable)

    init(model: SelectionModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        wireModelCallbacks()
        selectionInteraction.textInput = self
        selectionInteraction.delegate = self
        addInteraction(selectionInteraction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)):
            return model.hasNonCollapsedSelection
        default:
            return false
        }
    }

    override func copy(_ sender: Any?) {
        guard let text = model.selectedPlainText(), !text.isEmpty else {
            return
        }

        UIPasteboard.general.string = text
    }

    private func wireModelCallbacks() {
        model.selectionWillChange = { [weak self] in
            guard let self else { return }
            self.inputDelegate?.selectionWillChange(self)
        }

        model.selectionDidChange = { [weak self] in
            guard let self else { return }
            self.inputDelegate?.selectionDidChange(self)
        }
    }
}

extension SelectionInteractionView: UITextInteractionDelegate {
    func interactionWillBegin(_ interaction: UITextInteraction) {
        _ = becomeFirstResponder()
    }
}

private final class SelectionTextPositionBox: UITextPosition {
    let wrappedValue: SelectionPosition

    init(_ wrappedValue: SelectionPosition) {
        self.wrappedValue = wrappedValue
    }
}

private final class SelectionTextRangeBox: UITextRange {
    let wrappedValue: SelectionRange

    override var start: UITextPosition {
        SelectionTextPositionBox(wrappedValue.start)
    }

    override var end: UITextPosition {
        SelectionTextPositionBox(wrappedValue.end)
    }

    override var isEmpty: Bool {
        wrappedValue.isCollapsed
    }

    init(_ wrappedValue: SelectionRange) {
        self.wrappedValue = wrappedValue
    }

    init?(from: UITextPosition, to: UITextPosition) {
        guard
            let fromBox = from as? SelectionTextPositionBox,
            let toBox = to as? SelectionTextPositionBox
        else {
            return nil
        }

        self.wrappedValue = SelectionRange(from: fromBox.wrappedValue, to: toBox.wrappedValue)
    }
}

private final class SelectionTextSelectionRectBox: UITextSelectionRect {
    let wrappedValue: SelectionRect

    init(_ wrappedValue: SelectionRect) {
        self.wrappedValue = wrappedValue
    }

    override var rect: CGRect {
        wrappedValue.rect
    }

    override var writingDirection: UITextWritingDirection {
        wrappedValue.layoutDirection == .leftToRight ? .leftToRight : .rightToLeft
    }

    override var containsStart: Bool {
        wrappedValue.containsStart
    }

    override var containsEnd: Bool {
        wrappedValue.containsEnd
    }

    override var isVertical: Bool {
        false
    }
}

extension SelectionInteractionView: UITextInput {
    var hasText: Bool {
        model.hasText
    }

    func insertText(_ text: String) {
    }

    func deleteBackward() {
    }

    func text(in range: UITextRange) -> String? {
        guard let rangeBox = range as? SelectionTextRangeBox else { return nil }
        return model.text(in: rangeBox.wrappedValue)
    }

    func replace(_ range: UITextRange, withText text: String) {
    }

    var selectedTextRange: UITextRange? {
        get { model.selectedRange.map(SelectionTextRangeBox.init) }
        set {
            let rangeBox = newValue as? SelectionTextRangeBox
            model.selectedRange = rangeBox?.wrappedValue
        }
    }

    var markedTextRange: UITextRange? {
        nil
    }

    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set {}
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
    }

    func unmarkText() {
    }

    var beginningOfDocument: UITextPosition {
        SelectionTextPositionBox(model.startPosition)
    }

    var endOfDocument: UITextPosition {
        SelectionTextPositionBox(model.endPosition)
    }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        SelectionTextRangeBox(from: fromPosition, to: toPosition)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let positionBox = position as? SelectionTextPositionBox else { return nil }
        return model.position(from: positionBox.wrappedValue, offset: offset).map(SelectionTextPositionBox.init)
    }

    func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        nil
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard
            let lhs = position as? SelectionTextPositionBox,
            let rhs = other as? SelectionTextPositionBox,
            lhs.wrappedValue != rhs.wrappedValue
        else {
            return .orderedSame
        }

        return lhs.wrappedValue < rhs.wrappedValue ? .orderedAscending : .orderedDescending
    }

    func offset(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard
            let from = fromPosition as? SelectionTextPositionBox,
            let to = toPosition as? SelectionTextPositionBox
        else {
            return 0
        }

        return model.offset(from: from.wrappedValue, to: to.wrappedValue)
    }

    var tokenizer: any UITextInputTokenizer {
        tokenizerImpl
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        nil
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        nil
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .natural
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
    }

    func firstRect(for range: UITextRange) -> CGRect {
        guard let rangeBox = range as? SelectionTextRangeBox else { return .zero }
        return model.firstRect(for: rangeBox.wrappedValue)
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        guard let positionBox = position as? SelectionTextPositionBox else { return .zero }
        return model.caretRect(for: positionBox.wrappedValue)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let rangeBox = range as? SelectionTextRangeBox else { return [] }
        return model.selectionRectsSync(for: rangeBox.wrappedValue).map(SelectionTextSelectionRectBox.init)
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        model.closestPosition(to: point).map(SelectionTextPositionBox.init)
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let rangeBox = range as? SelectionTextRangeBox else { return nil }
        return model.closestPosition(to: point, within: rangeBox.wrappedValue).map(SelectionTextPositionBox.init)
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        model.characterRange(at: point).map(SelectionTextRangeBox.init)
    }

    var textInputView: UIView {
        self
    }

    var isEditable: Bool {
        false
    }
}
#endif
#endif
