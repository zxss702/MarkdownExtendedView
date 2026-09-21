// WindowDeselectHandler.swift
// MarkdownExtendedView
//
//  Window-level event monitor for the selectable container: clicks
//  clear the selection, Cmd+C copies it, Cmd+A selects everything.

import SwiftUI
#if canImport(AppKit)
import AppKit

struct WindowDeselectHandler: NSViewRepresentable {
    let onDeselect: () -> Void
    let onCopy: () -> Bool
    let onSelectAll: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = DeselectMonitorView()
        view.onDeselect = onDeselect
        view.onCopy = onCopy
        view.onSelectAll = onSelectAll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? DeselectMonitorView {
            view.onDeselect = onDeselect
            view.onCopy = onCopy
            view.onSelectAll = onSelectAll
        }
    }
}

class DeselectMonitorView: NSView {
    var onDeselect: (() -> Void)?
    var onCopy: (() -> Bool)?
    var onSelectAll: (() -> Bool)?

    private final class MonitorBox: @unchecked Sendable {
        var value: Any?
    }
    private let monitorBox = MonitorBox()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if monitorBox.value != nil {
            NSEvent.removeMonitor(monitorBox.value!)
            monitorBox.value = nil
        }

        if window != nil {
            monitorBox.value = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                guard let self = self else { return event }

                if event.type == .keyDown {
                    guard event.modifierFlags.contains(.command) else {
                        return event
                    }
                    // Cmd+C → copy; Cmd+A → select all (keyCodes 8 / 0).
                    if event.keyCode == 8, self.onCopy?() == true {
                        return nil
                    }
                    if event.keyCode == 0, self.onSelectAll?() == true {
                        return nil
                    }
                    return event
                }

                // Any click starts a potential new selection — clear the old one.
                self.onDeselect?()
                return event
            }
        }
    }

    deinit {
        let box = monitorBox
        if let m = box.value {
            Task { @MainActor in
                NSEvent.removeMonitor(m)
            }
        }
    }
}
#endif
