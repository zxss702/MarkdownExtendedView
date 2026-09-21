// GlobalSelectionCache.swift
// MarkdownExtendedView
//
//  Marker object placed in the environment by `.selectable()`. Its mere
//  presence opts descendant views into selection (anchors registered via
//  `makeCanSelectable()`); it no longer stores per-run layout data — the
//  selection document is built from `Text.LayoutKey` + anchors.

import SwiftUI
import Observation

/// Optional glyph mapping attribute — run-length encoded, so one entry
/// can cover many laid-out glyphs (an embedded attachment counts as one
/// glyph). Applied to a `Text` via `.customAttribute`, it survives into
/// `Text.Layout` runs where the selection builder uses it for direct
/// char extraction instead of Core Text reflection — provided the
/// laid-out slice count matches the total glyph count exactly.
public struct MarkdownBlockMappingsAttribute: TextAttribute, Equatable, Hashable, Sendable {
    public typealias Value = MarkdownBlockMappingsAttribute
    public static let name = "MarkdownBlockMappingsAttribute"

    public let mappings: [GlobalSelectionCache.CharacterMapping]
    public init(mappings: [GlobalSelectionCache.CharacterMapping]) {
        self.mappings = mappings
    }
}

/// Storage key carrying the same payload INSIDE a flattened
/// `AttributedString` so the string stays self-contained. Renderers
/// re-publish it onto the `Text` via `.customAttribute` — `Text.Layout`
/// run subscripts only see `TextAttribute`s, not string attributes.
enum MarkdownBakedMappingsKey: AttributedStringKey {
    typealias Value = [GlobalSelectionCache.CharacterMapping]
    static let name = "MarkdownBakedMappingsKey"
}

/// The block-content signature accumulated while baking mappings —
/// stored on the `AttributedString` so `mdSignature` is an O(1) read
/// instead of joining every mapping's characters again.
enum MarkdownBakedSignatureKey: AttributedStringKey {
    typealias Value = String
    static let name = "MarkdownBakedSignatureKey"
}

/// An image payload baked into an `AttributedString` at a `\u{FFFC}`
/// marker position. `SwiftUI.Text` cannot draw foreign
/// `NSTextAttachment`s — only its own `Text(Image)` interpolation — so
/// `InlineContentView` splits the string at these markers and
/// concatenates `Text`s, which still lay out as one continuous text.
///
/// The image is resolved LAZILY at first render/copy: expensive work
/// (LaTeX typesetting, file-icon lookup) never runs inside
/// `MarkdownView.init`. Resolution is memoized on the instance.
public final class MDBakedInlineImage: @unchecked Sendable, Hashable {
    public enum Sizing: Hashable, Sendable {
        /// Render at the image's own size with `descent` — typeset
        /// LaTeX whose metrics were fixed during typesetting.
        case fixed
        /// Scale at render time to the effective font's glyph box and
        /// center it on the cap-height box — so inline icons match the
        /// surrounding text height and sit vertically centered.
        case fontScaled
    }

    enum Payload {
        /// An already-rendered image (anchor attachments, tests).
        case rendered(MTImage, descent: CGFloat)
        /// Inline `$..$` math — typeset on first resolve.
        case inlineMath(latex: String, fontSize: CGFloat)
        /// A code-reference icon — looked up on first resolve.
        case codeRefIcon(MCodeReference, size: CGFloat)
    }

    let payload: Payload
    public let sizing: Sizing
    /// Memoized resolution. `nil` = not yet resolved; `.some(nil)` =
    /// resolved and failed (LaTeX parse error — never recurs).
    private var resolvedResult: (image: MTImage, descent: CGFloat)? = nil
    private var didResolve = false

    public init(image: MTImage, descent: CGFloat, sizing: Sizing = .fixed) {
        self.payload = .rendered(image, descent: descent)
        self.sizing = sizing
        self.resolvedResult = (image, descent)
        self.didResolve = true
    }

    init(payload: Payload, sizing: Sizing) {
        self.payload = payload
        self.sizing = sizing
    }

    /// The resolved image and baseline descent — typesets math or looks
    /// up the icon on first call, then memoizes. `nil` only when the
    /// LaTeX source fails to typeset (icons always resolve).
    func resolve() -> (image: MTImage, descent: CGFloat)? {
        if didResolve { return resolvedResult }
        didResolve = true
        switch payload {
        case .rendered(let image, let descent):
            resolvedResult = (image, descent)
        case .inlineMath(let latex, let fontSize):
            #if canImport(AppKit)
            let textColor: MTColor = .labelColor
            #elseif canImport(UIKit)
            let textColor: MTColor = .label
            #endif
            if let cached = MathDisplayCache.shared.getCachedImage(
                latex: latex,
                fontSize: fontSize,
                isBlock: false,
                textColor: textColor
            ) {
                resolvedResult = (cached.platformImage, cached.descent)
            }
        case .codeRefIcon(let reference, let size):
            resolvedResult = (MCodeReferenceIcon.image(for: reference, size: size), 0)
        }
        return resolvedResult
    }

    /// Plain-text stand-in when the image cannot be produced — the
    /// literal `$..$` source for inline math, nil for icons.
    var fallbackText: String? {
        if case .inlineMath(let latex, _) = payload { return "$\(latex)$" }
        return nil
    }

    /// The image and baseline descent for `font` — `.fixed` passes
    /// through, `.fontScaled` resizes the glyph to span the font's
    /// descender line up to its cap line.
    func rendered(for font: MarkdownNativeFont) -> (image: MTImage, descent: CGFloat)? {
        guard let resolved = resolve() else { return nil }
        switch sizing {
        case .fixed:
            return resolved
        case .fontScaled:
            // Midline-to-midline: center the glyph on the font's
            // typographic midline ((ascender + descender) / 2).
            let height = font.capHeight - font.descender
            let midline = (font.ascender + font.descender) / 2
            return (resolved.image.mdScaled(toHeight: height), height / 2 - midline)
        }
    }

    public static func == (lhs: MDBakedInlineImage, rhs: MDBakedInlineImage) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

enum MarkdownInlineImageKey: AttributedStringKey {
    typealias Value = MDBakedInlineImage
    static let name = "MarkdownInlineImage"
}

extension AttributedString {
    /// The baked run-encoded selection payload, if present.
    var selectionMappings: [GlobalSelectionCache.CharacterMapping]? {
        for run in runs {
            if let mappings = run.attributes[MarkdownBakedMappingsKey.self] {
                return mappings
            }
        }
        return nil
    }
}

/// Rich ("with images") copy content attached to one selection slice.
enum SelectionRichContent {
    /// A rendered image placed at this slice — inline formula image or
    /// an atomic block (mermaid diagram, block formula).
    case image(MTImage)
    /// `[icon] File.swift:46-58` — icon attachment plus the tinted,
    /// linked label, preserving the inline reference's look.
    case codeRef(icon: MTImage, label: String, link: String?)
}

@Observable
public class GlobalSelectionCache {

    /// Run-length encoded per-glyph mapping. One entry can cover many
    /// laid-out glyphs (`glyphCount`), so building the map is O(runs),
    /// not O(characters) — the per-glyph payloads are expanded lazily by
    /// `MDGlyphCursor` while the selection document consumes them.
    public struct CharacterMapping: Equatable, Hashable, Sendable {
        /// Copy text for this entry: the full run when `slicesText` is
        /// set (one Character per glyph), otherwise verbatim per glyph
        /// ("" for grouped members, the raw payload on a group's first
        /// glyph, `\n` for a line break).
        public let char: Substring
        /// Laid-out glyphs covered by this entry — `0` for line breaks.
        public let glyphCount: Int
        /// `true` when `char` is source text sliced one Character per
        /// glyph at expansion; `false` repeats `char` verbatim per glyph.
        public let slicesText: Bool
        /// Non-nil members of the same group merge into ONE selection
        /// slice — used to make a code reference (`icon + filename`)
        /// select atomically like an inline formula.
        public let group: String?
        /// `true` for `\n`: it occupies a mapping (copied as a line
        /// break) but lays out no glyph, so it owns no `Text.Layout`
        /// slice. Consumed at line boundaries as a zero-width slice.
        public let isLineBreak: Bool
        /// Resolved absolute link destination on this glyph — drives
        /// pointing-hand hover and the "拷贝链接" menu.
        public let link: String?
        /// Image payload baked at a `\u{FFFC}` glyph (inline formula,
        /// code-reference icon) — attached verbatim by rich copy.
        public let richImage: MDBakedInlineImage?
        /// Display text paired with `richImage` at a group's first
        /// member (the code-reference label `File.swift:46-58`).
        public let richText: String?
        public init(
            char: Substring,
            glyphCount: Int = 1,
            slicesText: Bool = false,
            group: String? = nil,
            isLineBreak: Bool = false,
            link: String? = nil,
            richImage: MDBakedInlineImage? = nil,
            richText: String? = nil
        ) {
            self.char = char
            self.glyphCount = glyphCount
            self.slicesText = slicesText
            self.group = group
            self.isLineBreak = isLineBreak
            self.link = link
            self.richImage = richImage
            self.richText = richText
        }
    }

    /// Sequential expansion of run-encoded mappings into per-glyph
    /// entries. Used by the selection document builder, which consumes
    /// glyphs strictly in order.
    public struct MDGlyphCursor: Sendable {
        private let mappings: [CharacterMapping]
        private var runIndex = 0
        private var producedInRun = 0
        private var textIndex: String.Index

        public init(_ mappings: [CharacterMapping]) {
            self.mappings = mappings
            self.textIndex = mappings.first?.char.startIndex ?? "".startIndex
        }

        /// `true` when the next un-consumed entry is a line break.
        public var nextIsLineBreak: Bool {
            runIndex < mappings.count && mappings[runIndex].isLineBreak
        }

        /// Total laid-out glyphs covered by all runs.
        public var glyphCount: Int {
            mappings.reduce(0) { $0 + ($1.isLineBreak ? 0 : $1.glyphCount) }
        }

        /// Consumes the next line-break entry.
        public mutating func nextLineBreak() -> CharacterMapping? {
            guard nextIsLineBreak else { return nil }
            defer { runIndex += 1 }
            return mappings[runIndex]
        }

        /// Consumes one laid-out glyph, expanding the current run.
        public mutating func nextGlyph() -> CharacterMapping? {
            while runIndex < mappings.count {
                let run = mappings[runIndex]
                if run.isLineBreak || run.glyphCount == 0 {
                    runIndex += 1
                    producedInRun = 0
                    continue
                }
                let char: Substring
                if run.slicesText {
                    if producedInRun == 0 {
                        textIndex = run.char.startIndex
                    }
                    let next = run.char.index(after: textIndex)
                    char = run.char[textIndex..<next]
                    textIndex = next
                } else {
                    char = run.char
                }
                producedInRun += 1
                if producedInRun == run.glyphCount {
                    runIndex += 1
                    producedInRun = 0
                }
                return CharacterMapping(
                    char: char,
                    group: run.group,
                    link: run.link,
                    richImage: run.richImage,
                    richText: run.richText
                )
            }
            return nil
        }
    }

    public init() {}
}
