#if os(macOS) || os(iOS)
// SelectableMarkdownRendererNative.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import CoreText
import Markdown
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import Observation

#if os(macOS) || os(iOS)
public extension View {
    func selectable() -> some View {
        modifier(SelectableMarkdownRendererViewModifier())
    }
}

struct SelectableMarkdownRendererViewModifier: ViewModifier {
    @State private var model = SelectionModel()
    
    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(SwiftUI.Text.LayoutKey.self) { value in
                GeometryReader { geometry in
                    let collection = AnySelectionLayoutCollection(
                        LiveSelectionLayoutCollection(base: value, geometry: geometry)
                    )

                    SelectionInteractionOverlay(model: model)
                        .task(id: collection) {
                            await model.updateLayoutCollection(collection)
                        }
                }
            }
            .overlay {
                SelectionHighlightLayer(model: model)
                    .allowsHitTesting(false)
                    .blendMode(.multiply)
            }
    }
}
#endif

#if canImport(AppKit)

private struct SelectionInteractionOverlay: NSViewRepresentable {
    let model: SelectionModel

    func makeNSView(context: Context) -> SelectionInteractionView {
        SelectionInteractionView(model: model)
    }

    func updateNSView(_ nsView: SelectionInteractionView, context: Context) {
        nsView.model = model
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}


private final class SelectionInteractionView: NSView {
    var model: SelectionModel

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private var dragStart: SelectionTextPosition?

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

        guard model.containsText(at: location), let start = model.closestPosition(to: location) else {
            model.clearSelection()
            dragStart = nil
            return
        }

        dragStart = start
        model.selectedRange = SelectionTextRange(start: start, end: start)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let location = convert(event.locationInWindow, from: nil)

        guard let currentPosition = model.closestPosition(to: location) else {
            return
        }
        
        model.selectedRange = SelectionTextRange(from: dragStart, to: currentPosition)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if model.selectedRange?.isCollapsed == true {
            model.clearSelection()
        }
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

private struct SelectionInteractionOverlay: UIViewRepresentable {
    let model: SelectionModel

    func makeUIView(context: Context) -> SelectionInteractionView {
        SelectionInteractionView(model: model)
    }

    func updateUIView(_ uiView: SelectionInteractionView, context: Context) {
        uiView.model = model
    }
}


private final class SelectionInteractionView: UIView {
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
    let wrappedValue: SelectionTextPosition

    init(_ wrappedValue: SelectionTextPosition) {
        self.wrappedValue = wrappedValue
    }
}


private final class SelectionTextRangeBox: UITextRange {
    let wrappedValue: SelectionTextRange

    override var start: UITextPosition {
        SelectionTextPositionBox(wrappedValue.start)
    }

    override var end: UITextPosition {
        SelectionTextPositionBox(wrappedValue.end)
    }

    override var isEmpty: Bool {
        wrappedValue.isCollapsed
    }

    init(_ wrappedValue: SelectionTextRange) {
        self.wrappedValue = wrappedValue
    }

    init?(from: UITextPosition, to: UITextPosition) {
        guard
            let fromBox = from as? SelectionTextPositionBox,
            let toBox = to as? SelectionTextPositionBox
        else {
            return nil
        }
        self.wrappedValue = SelectionTextRange(from: fromBox.wrappedValue, to: toBox.wrappedValue)
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
        else { return 0 }
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


private struct SelectionHighlightLayer: View {
    let model: SelectionModel

    #if canImport(AppKit)
    private let fillColor = Color(nsColor: .selectedTextBackgroundColor).opacity(0.5)
    #else
    private let fillColor = Color(uiColor: .systemBlue).opacity(0.28)
    #endif

    var body: some View {
        Canvas { context, size in
            for selectionRect in model.selectionRects {
                context.fill(
                    Path(selectionRect.rect),
                    with: .color(fillColor)
                )
            }
        }
    }
}

private actor SelectionCalculator {
    static let shared = SelectionCalculator()
    
    func processLayout(
        newCollection: any SelectionTextLayoutCollection,
        oldCollection: any SelectionTextLayoutCollection,
        oldRange: SelectionTextRange?
    ) -> (SelectionTextRange?, [SelectionRect], [CGRect]) {
        _ = newCollection.layouts
        let newRange = oldRange.flatMap { newCollection.reconcileRange($0, from: oldCollection) }
        let rects = newRange.map { newCollection.selectionRects(for: $0) } ?? []
        let hitRects = newCollection.textHitRects()
        return (newRange, rects, hitRects)
    }
    
    func calculateRects(for range: SelectionTextRange, in collection: any SelectionTextLayoutCollection) -> [SelectionRect] {
        collection.selectionRects(for: range)
    }
}

@MainActor
@Observable
private final class SelectionModel {
    var selectedRange: SelectionTextRange? {
        willSet {
            selectionWillChange?()
        }
        didSet {
            selectionRectTask?.cancel()
            
            if let selectedRange {
                let collection = layoutCollection
                selectionRectTask = Task.detached(priority: .userInitiated) {
                    let rects = await SelectionCalculator.shared.calculateRects(for: selectedRange, in: collection)
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.selectionRects = rects
                        }
                    }
                }
            } else {
                selectionRects = []
            }
            selectionDidChange?()
        }
    }

    private(set) var selectionRects: [SelectionRect] = []

    @ObservationIgnored var selectionWillChange: (() -> Void)?
    @ObservationIgnored var selectionDidChange: (() -> Void)?
    
    @ObservationIgnored private var selectionRectTask: Task<Void, Never>?
    @ObservationIgnored private var cachedTextHitRects: [CGRect] = []
    
    var layoutCollection: any SelectionTextLayoutCollection = EmptySelectionLayoutCollection()

    @ObservationIgnored var hasText: Bool {
        layoutCollection.stringLength > 0
    }

    @ObservationIgnored var hasNonCollapsedSelection: Bool {
        guard let selectedRange else { return false }
        return !selectedRange.isCollapsed
    }

    func updateLayoutCollection(_ newCollection: any SelectionTextLayoutCollection) async {
        guard !newCollection.isEqual(to: self.layoutCollection) else { return }
        
        do {
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            return
        }

        let oldCollection = self.layoutCollection
        let oldRange = self.selectedRange
        
        let updateTask = Task.detached(priority: .userInitiated) {
            await SelectionCalculator.shared.processLayout(
                newCollection: newCollection,
                oldCollection: oldCollection,
                oldRange: oldRange
            )
        }
        
        let (newRange, newRects, hitRects) = await updateTask.value
        
        guard !Task.isCancelled else { return }
        
        self.layoutCollection = newCollection
        self.cachedTextHitRects = hitRects
        if oldRange != nil {
            self.selectedRange = newRange
        } else {
            self.selectionRects = newRects
        }
    }

    func clearSelection() {
        selectedRange = nil
    }

    func selectAll() {
        guard hasText else {
            selectedRange = nil
            return
        }

        selectedRange = SelectionTextRange(
            start: layoutCollection.startPosition,
            end: layoutCollection.endPosition
        )
    }

    func closestPosition(to point: CGPoint) -> SelectionTextPosition? {
        layoutCollection.closestPosition(to: point)
    }

    func closestPosition(to point: CGPoint, within range: SelectionTextRange) -> SelectionTextPosition? {
        guard let position = closestPosition(to: point) else { return nil }
        if position <= range.start { return range.start }
        if position >= range.end { return range.end }
        return position
    }

    func characterRange(at point: CGPoint) -> SelectionTextRange? {
        layoutCollection.characterRange(at: point)
    }

    func position(from position: SelectionTextPosition, offset: Int) -> SelectionTextPosition? {
        layoutCollection.position(from: position, offset: offset)
    }

    func offset(from: SelectionTextPosition, to: SelectionTextPosition) -> Int {
        (layoutCollection.characterIndex(at: to) ?? 0) - (layoutCollection.characterIndex(at: from) ?? 0)
    }

    var startPosition: SelectionTextPosition {
        layoutCollection.startPosition
    }

    var endPosition: SelectionTextPosition {
        layoutCollection.endPosition
    }

    func textHitRects() -> [CGRect] {
        cachedTextHitRects
    }

    func containsText(at point: CGPoint) -> Bool {
        cachedTextHitRects.contains { $0.contains(point) }
    }

    func selectedPlainText() -> String? {
        guard let selectedRange else { return nil }
        guard !selectedRange.isCollapsed else { return nil }

        return text(in: selectedRange)
    }

    func text(in range: SelectionTextRange) -> String {
        layoutCollection.plainText(in: range)
    }

    func attributedText(in range: SelectionTextRange) -> NSAttributedString {
        layoutCollection.attributedText(in: range)
    }

    func firstRect(for range: SelectionTextRange) -> CGRect {
        layoutCollection.firstRect(for: range)
    }

    func caretRect(for position: SelectionTextPosition) -> CGRect {
        layoutCollection.caretRect(for: position)
    }

    func selectionRectsSync(for range: SelectionTextRange) -> [SelectionRect] {
        layoutCollection.selectionRects(for: range)
    }
}


private struct SelectionTextPosition: Hashable, Comparable {
    enum Affinity: Comparable {
        case downstream
        case upstream
    }

    let indexPath: IndexPath
    let affinity: Affinity

    static func < (lhs: SelectionTextPosition, rhs: SelectionTextPosition) -> Bool {
        if lhs.indexPath == rhs.indexPath {
            return lhs.affinity < rhs.affinity
        }
        return lhs.indexPath < rhs.indexPath
    }
}


private struct SelectionTextRange: Hashable {
    let start: SelectionTextPosition
    let end: SelectionTextPosition

    var isCollapsed: Bool {
        start == end
    }

    init(from: SelectionTextPosition, to: SelectionTextPosition) {
        if from <= to {
            self.init(start: from, end: to)
        } else {
            self.init(start: to, end: from)
        }
    }

    init(start: SelectionTextPosition, end: SelectionTextPosition) {
        self.start = start
        self.end = end
    }

    func contains(_ position: SelectionTextPosition) -> Bool {
        (start.affinity == .upstream ? position > start : position >= start)
            && (end.affinity == .downstream ? position < end : position <= end)
    }
}


private struct SelectionRect: Hashable {
    var rect: CGRect

    let layoutDirection: LayoutDirection
    var containsStart: Bool
    var containsEnd: Bool

    init(
        rect: CGRect,
        layoutDirection: LayoutDirection,
        containsStart: Bool = false,
        containsEnd: Bool = false
    ) {
        self.rect = rect
        self.layoutDirection = layoutDirection
        self.containsStart = containsStart
        self.containsEnd = containsEnd
    }
}

private struct SelectionPathComponents {
    let layout: Int
    let line: Int
    let run: Int
    let runSlice: Int
}


private struct SelectionIndexPathSequence: Sequence, IteratorProtocol {
    private var current: IndexPath?
    private let end: IndexPath?
    private let nextHandler: (IndexPath) -> IndexPath?

    init(
        range: SelectionTextRange,
        next: @escaping (IndexPath) -> IndexPath?,
        previous: @escaping (IndexPath) -> IndexPath?
    ) {
        self.nextHandler = next

        let lowerBound =
            if range.start.affinity == .upstream {
                next(range.start.indexPath)
            } else {
                range.start.indexPath
            }

        let upperBound =
            if range.end.affinity == .downstream {
                previous(range.end.indexPath)
            } else {
                range.end.indexPath
            }

        guard let lowerBound, let upperBound, lowerBound <= upperBound else {
            self.current = nil
            self.end = nil
            return
        }

        self.current = lowerBound
        self.end = upperBound
    }

    mutating func next() -> IndexPath? {
        guard let current, let end else { return nil }

        let value = current
        if value == end {
            self.current = nil
        } else {
            self.current = nextHandler(current)
        }

        return value
    }
}


private protocol SelectionTextLayoutCollection: Sendable {
    var layouts: [any SelectionTextLayout] { get }

    func isEqual(to other: any SelectionTextLayoutCollection) -> Bool
    func needsPositionReconciliation(with other: any SelectionTextLayoutCollection) -> Bool
}


private struct AnySelectionLayoutCollection: SelectionTextLayoutCollection, @unchecked Sendable, Equatable {
    private let base: any SelectionTextLayoutCollection

    init(_ base: any SelectionTextLayoutCollection) {
        self.base = base
    }

    var layouts: [any SelectionTextLayout] {
        base.layouts
    }

    func isEqual(to other: any SelectionTextLayoutCollection) -> Bool {
        base.isEqual(to: other)
    }

    func needsPositionReconciliation(with other: any SelectionTextLayoutCollection) -> Bool {
        base.needsPositionReconciliation(with: other)
    }

    static func == (lhs: AnySelectionLayoutCollection, rhs: AnySelectionLayoutCollection) -> Bool {
        lhs.base.isEqual(to: rhs.base)
    }
}


private protocol SelectionTextLayout: Sendable {
    var attributedString: NSAttributedString { get }
    var origin: CGPoint { get }
    var bounds: CGRect { get }
    var lines: [any SelectionTextLine] { get }
}


private protocol SelectionTextLine: Sendable {
    var origin: CGPoint { get }
    var typographicBounds: CGRect { get }
    var runs: [any SelectionTextRun] { get }
}


private protocol SelectionTextRun: Sendable {
    var layoutDirection: LayoutDirection { get }
    var typographicBounds: CGRect { get }
    var slices: [any SelectionTextRunSlice] { get }
}


private protocol SelectionTextRunSlice: Sendable {
    var typographicBounds: CGRect { get }
    var characterRange: Range<Int> { get }
}


private struct EmptySelectionLayoutCollection: SelectionTextLayoutCollection, @unchecked Sendable {
    var layouts: [any SelectionTextLayout] { [] }

    func isEqual(to other: any SelectionTextLayoutCollection) -> Bool {
        other.layouts.isEmpty
    }

    func needsPositionReconciliation(with other: any SelectionTextLayoutCollection) -> Bool {
        false
    }
}


private final class LiveSelectionLayoutCollection: SelectionTextLayoutCollection, @unchecked Sendable {
    private(set) lazy var layouts: [any SelectionTextLayout] = makeLayouts()

    private let base: SwiftUI.Text.LayoutKey.Value
    private let geometry: GeometryProxy

    init(base: SwiftUI.Text.LayoutKey.Value, geometry: GeometryProxy) {
        self.base = base
        self.geometry = geometry
    }

    func isEqual(to other: any SelectionTextLayoutCollection) -> Bool {
        base == (other as? LiveSelectionLayoutCollection)?.base
    }

    func needsPositionReconciliation(with other: any SelectionTextLayoutCollection) -> Bool {
        base.map(\.layout) != (other as? LiveSelectionLayoutCollection)?.base.map(\.layout)
    }

    private func makeLayouts() -> [any SelectionTextLayout] {
        base.map { anchoredLayout in
            LiveSelectionTextLayout(
                base: anchoredLayout.layout,
                origin: geometry[anchoredLayout.origin]
            )
        }
    }
}


private final class LiveSelectionTextLayout: SelectionTextLayout, @unchecked Sendable {
    var attributedString: NSAttributedString {
        joinedAttributedString.joined
    }

    let origin: CGPoint

    private(set) lazy var bounds: CGRect = makeBounds()
    private(set) lazy var lines: [any SelectionTextLine] = makeLines()

    private let base: SwiftUI.Text.Layout
    private lazy var contents = base.materializeSelectionContents()
    private lazy var joinedAttributedString = contents.attributedStrings.joinedForSelection()

    init(base: SwiftUI.Text.Layout, origin: CGPoint) {
        self.base = base
        self.origin = origin
    }

    private func makeBounds() -> CGRect {
        base.map(\.typographicBounds.rect).reduce(CGRect.null, CGRectUnion)
    }

    private func makeLines() -> [any SelectionTextLine] {
        guard contents.attributedStrings.count > 1 else {
            return base.map { LiveSelectionTextLine(base: $0) }
        }

        let (_, characterOffsets) = contents.layoutAttributedStrings.joinedForSelection()

        return zip(base, contents.lineFragments).compactMap { line, lineFragment in
            guard let offset = characterOffsets[ObjectIdentifier(lineFragment.attributedString)] else {
                return nil
            }

            return LiveSelectionTextLine(base: line, offset: offset)
        }
    }
}


private final class LiveSelectionTextLine: SelectionTextLine, @unchecked Sendable {
    var origin: CGPoint {
        base.origin
    }

    var typographicBounds: CGRect {
        base.typographicBounds.rect
    }

    private(set) lazy var runs: [any SelectionTextRun] = makeRuns()

    private let base: SwiftUI.Text.Layout.Line
    private let offset: Int

    init(base: SwiftUI.Text.Layout.Line, offset: Int = 0) {
        self.base = base
        self.offset = offset
    }

    private func makeRuns() -> [any SelectionTextRun] {
        if base.isEmpty {
            return [
                EmptySelectionRun(
                    typographicBounds: base.typographicBounds.rect,
                    slice: .init(
                        typographicBounds: base.typographicBounds.rect,
                        characterRange: offset..<(offset + 1)
                    )
                )
            ]
        } else {
            return base.map { run in
                LiveSelectionTextRun(base: run, offset: offset)
            }
        }
    }
}


private final class LiveSelectionTextRun: SelectionTextRun, @unchecked Sendable {
    var layoutDirection: LayoutDirection {
        base.layoutDirection
    }

    var typographicBounds: CGRect {
        base.typographicBounds.rect
    }

    private(set) lazy var slices: [any SelectionTextRunSlice] = makeRunSlices()

    private let base: SwiftUI.Text.Layout.Run
    private let offset: Int

    init(base: SwiftUI.Text.Layout.Run, offset: Int) {
        self.base = base
        self.offset = offset
    }

    private func makeRunSlices() -> [any SelectionTextRunSlice] {
        zip(base, base.selectionCharacterRanges).map { slice, characterRange in
            LiveSelectionTextRunSlice(
                base: slice,
                characterRange: characterRange.offsetBySelection(by: offset)
            )
        }
    }
}


private struct EmptySelectionRun: SelectionTextRun, @unchecked Sendable {
    let layoutDirection: LayoutDirection = .leftToRight
    let typographicBounds: CGRect
    let slice: EmptySelectionRunSlice

    var slices: [any SelectionTextRunSlice] {
        [slice]
    }
}


private final class LiveSelectionTextRunSlice: SelectionTextRunSlice, @unchecked Sendable {
    var typographicBounds: CGRect {
        base.typographicBounds.rect
    }

    let characterRange: Range<Int>
    private let base: SwiftUI.Text.Layout.RunSlice

    init(base: SwiftUI.Text.Layout.RunSlice, characterRange: Range<Int>) {
        self.base = base
        self.characterRange = characterRange
    }
}


private struct EmptySelectionRunSlice: SelectionTextRunSlice, @unchecked Sendable {
    let typographicBounds: CGRect
    let characterRange: Range<Int>
}


private struct SelectionLayoutContents {
    let lineFragments: [NSTextLineFragment]
    let layoutAttributedStrings: [NSAttributedString]
    let attributedStrings: [NSAttributedString]
}


private extension SwiftUI.Text.Layout {
    func materializeSelectionContents() -> SelectionLayoutContents {
        let lineFragments = compactMap(\.selectionLineFragment)
        let layoutAttributedStrings = lineFragments
            .map(\.attributedString)
            .removingSelectionIdenticalDuplicates()

        return .init(
            lineFragments: lineFragments,
            layoutAttributedStrings: layoutAttributedStrings,
            attributedStrings: layoutAttributedStrings
        )
    }
}


private extension SwiftUI.Text.Layout.Line {
    var selectionLineFragment: NSTextLineFragment? {
        let mirror = Mirror(reflecting: self)
        if let fragment = mirror.descendant("_line", "nsLine", 0) as? NSTextLineFragment {
            return fragment
        }
        return mirror.descendant("_line", "nsLine") as? NSTextLineFragment
    }
}


private extension SwiftUI.Text.Layout.Run {
    var selectionCharacterRanges: [Range<Int>] {
        guard let ctRun = selectionCTRun else { return [] }

        let runRange = CTRunGetStringRange(ctRun)
        let start = runRange.location
        let end = start + runRange.length

        let characterIndices: [CFIndex]
        if let pointer = CTRunGetStringIndicesPtr(ctRun) {
            characterIndices = Array(UnsafeBufferPointer(start: pointer, count: count))
        } else {
            var temp = Array(repeating: 0 as CFIndex, count: count)
            CTRunGetStringIndices(ctRun, .init(), &temp)
            characterIndices = temp
        }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(count)

        for i in 0..<count {
            let characterIndex = characterIndices[i]
            let boundary: CFIndex

            if layoutDirection == .leftToRight {
                var j = i + 1
                while j < count, characterIndices[j] == characterIndex { j += 1 }
                boundary = (j < count) ? characterIndices[j] : end
            } else {
                var j = i - 1
                while j >= 0, characterIndices[j] == characterIndex { j -= 1 }
                boundary = (j >= 0) ? characterIndices[j] : end
            }

            let lowerBound = Swift.max(Swift.min(characterIndex, boundary), start)
            let upperBound = Swift.min(Swift.max(characterIndex, boundary), end)
            ranges.append(lowerBound..<upperBound)
        }

        return ranges
    }

    private var selectionCTRun: CTRun? {
        let mirror = Mirror(reflecting: self)
        guard
            let index = mirror.descendant("index") as? Int,
            let lineRef = mirror.descendant("line") as? CFTypeRef,
            CFGetTypeID(lineRef) == CTLineGetTypeID()
        else {
            return nil
        }

        let ctLine = unsafeDowncast(lineRef, to: CTLine.self)
        guard let ctRuns = CTLineGetGlyphRuns(ctLine) as? [CTRun], ctRuns.indices.contains(index) else {
            return nil
        }

        return ctRuns[index]
    }
}


private extension SelectionTextLayoutCollection {
    var startPosition: SelectionTextPosition {
        SelectionTextPosition(
            indexPath: .init(runSlice: 0, run: 0, line: 0, layout: 0),
            affinity: layouts.isEmpty ? .upstream : .downstream
        )
    }

    var endPosition: SelectionTextPosition {
        guard
            let layout = layouts.last,
            let line = layout.lines.last,
            let run = line.runs.last
        else {
            return startPosition
        }

        return SelectionTextPosition(
            indexPath: .init(
                runSlice: run.slices.endIndex - 1,
                run: line.runs.endIndex - 1,
                line: layout.lines.endIndex - 1,
                layout: layouts.endIndex - 1
            ),
            affinity: .upstream
        )
    }

    var stringLength: Int {
        layouts.map(\.attributedString.length).reduce(0, +)
    }

    func localCharacterRange(at indexPath: IndexPath) -> Range<Int>? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        let line = layouts[components.layout].lines[components.line]
        return line.runs[components.run].slices[components.runSlice].characterRange
    }

    func localCharacterIndex(at position: SelectionTextPosition) -> Int? {
        guard let range = localCharacterRange(at: position.indexPath) else {
            return nil
        }

        switch position.affinity {
        case .downstream:
            return range.lowerBound
        case .upstream:
            return range.upperBound
        }
    }

    func characterIndex(at position: SelectionTextPosition) -> Int? {
        guard
            let components = position.indexPath.selectionComponents,
            let localCharacterIndex = localCharacterIndex(at: position)
        else {
            return nil
        }

        let base = layouts.prefix(components.layout)
            .map(\.attributedString.length)
            .reduce(0, +)
        return base + localCharacterIndex
    }

    func position(from position: SelectionTextPosition, offset: Int) -> SelectionTextPosition? {
        guard let source = characterIndex(at: position) else {
            return nil
        }

        let target = source + offset

        guard (0...stringLength).contains(target) else {
            return nil
        }

        var localTarget = target
        var layoutIndex = 0
        while layoutIndex < layouts.count {
            let length = layouts[layoutIndex].attributedString.length
            guard localTarget > length else {
                break
            }
            localTarget -= length
            layoutIndex += 1
        }

        guard layoutIndex < layouts.count else {
            return endPosition
        }

        return self.position(at: layoutIndex, localCharacterIndex: localTarget)
    }

    func position(at layoutIndex: Int, localCharacterIndex: Int) -> SelectionTextPosition? {
        guard layouts.indices.contains(layoutIndex) else { return nil }

        guard localCharacterIndex > 0 else {
            return SelectionTextPosition(indexPath: .init(layout: layoutIndex), affinity: .downstream)
        }

        let layout = layouts[layoutIndex]
        let stringLength = layout.attributedString.length

        guard localCharacterIndex <= stringLength else {
            guard let line = layout.lines.last, let run = line.runs.last else {
                return SelectionTextPosition(
                    indexPath: .init(runSlice: 0, run: 0, line: 0, layout: layoutIndex),
                    affinity: .upstream
                )
            }

            return SelectionTextPosition(
                indexPath: .init(
                    runSlice: run.slices.endIndex - 1,
                    run: line.runs.endIndex - 1,
                    line: layout.lines.endIndex - 1,
                    layout: layoutIndex
                ),
                affinity: .upstream
            )
        }

        for (lineIndex, line) in zip(layout.lines.indices, layout.lines) {
            for (runIndex, run) in zip(line.runs.indices, line.runs) {
                for (sliceIndex, slice) in zip(run.slices.indices, run.slices) {
                    if slice.characterRange.contains(localCharacterIndex) {
                        return SelectionTextPosition(
                            indexPath: .init(
                                runSlice: sliceIndex,
                                run: runIndex,
                                line: lineIndex,
                                layout: layoutIndex
                            ),
                            affinity: .downstream
                        )
                    } else if slice.characterRange.upperBound == localCharacterIndex {
                        return SelectionTextPosition(
                            indexPath: .init(
                                runSlice: sliceIndex,
                                run: runIndex,
                                line: lineIndex,
                                layout: layoutIndex
                            ),
                            affinity: .upstream
                        )
                    }
                }
            }
        }

        return nil
    }

    func reconcileRange(
        _ range: SelectionTextRange,
        from other: any SelectionTextLayoutCollection
    ) -> SelectionTextRange? {
        guard
            layouts.count == other.layouts.count,
            let startLayout = range.start.indexPath.selectionComponents?.layout,
            let startLocalCharacterIndex = other.localCharacterIndex(at: range.start),
            let start = position(
                at: startLayout,
                localCharacterIndex: startLocalCharacterIndex
            ),
            let endLayout = range.end.indexPath.selectionComponents?.layout,
            let endLocalCharacterIndex = other.localCharacterIndex(at: range.end),
            let end = position(
                at: endLayout,
                localCharacterIndex: endLocalCharacterIndex
            )
        else {
            return nil
        }

        return SelectionTextRange(start: start, end: end)
    }

    func attributedText(in range: SelectionTextRange) -> NSAttributedString {
        guard !range.isCollapsed else { return NSAttributedString() }

        let result = NSMutableAttributedString()

        guard
            let startLayout = range.start.indexPath.selectionComponents?.layout,
            let endLayout = range.end.indexPath.selectionComponents?.layout,
            layouts.indices.contains(startLayout),
            layouts.indices.contains(endLayout)
        else {
            return result
        }

        for layoutIndex in startLayout...endLayout {
            let attributedString = layouts[layoutIndex].attributedString
            let lowerBound = layoutIndex == startLayout ? (localCharacterIndex(at: range.start) ?? 0) : 0
            let upperBound = layoutIndex == endLayout ? (localCharacterIndex(at: range.end) ?? attributedString.length) : attributedString.length

            if lowerBound < upperBound {
                result.append(
                    attributedString.attributedSubstring(from: NSRange(lowerBound..<upperBound))
                )
            }
        }

        return result
    }

    func plainText(in range: SelectionTextRange) -> String {
        guard !range.isCollapsed else { return "" }

        guard
            let startLayout = range.start.indexPath.selectionComponents?.layout,
            let endLayout = range.end.indexPath.selectionComponents?.layout,
            layouts.indices.contains(startLayout),
            layouts.indices.contains(endLayout)
        else {
            return ""
        }

        var text = ""
        var previousLayoutIndex: Int?

        for layoutIndex in startLayout...endLayout {
            let attributedString = layouts[layoutIndex].attributedString
            let lowerBound = layoutIndex == startLayout ? (localCharacterIndex(at: range.start) ?? 0) : 0
            let upperBound = layoutIndex == endLayout ? (localCharacterIndex(at: range.end) ?? attributedString.length) : attributedString.length

            guard lowerBound < upperBound else {
                continue
            }

            let substring = attributedString.attributedSubstring(from: NSRange(lowerBound..<upperBound)).string
            guard !substring.isEmpty else {
                continue
            }

            if
                let previousLayoutIndex,
                let separator = plainTextSeparator(
                    betweenLayoutAt: previousLayoutIndex,
                    andLayoutAt: layoutIndex,
                    existingText: text,
                    upcomingText: substring
                )
            {
                text += separator
            }

            text += substring
            previousLayoutIndex = layoutIndex
        }

        return text
    }

    func firstRect(for range: SelectionTextRange) -> CGRect {
        guard !range.isCollapsed else {
            return caretRect(for: range.start)
        }

        var firstRect = CGRect.null
        guard let startComponents = range.start.indexPath.selectionComponents else {
            return firstRect
        }

        let layout = startComponents.layout
        let line = startComponents.line

        for indexPath in indexPathsForRunSlices(in: range) {
            guard indexPath.layout == layout, indexPath.line == line else {
                break
            }
            guard let selectionRect = runSliceSelectionRect(at: indexPath) else {
                continue
            }
            firstRect = firstRect.union(selectionRect)
        }

        return firstRect
    }

    func selectionRects(for range: SelectionTextRange) -> [SelectionRect] {
        guard !range.isCollapsed else { return [] }

        guard
            let startComponents = range.start.indexPath.selectionComponents,
            let endComponents = range.end.indexPath.selectionComponents
        else {
            return []
        }

        let startX = caretRect(for: range.start).minX
        let endX = caretRect(for: range.end).minX

        let start = range.start.indexPath
        let end = range.end.indexPath

        var selectionRects: [SelectionRect] = []
        var currentLayout: Int?
        var builder: SelectionRectBuilder?

        func flushRects() {
            selectionRects += builder?.rects() ?? []
            builder = nil
        }

        for indexPath in indexPathsForRunSlices(in: range) {
            if currentLayout != indexPath.layout {
                flushRects()
                currentLayout = indexPath.layout
                builder = .init(
                    start: indexPath.layout == startComponents.layout ? start : nil,
                    end: indexPath.layout == endComponents.layout ? end : nil,
                    startX: startX,
                    endX: endX
                )
            }

            guard let rect = runSliceSelectionRect(at: indexPath) else {
                continue
            }
            let direction = layoutDirection(at: indexPath)
            builder?.appendRect(rect, layoutDirection: direction, line: indexPath.line)
        }

        flushRects()

        guard !selectionRects.isEmpty else { return [] }

        selectionRects[0].containsStart = true
        selectionRects[selectionRects.count - 1].containsEnd = true

        return selectionRects
    }

    func layoutDirection(at indexPath: IndexPath) -> LayoutDirection {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return .leftToRight
        }

        let line = layouts[components.layout].lines[components.line]
        return line.runs[components.run].layoutDirection
    }

    func indexPathsForRunSlices(in range: SelectionTextRange) -> some Sequence<IndexPath> {
        SelectionIndexPathSequence(
            range: range,
            next: indexPathForRunSlice(after:),
            previous: indexPathForRunSlice(before:)
        )
    }

    func caretRect(for position: SelectionTextPosition) -> CGRect {
        guard
            let runSliceRect = runSliceRect(at: position.indexPath),
            let lineRect = lineRect(at: position.indexPath)
        else {
            return .zero
        }

        let direction = layoutDirection(at: position.indexPath)

        let x =
            (position.affinity == .downstream)
            ? runSliceRect.leadingEdgeX(for: direction)
            : runSliceRect.trailingEdgeX(for: direction)

        return CGRect(x: x, y: lineRect.minY, width: 1, height: lineRect.height)
    }

    func closestPosition(to point: CGPoint) -> SelectionTextPosition? {
        guard !layouts.isEmpty else { return nil }

        let layoutIndex = layoutIndex(closestTo: point)
        let layout = layouts[layoutIndex]

        guard !layout.lines.isEmpty else { return nil }

        let localPoint = CGPoint(
            x: point.x - layout.origin.x,
            y: point.y - layout.origin.y
        )

        let lineIndex = layout.lineIndex(closestToY: localPoint.y)
        let line = layout.lines[lineIndex]
        let runIndex = line.runIndex(closestToX: localPoint.x)
        let run = line.runs[runIndex]
        let direction = run.layoutDirection
        let runSliceIndex = run.sliceIndex(closestToX: localPoint.x)
        let runSlice = run.slices[runSliceIndex]

        let leadingDistance = abs(localPoint.x - runSlice.typographicBounds.leadingEdgeX(for: direction))
        let trailingDistance = abs(localPoint.x - runSlice.typographicBounds.trailingEdgeX(for: direction))

        return SelectionTextPosition(
            indexPath: .init(
                runSlice: runSliceIndex,
                run: runIndex,
                line: lineIndex,
                layout: layoutIndex
            ),
            affinity: (leadingDistance <= trailingDistance) ? .downstream : .upstream
        )
    }

    func characterRange(at point: CGPoint) -> SelectionTextRange? {
        guard !layouts.isEmpty else { return nil }

        let layoutIndex = layoutIndex(closestTo: point)
        let layout = layouts[layoutIndex]
        guard !layout.lines.isEmpty else { return nil }

        let localPoint = CGPoint(
            x: point.x - layout.origin.x,
            y: point.y - layout.origin.y
        )

        let lineIndex = layout.lineIndex(closestToY: localPoint.y)
        let line = layout.lines[lineIndex]
        let runIndex = line.runIndex(closestToX: localPoint.x)
        let run = line.runs[runIndex]
        let runSliceIndex = run.sliceIndex(closestToX: localPoint.x)

        let start = SelectionTextPosition(
            indexPath: .init(
                runSlice: runSliceIndex,
                run: runIndex,
                line: lineIndex,
                layout: layoutIndex
            ),
            affinity: .downstream
        )
        let end = SelectionTextPosition(
            indexPath: .init(
                runSlice: runSliceIndex,
                run: runIndex,
                line: lineIndex,
                layout: layoutIndex
            ),
            affinity: .upstream
        )

        return SelectionTextRange(start: start, end: end)
    }

    func runSliceSelectionRect(at indexPath: IndexPath) -> CGRect? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        let layout = layouts[components.layout]
        let line = layout.lines[components.line]
        let runSlice = line.runs[components.run].slices[components.runSlice]

        var rect = runSlice.typographicBounds
        rect.origin.y = line.typographicBounds.minY
        rect.size.height = line.typographicBounds.height

        return rect.offsetBy(dx: layout.origin.x, dy: layout.origin.y)
    }

    private func runSliceRect(at indexPath: IndexPath) -> CGRect? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        let layout = layouts[components.layout]
        let runSlice = layout.lines[components.line].runs[components.run].slices[components.runSlice]
        return runSlice.typographicBounds.offsetBy(dx: layout.origin.x, dy: layout.origin.y)
    }

    private func lineRect(at indexPath: IndexPath) -> CGRect? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        let layout = layouts[components.layout]
        let line = layout.lines[components.line]
        return line.typographicBounds.offsetBy(dx: layout.origin.x, dy: layout.origin.y)
    }

    private func layoutIndex(closestTo point: CGPoint) -> Int {
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, layout) in zip(layouts.indices, layouts) {
            let distance = layout.frame.distanceSquared(to: point)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        return closestIndex
    }

    private func indexPathForRunSlice(after indexPath: IndexPath) -> IndexPath? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        let layout = layouts[components.layout]
        let line = layout.lines[components.line]
        let run = line.runs[components.run]

        if components.runSlice + 1 < run.slices.count {
            return IndexPath(
                runSlice: components.runSlice + 1,
                run: components.run,
                line: components.line,
                layout: components.layout
            )
        }

        if components.run + 1 < line.runs.count {
            return IndexPath(run: components.run + 1, line: components.line, layout: components.layout)
        }

        if components.line + 1 < layout.lines.count {
            return IndexPath(line: components.line + 1, layout: components.layout)
        }

        if components.layout + 1 < layouts.count {
            return IndexPath(layout: components.layout + 1)
        }

        return nil
    }

    func textHitRects() -> [CGRect] {
        var rects: [CGRect] = []
        rects.reserveCapacity(layouts.count * 4)

        for layout in layouts {
            for line in layout.lines {
                var rect = line.typographicBounds.offsetBy(dx: layout.origin.x, dy: layout.origin.y)
                guard rect.width > 0, rect.height > 0 else {
                    continue
                }

                // Expand hit target so users can start selection near text, not only on glyph pixels.
                rect = rect.insetBy(dx: -8, dy: -4)
                rects.append(rect)
            }
        }

        return rects
    }

    func containsText(at point: CGPoint) -> Bool {
        textHitRects().contains { $0.contains(point) }
    }

    private func indexPathForRunSlice(before indexPath: IndexPath) -> IndexPath? {
        guard let components = resolvedSelectionPath(for: indexPath) else {
            return nil
        }

        if components.runSlice > 0 {
            return IndexPath(
                runSlice: components.runSlice - 1,
                run: components.run,
                line: components.line,
                layout: components.layout
            )
        }

        if components.run > 0 {
            let previousRun = layouts[components.layout].lines[components.line].runs[components.run - 1]
            return IndexPath(
                runSlice: previousRun.slices.endIndex - 1,
                run: components.run - 1,
                line: components.line,
                layout: components.layout
            )
        }

        if components.line > 0 {
            let previousLine = layouts[components.layout].lines[components.line - 1]
            let lastRunIndex = previousLine.runs.endIndex - 1
            let lastRun = previousLine.runs[lastRunIndex]

            return IndexPath(
                runSlice: lastRun.slices.endIndex - 1,
                run: lastRunIndex,
                line: components.line - 1,
                layout: components.layout
            )
        }

        if components.layout > 0 {
            let previousLayout = layouts[components.layout - 1]
            let lastLineIndex = previousLayout.lines.endIndex - 1
            let lastLine = previousLayout.lines[lastLineIndex]
            let lastRunIndex = lastLine.runs.endIndex - 1
            let lastRun = lastLine.runs[lastRunIndex]

            return IndexPath(
                runSlice: lastRun.slices.endIndex - 1,
                run: lastRunIndex,
                line: lastLineIndex,
                layout: components.layout - 1
            )
        }

        return nil
    }

    private func resolvedSelectionPath(for indexPath: IndexPath) -> SelectionPathComponents? {
        guard
            let components = indexPath.selectionComponents,
            layouts.indices.contains(components.layout)
        else {
            return nil
        }

        let layout = layouts[components.layout]
        guard layout.lines.indices.contains(components.line) else {
            return nil
        }

        let line = layout.lines[components.line]
        guard line.runs.indices.contains(components.run) else {
            return nil
        }

        let run = line.runs[components.run]
        guard run.slices.indices.contains(components.runSlice) else {
            return nil
        }

        return components
    }

    private func plainTextSeparator(
        betweenLayoutAt previousIndex: Int,
        andLayoutAt currentIndex: Int,
        existingText: String,
        upcomingText: String
    ) -> String? {
        guard
            layouts.indices.contains(previousIndex),
            layouts.indices.contains(currentIndex)
        else {
            return nil
        }

        guard
            let lastCharacter = existingText.last,
            let nextCharacter = upcomingText.first,
            !lastCharacter.isNewline,
            !nextCharacter.isNewline
        else {
            return nil
        }

        let previousFrame = layouts[previousIndex].frame
        let currentFrame = layouts[currentIndex].frame

        if currentFrame.minY - previousFrame.maxY > 1 {
            return "\n"
        }

        return nil
    }
}


private struct SelectionRectBuilder {
    let start: IndexPath?
    let end: IndexPath?
    let startX: CGFloat
    let endX: CGFloat

    private var lines: [[SelectionRect]] = []
    private var currentLine: Int?
    private var currentLineRects: [SelectionRect] = []

    init(
        start: IndexPath?,
        end: IndexPath?,
        startX: CGFloat,
        endX: CGFloat
    ) {
        self.start = start
        self.end = end
        self.startX = startX
        self.endX = endX
    }

    mutating func appendRect(_ rect: CGRect, layoutDirection: LayoutDirection, line: Int) {
        if currentLine != line {
            appendCurrentLine()
            currentLine = line
        }

        if let last = currentLineRects.indices.last,
           currentLineRects[last].layoutDirection == layoutDirection {
            currentLineRects[last].rect = currentLineRects[last].rect.union(rect)
        } else {
            currentLineRects.append(.init(rect: rect, layoutDirection: layoutDirection))
        }
    }

    mutating func rects() -> [SelectionRect] {
        appendCurrentLine()
        guard !lines.isEmpty else {
            return []
        }

        lines.inflateSelectionLines()
        return lines.flatMap(\.self)
    }

    private mutating func appendCurrentLine() {
        guard let currentLine, !currentLineRects.isEmpty else {
            currentLineRects.removeAll(keepingCapacity: true)
            self.currentLine = nil
            return
        }

        if let start, start.line == currentLine {
            let span = currentLineRects.selectionIndex(containing: startX) ?? currentLineRects.startIndex
            currentLineRects[span].trimSelectionLeading(to: startX)
        }

        if let end, end.line == currentLine {
            let span =
                currentLineRects.selectionIndex(containing: endX)
                ?? currentLineRects.index(before: currentLineRects.endIndex)
            currentLineRects[span].trimSelectionTrailing(to: endX)
        }

        lines.append(currentLineRects)
        currentLineRects.removeAll(keepingCapacity: true)
        self.currentLine = nil
    }
}


private extension IndexPath {
    var selectionComponents: SelectionPathComponents? {
        guard count >= 4 else {
            return nil
        }

        return .init(
            layout: self[0],
            line: self[1],
            run: self[2],
            runSlice: self[3]
        )
    }

    var layout: Int {
        selectionComponents?.layout ?? 0
    }

    var line: Int {
        selectionComponents?.line ?? 0
    }

    var run: Int {
        selectionComponents?.run ?? 0
    }

    var runSlice: Int {
        selectionComponents?.runSlice ?? 0
    }

    init(runSlice: Int, run: Int, line: Int, layout: Int) {
        self.init(indexes: [layout, line, run, runSlice])
    }

    init(run: Int, line: Int, layout: Int) {
        self.init(runSlice: 0, run: run, line: line, layout: layout)
    }

    init(line: Int, layout: Int) {
        self.init(runSlice: 0, run: 0, line: line, layout: layout)
    }

    init(layout: Int) {
        self.init(runSlice: 0, run: 0, line: 0, layout: layout)
    }
}


private extension SelectionTextLayout {
    var frame: CGRect {
        bounds.offsetBy(dx: origin.x, dy: origin.y)
    }
}


private extension SelectionTextLayout {
    func lineIndex(closestToY y: CGFloat) -> Int {
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, line) in lines.enumerated() {
            let distance = line.typographicBounds.verticalDistance(to: y)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        return closestIndex
    }
}


private extension SelectionTextLine {
    func runIndex(closestToX x: CGFloat) -> Int {
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, run) in runs.enumerated() {
            let distance = run.typographicBounds.horizontalDistance(to: x)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        return closestIndex
    }
}


private extension SelectionTextRun {
    func sliceIndex(closestToX x: CGFloat) -> Int {
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, slice) in slices.enumerated() {
            let distance = slice.typographicBounds.horizontalDistance(to: x)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        return closestIndex
    }
}


private extension SelectionRect {
    mutating func trimSelectionLeading(to caretX: CGFloat) {
        if layoutDirection == .leftToRight {
            let minX = max(rect.minX, caretX)
            rect.size.width = max(0, rect.maxX - minX)
            rect.origin.x = minX
        } else {
            let maxX = max(rect.minX, caretX)
            rect.size.width = Swift.max(0, maxX - rect.minX)
        }
    }

    mutating func trimSelectionTrailing(to caretX: CGFloat) {
        if layoutDirection == .leftToRight {
            let maxX = max(rect.minX, caretX)
            rect.size.width = Swift.max(0, maxX - rect.minX)
        } else {
            let minX = Swift.min(rect.maxX, caretX)
            rect.size.width = Swift.max(0, rect.maxX - minX)
            rect.origin.x = minX
        }
    }
}


private extension Array where Element == [SelectionRect] {
    mutating func inflateSelectionLines() {
        var previousMaxY: CGFloat?

        for line in indices {
            guard !self[line].isEmpty else {
                continue
            }

            if let previousMaxY {
                let lineMinY = self[line][0].rect.minY
                if lineMinY > previousMaxY {
                    let gap = lineMinY - previousMaxY
                    for span in self[line].indices {
                        self[line][span].rect.origin.y -= gap
                        self[line][span].rect.size.height += gap
                    }
                }
            }

            previousMaxY = self[line][0].rect.maxY
        }
    }
}


private extension Array where Element == SelectionRect {
    func selectionIndex(containing caretX: CGFloat) -> Int? {
        firstIndex {
            ($0.rect.minX...$0.rect.maxX).contains(caretX)
        }
    }
}


private extension CGRect {
    func leadingEdgeX(for layoutDirection: LayoutDirection) -> CGFloat {
        layoutDirection == .leftToRight ? minX : maxX
    }

    func trailingEdgeX(for layoutDirection: LayoutDirection) -> CGFloat {
        layoutDirection == .leftToRight ? maxX : minX
    }

    func verticalDistance(to y: CGFloat) -> CGFloat {
        if y < minY { return minY - y }
        if y > maxY { return y - maxY }
        return 0
    }

    func horizontalDistance(to x: CGFloat) -> CGFloat {
        if x < minX { return minX - x }
        if x > maxX { return x - maxX }
        return 0
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = horizontalDistance(to: point.x)
        let dy = verticalDistance(to: point.y)
        return dx * dx + dy * dy
    }
}


private extension Array where Element: AnyObject {
    func removingSelectionIdenticalDuplicates() -> Self {
        var identifiers: Set<ObjectIdentifier> = []
        var result: Self = []

        result.reserveCapacity(underestimatedCount)

        for element in self {
            if identifiers.insert(.init(element)).inserted {
                result.append(element)
            }
        }

        return result
    }
}


private extension Array where Element == NSAttributedString {
    func joinedForSelection() -> (joined: NSAttributedString, characterOffsets: [ObjectIdentifier: Int]) {
        guard !isEmpty else {
            let attributedString = NSAttributedString()
            return (attributedString, [ObjectIdentifier(attributedString): 0])
        }

        guard count > 1 else {
            return (self[0], [ObjectIdentifier(self[0]): 0])
        }

        let joined = NSMutableAttributedString()
        var characterOffsets: [ObjectIdentifier: Int] = [:]
        characterOffsets.reserveCapacity(underestimatedCount)

        var offset = 0
        for element in self {
            joined.append(element)
            characterOffsets[ObjectIdentifier(element)] = offset
            offset += element.length
        }

        return (joined, characterOffsets)
    }
}


private extension Range where Bound == Int {
    func offsetBySelection(by value: Int) -> Range<Int> {
        (lowerBound + value)..<(upperBound + value)
    }
}

#endif
