// WindowDeselectHandler.swift
// MarkdownExtendedView

import SwiftUI
#if canImport(AppKit)
import AppKit

struct WindowDeselectHandler: NSViewRepresentable {
    let onDeselect: () -> Void
    let onCopy: () -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = DeselectMonitorView()
        view.onDeselect = onDeselect
        view.onCopy = onCopy
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? DeselectMonitorView {
            view.onDeselect = onDeselect
            view.onCopy = onCopy
        }
    }
}

class DeselectMonitorView: NSView {
    var onDeselect: (() -> Void)?
    var onCopy: (() -> Bool)?
    
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
                    // Check for Cmd+C (Key code for 'c' is 8, modifier flags include command)
                    if event.modifierFlags.contains(.command) && event.keyCode == 8 {
                        if self.onCopy?() == true {
                            return nil // consume the event if we handled it
                        }
                    }
                    return event
                }
                
                // Check if the click is inside this view's bounds
                let pointInWindow = event.locationInWindow
                let pointInView = self.convert(pointInWindow, from: nil)
                
                if !self.bounds.contains(pointInView) {
                    self.onDeselect?()
                } else {
                    self.onDeselect?()
                }
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
