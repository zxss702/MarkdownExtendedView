// SelectionAutoScroll.swift
// MarkdownExtendedView
//
//  Continuous auto-scroll while a selection drag sits near the edge of
//  the nearest enclosing scroll view. A hit-transparent bridge view
//  fills the selectable container so its local space matches the
//  document space the selection model uses. A common-mode timer ticks
//  while `isDragging` (drags run the loop in .eventTracking — a default
//  timer would never fire): each tick scrolls the clip view, then
//  re-feeds the pointer position, because a stationary cursor emits no
//  gesture events — the timer is what extends the selection during
//  scroll.

import SwiftUI

#if canImport(AppKit)
import AppKit

struct SelectionAutoScrollBridge: NSViewRepresentable {
    var isDragging: Bool
    /// Latest drag location in container space — fallback when the
    /// window/mouse position is unavailable (also the iOS input path).
    var dragPoint: CGPoint
    var onDrag: (CGPoint) -> Void

    func makeNSView(context: Context) -> SelectionAutoScrollView {
        SelectionAutoScrollView()
    }

    func updateNSView(_ nsView: SelectionAutoScrollView, context: Context) {
        nsView.onDrag = onDrag
        nsView.dragPoint = dragPoint
        nsView.isDragging = isDragging
    }
}

final class SelectionAutoScrollView: NSView {
    var onDrag: ((CGPoint) -> Void)?
    var dragPoint: CGPoint = .zero

    var isDragging = false {
        didSet {
            if isDragging { startTimer() } else { stopTimer() }
        }
    }

    /// Distance from the visible edge where scrolling engages.
    private let edgeBand: CGFloat = 28
    /// Fastest scroll step per tick (~60 Hz → up to ~960 pt/s).
    private let maxStep: CGFloat = 16
    /// Boxed so `deinit` (nonisolated) can reach the timer.
    private final class TimerBox: @unchecked Sendable { var value: Timer? }
    private let timerBox = TimerBox()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// Never intercept — hit testing falls through to the container.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTimer() }
    }

    private func startTimer() {
        guard timerBox.value == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop — assumeIsolated keeps
            // the tick synchronous.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timerBox.value = timer
    }

    private func stopTimer() {
        timerBox.value?.invalidate()
        timerBox.value = nil
    }

    private func tick() {
        guard isDragging, let scrollView = enclosingScrollView else {
            stopTimer()
            return
        }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return }

        // Prefer the live cursor position; fall back to the last
        // container-space drag point converted through the window.
        let windowPoint = window.map {
            $0.convertFromScreen(NSRect(origin: NSEvent.mouseLocation, size: .zero)).origin
        } ?? convert(dragPoint, to: nil)
        // A point converted into the clip view lands in document space —
        // the clip view's coordinate origin is the scroll position.
        let documentPoint = clipView.convert(windowPoint, from: nil)
        let visible = clipView.documentVisibleRect
        let flipped = documentView.isFlipped

        var origin = clipView.bounds.origin
        var scrolled = false

        if clipView.documentRect.height > visible.height + 0.5 {
            // Flipped documents grow downward: the top edge is `minY`.
            let topGap = flipped ? documentPoint.y - visible.minY : visible.maxY - documentPoint.y
            let bottomGap = flipped ? visible.maxY - documentPoint.y : documentPoint.y - visible.minY
            if let dy = scrollStep(topGap: topGap, bottomGap: bottomGap) {
                origin.y += dy
            }
        }
        if clipView.documentRect.width > visible.width + 0.5 {
            // Horizontal documents are never flipped on x.
            let leftGap = documentPoint.x - visible.minX
            let rightGap = visible.maxX - documentPoint.x
            if let dx = scrollStep(topGap: leftGap, bottomGap: rightGap) {
                origin.x += dx
            }
        }

        // Clamp to the clip view's true scroll range — `constrainBoundsRect`
        // accounts for content insets (e.g. safeAreaInset bars), where the
        // resting origin can be negative. A manual `max(0, …)` clamp would
        // snap a negative resting origin up to 0 — a visible jump.
        let constrained = clipView.constrainBoundsRect(
            NSRect(origin: origin, size: clipView.bounds.size)
        )
        origin = constrained.origin
        scrolled = origin != clipView.bounds.origin

        if scrolled {
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        // The cursor may not have moved — feed the (newly scrolled)
        // pointer position so the selection keeps advancing.
        onDrag?(convert(windowPoint, from: nil))
    }

    /// Step toward the pointer when it sits inside the edge band;
    /// deeper penetration scrolls faster. Nil outside the band.
    private func scrollStep(topGap: CGFloat, bottomGap: CGFloat) -> CGFloat? {
        if topGap < edgeBand {
            return -min(maxStep, (edgeBand - topGap) * 0.5 + 2)
        }
        if bottomGap < edgeBand {
            return min(maxStep, (edgeBand - bottomGap) * 0.5 + 2)
        }
        return nil
    }

    deinit {
        let box = timerBox
        // `invalidate` must run on the timer's run loop.
        Task { @MainActor in box.value?.invalidate() }
    }
}

#elseif canImport(UIKit)
import UIKit

struct SelectionAutoScrollBridge: UIViewRepresentable {
    var isDragging: Bool
    /// Latest drag location in container space — touch input has no
    /// `NSEvent.mouseLocation`, so the modifier feeds it every move.
    var dragPoint: CGPoint
    var onDrag: (CGPoint) -> Void

    func makeUIView(context: Context) -> SelectionAutoScrollView {
        SelectionAutoScrollView()
    }

    func updateUIView(_ uiView: SelectionAutoScrollView, context: Context) {
        uiView.onDrag = onDrag
        uiView.dragPoint = dragPoint
        uiView.isDragging = isDragging
    }
}

final class SelectionAutoScrollView: UIView {
    var onDrag: ((CGPoint) -> Void)?
    var dragPoint: CGPoint = .zero

    var isDragging = false {
        didSet {
            if isDragging { startTimer() } else { stopTimer() }
        }
    }

    private let edgeBand: CGFloat = 28
    private let maxStep: CGFloat = 16
    private final class TimerBox: @unchecked Sendable { var value: Timer? }
    private let timerBox = TimerBox()

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    private var scrollView: UIScrollView? {
        sequence(first: superview, next: { $0?.superview })
            .compactMap { $0 }
            .first { $0 is UIScrollView } as? UIScrollView
    }

    private func startTimer() {
        guard timerBox.value == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timerBox.value = timer
    }

    private func stopTimer() {
        timerBox.value?.invalidate()
        timerBox.value = nil
    }

    private func tick() {
        guard isDragging, let scrollView else {
            stopTimer()
            return
        }

        let point = scrollView.convert(dragPoint, from: self)
        let visible = scrollView.bounds
        var offset = scrollView.contentOffset
        var scrolled = false

        if scrollView.contentSize.height > visible.height + 0.5 {
            let topGap = point.y - visible.minY
            let bottomGap = visible.maxY - point.y
            if let dy = scrollStep(topGap: topGap, bottomGap: bottomGap) {
                offset.y += dy
            }
        }
        if scrollView.contentSize.width > visible.width + 0.5 {
            let leftGap = point.x - visible.minX
            let rightGap = visible.maxX - point.x
            if let dx = scrollStep(topGap: leftGap, bottomGap: rightGap) {
                offset.x += dx
            }
        }

        // Clamp to the content extent — no rubber-band over-scroll.
        let inset = scrollView.adjustedContentInset
        offset.y = min(max(offset.y, -inset.top), max(-inset.top, scrollView.contentSize.height - visible.height + inset.bottom))
        offset.x = min(max(offset.x, -inset.left), max(-inset.left, scrollView.contentSize.width - visible.width + inset.right))
        scrolled = offset != scrollView.contentOffset

        if scrolled {
            scrollView.setContentOffset(offset, animated: false)
        }
        onDrag?(scrollView.convert(point, to: self))
    }

    private func scrollStep(topGap: CGFloat, bottomGap: CGFloat) -> CGFloat? {
        if topGap < edgeBand {
            return -min(maxStep, (edgeBand - topGap) * 0.5 + 2)
        }
        if bottomGap < edgeBand {
            return min(maxStep, (edgeBand - bottomGap) * 0.5 + 2)
        }
        return nil
    }

    deinit {
        let box = timerBox
        Task { @MainActor in box.value?.invalidate() }
    }
}
#endif
