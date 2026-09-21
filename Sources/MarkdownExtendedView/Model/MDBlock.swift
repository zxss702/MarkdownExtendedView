// MDBlock.swift
//  MarkdownExtendedView
//
//  Flattened render model. Produced once per content change inside
//  `MarkdownView.init` by `MarkdownFlattener`; the view body only maps
//  these values to views without walking the Markdown AST again.

import Foundation
@preconcurrency import Markdown

// MARK: - Block

/// A flattened top-level Markdown block. `id` is kept stable across
/// streaming updates by matching kind (same position) or signature
/// (same content elsewhere).
struct MDBlock: Identifiable {
    let id: UUID
    let kind: String
    let signature: String
    let content: MDBlockContent
}

extension MDBlock: Equatable {
    static func == (lhs: MDBlock, rhs: MDBlock) -> Bool {
        lhs.id == rhs.id && lhs.signature == rhs.signature
    }
}

/// Render-bucketed block kinds — the renderer `switch`es on these
/// directly; there is no secondary dispatch in `body`.
enum MDBlockContent {
    case heading(level: Int, AttributedString)
    case text(AttributedString)
    case image(MDImage)
    case codeBlock(MDCodeBlock)
    case latexBlock(String)
    case mermaid(code: String)
    case blockQuote(children: [MDBlock])
    case orderedList(startIndex: Int, items: [MDListItem])
    case unorderedList(items: [MDListItem])
    case table(MDTable)
    case thematicBreak
    case htmlBlock(rawHTML: String)

    var kind: String {
        switch self {
        case .heading(let level, _): return "heading\(level)"
        case .text: return "text"
        case .image: return "image"
        case .codeBlock: return "codeBlock"
        case .latexBlock: return "latexBlock"
        case .mermaid: return "mermaid"
        case .blockQuote: return "blockQuote"
        case .orderedList: return "orderedList"
        case .unorderedList: return "unorderedList"
        case .table: return "table"
        case .thematicBreak: return "thematicBreak"
        case .htmlBlock: return "htmlBlock"
        }
    }
}

// MARK: - Code block payload

struct MDCodeBlock {
    let code: String
    let language: String?
    /// Pre-tokenized lines, produced synchronously during flattening.
    let lines: [[Token]]
}

// MARK: - Lists

struct MDListItem: Identifiable {
    let id: UUID
    /// nil for plain bullets; otherwise a task-list checkbox state.
    let checkbox: MDCheckbox?
    let children: [MDBlock]
}

enum MDCheckbox {
    case checked
    case unchecked

    var isChecked: Bool { self == .checked }
}

// MARK: - Table

struct MDTable {
    let alignments: [Markdown.Table.ColumnAlignment?]
    let head: [AttributedString]
    let rows: [[AttributedString]]
}

// MARK: - Inline content

// Flattened inline content is a single complete `AttributedString`:
// emphasis/links are baked as attributes, inline LaTeX and code
// references are baked as embedded image attachments, and the
// per-glyph `MarkdownBlockMappingsAttribute` copy payload covers the
// whole range. The renderer hands it to `SwiftUI.Text` unchanged.

struct MDImage {
    let source: String?
    let altText: String
}

// MARK: - Inline style (flatten-time only)

/// Semantic inline emphasis collected while walking the AST. Baked
/// into `AttributedString` runs as `inlinePresentationIntent` so the
/// model stays theme-independent.
struct InlineTextStyle: OptionSet {
    let rawValue: Int

    static let bold = InlineTextStyle(rawValue: 1 << 0)
    static let italic = InlineTextStyle(rawValue: 1 << 1)
    static let strikethrough = InlineTextStyle(rawValue: 1 << 2)
    static let code = InlineTextStyle(rawValue: 1 << 3)

    var presentationIntent: InlinePresentationIntent {
        var intent = InlinePresentationIntent()
        if contains(.bold) { intent.insert(.stronglyEmphasized) }
        if contains(.italic) { intent.insert(.emphasized) }
        if contains(.strikethrough) { intent.insert(.strikethrough) }
        if contains(.code) { intent.insert(.code) }
        return intent
    }
}

// MARK: - Signatures

extension AttributedString {
    /// Content signature for block-identity reuse: the signature baked
    /// while the mappings were built (O(1)), else the joined mapping
    /// characters (they carry embedded payloads like `$..$` sources and
    /// reference names verbatim), otherwise the characters.
    var mdSignature: String {
        for run in runs {
            if let signature = run.attributes[MarkdownBakedSignatureKey.self] {
                return signature
            }
        }
        if let mappings = selectionMappings {
            return "m:" + mappings.map(\.char).joined()
        }
        return String(characters)
    }
}

extension MDBlock {
    static func signature(of content: MDBlockContent) -> String {
        switch content {
        case .text(let attributed):
            return "t:" + attributed.mdSignature
        case .heading(let level, let attributed):
            return "h\(level):" + attributed.mdSignature
        case .image(let image):
            return "i:\(image.source ?? "")|\(image.altText)"
        case .codeBlock(let code):
            return "c:\(code.language ?? ""):\(code.code)"
        case .latexBlock(let latex):
            return "lb:\(latex)"
        case .mermaid(let code):
            return "m:\(code)"
        case .blockQuote(let children):
            return "q:[" + children.map(\.signature).joined(separator: ",") + "]"
        case .orderedList(let startIndex, let items):
            return "ol\(startIndex):[" + items.map(\.signature).joined(separator: ",") + "]"
        case .unorderedList(let items):
            return "ul:[" + items.map(\.signature).joined(separator: ",") + "]"
        case .table(let table):
            var sig = "tb:"
            for cell in table.head { sig += cell.mdSignature + "|" }
            for row in table.rows {
                for cell in row { sig += cell.mdSignature + "|" }
                sig += "/"
            }
            return sig
        case .thematicBreak:
            return "hr"
        case .htmlBlock(let rawHTML):
            return "html:" + rawHTML
        }
    }
}

extension MDListItem {
    var signature: String {
        let checkboxSig = checkbox == nil ? "-" : (checkbox == .checked ? "x" : "o")
        return "i\(checkboxSig):[" + children.map(\.signature).joined(separator: ",") + "]"
    }
}
