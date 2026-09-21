// MarkdownCopy.swift
//  MarkdownExtendedView
//
//  Shared pasteboard helpers for the block context menus — plain text,
//  and platform images (tiff + png on macOS so both Apple and cross
//  platform targets can paste).

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownCopy {

    static func text(_ string: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }

    static func image(_ image: MTImage) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        {
            pasteboard.setData(png, forType: .png)
        }
        #elseif canImport(UIKit)
        UIPasteboard.general.image = image
        #endif
    }
}
