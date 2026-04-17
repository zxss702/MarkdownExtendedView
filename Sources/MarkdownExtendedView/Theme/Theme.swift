// Theme.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import SwiftUI

#if canImport(AppKit)
import AppKit
public typealias MarkdownNativeFont = NSFont
#elseif canImport(UIKit)
import UIKit
public typealias MarkdownNativeFont = UIFont
#endif

// MARK: - Syntax Colors

/// Colors for syntax highlighting in code blocks.
public struct SyntaxColors: Sendable {

    /// Color for keywords (e.g., `let`, `func`, `class`, `if`, `return`).
    public var keyword: Color

    /// Color for string literals (e.g., `"Hello"`).
    public var string: Color

    /// Color for comments (e.g., `// comment`).
    public var comment: Color

    /// Color for numbers (e.g., `42`, `3.14`).
    public var number: Color

    /// Color for type names (e.g., `String`, `Int`, `MyClass`).
    public var type: Color

    /// Color for function/method names.
    public var function: Color

    /// Color for plain text (default code color).
    public var plain: Color

    /// Creates a syntax color palette.
    public init(
        keyword: Color = Color(red: 0.61, green: 0.13, blue: 0.58),
        string: Color = Color(red: 0.77, green: 0.1, blue: 0.09),
        comment: Color = Color(red: 0.42, green: 0.48, blue: 0.51),
        number: Color = Color(red: 0.11, green: 0.44, blue: 0.72),
        type: Color = Color(red: 0.11, green: 0.44, blue: 0.72),
        function: Color = Color(red: 0.16, green: 0.5, blue: 0.73),
        plain: Color = .primary
    ) {
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.function = function
        self.plain = plain
    }

    /// Default syntax colors matching Xcode's default theme.
    public static let `default` = SyntaxColors()

    /// GitHub-style syntax colors.
    public static let gitHub = SyntaxColors(
        keyword: Color(red: 0.84, green: 0.16, blue: 0.5),
        string: Color(red: 0.0, green: 0.37, blue: 0.73),
        comment: Color(red: 0.42, green: 0.48, blue: 0.51),
        number: Color(red: 0.0, green: 0.37, blue: 0.73),
        type: Color(red: 0.42, green: 0.22, blue: 0.6),
        function: Color(red: 0.42, green: 0.22, blue: 0.6),
        plain: Color(red: 0.14, green: 0.16, blue: 0.18)
    )
}

// MARK: - Native Font Helpers

public extension MarkdownNativeFont {
    /// A SwiftUI font bridged from the native AppKit/UIKit font.
    var swiftUIFont: Font {
        Font(self)
    }

    /// A stable signature used for snapshot height caching.
    var markdownSignature: String {
        "\(fontName):\(pointSize)"
    }

    /// The typographic line height used by the estimator.
    var markdownLineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}

public enum MarkdownThemeFontDefaults {
    public static var body: MarkdownNativeFont {
        system(size: 17)
    }

    public static var heading1: MarkdownNativeFont {
        system(size: 34, weight: .bold)
    }

    public static var heading2: MarkdownNativeFont {
        system(size: 28, weight: .bold)
    }

    public static var heading3: MarkdownNativeFont {
        system(size: 22, weight: .bold)
    }

    public static var heading4: MarkdownNativeFont {
        system(size: 20, weight: .semibold)
    }

    public static var heading5: MarkdownNativeFont {
        system(size: 17, weight: .semibold)
    }

    public static var heading6: MarkdownNativeFont {
        system(size: 15, weight: .semibold)
    }

    public static var code: MarkdownNativeFont {
        monospaced(size: 17)
    }

    public static var codeBlock: MarkdownNativeFont {
        monospaced(size: 14)
    }

    static func system(size: CGFloat, weight: MarkdownSystemFontWeight = .regular) -> MarkdownNativeFont {
#if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
#else
        return UIFont.systemFont(ofSize: size, weight: weight)
#endif
    }

    static func monospaced(size: CGFloat, weight: MarkdownSystemFontWeight = .regular) -> MarkdownNativeFont {
#if canImport(AppKit)
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
#else
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
#endif
    }
}

#if canImport(AppKit)
typealias MarkdownSystemFontWeight = NSFont.Weight
#elseif canImport(UIKit)
typealias MarkdownSystemFontWeight = UIFont.Weight
#endif

// MARK: - Theme

/// A theme for customizing the appearance of rendered Markdown content.
///
/// `MarkdownTheme` provides comprehensive control over typography, colors, and spacing
/// for all Markdown elements. Fonts are stored as native AppKit/UIKit fonts so the same
/// values can be used for both rendering and height estimation.
public struct MarkdownTheme: @unchecked Sendable {

    // MARK: - Text Styles

    /// Font for body text.
    public var bodyFont: MarkdownNativeFont
    /// Font for H1 headings.
    public var heading1Font: MarkdownNativeFont
    /// Font for H2 headings.
    public var heading2Font: MarkdownNativeFont
    /// Font for H3 headings.
    public var heading3Font: MarkdownNativeFont
    /// Font for H4 headings.
    public var heading4Font: MarkdownNativeFont
    /// Font for H5 headings.
    public var heading5Font: MarkdownNativeFont
    /// Font for H6 headings.
    public var heading6Font: MarkdownNativeFont
    /// Font for inline code.
    public var codeFont: MarkdownNativeFont
    /// Font for code blocks.
    public var codeBlockFont: MarkdownNativeFont

    public var latexInlineFontSize: CGFloat
    public var latexBlockFontSize: CGFloat
    public var mermaidFontSize: CGFloat

    // MARK: - Colors

    public var textColor: Color
    public var secondaryTextColor: Color
    public var linkColor: Color
    public var codeBackgroundColor: Color
    public var blockQuoteBorderColor: Color
    public var syntaxColors: SyntaxColors

    // MARK: - Spacing

    public var paragraphSpacing: CGFloat
    public var listItemSpacing: CGFloat
    public var indentation: CGFloat
    public var codeBlockPadding: CGFloat
    public var codeLineSpacing: CGFloat
    public var textAlignment: HorizontalAlignment = .leading

    // MARK: - Initialization

    public init(
        bodyFont: MarkdownNativeFont = MarkdownThemeFontDefaults.body,
        heading1Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading1,
        heading2Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading2,
        heading3Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading3,
        heading4Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading4,
        heading5Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading5,
        heading6Font: MarkdownNativeFont = MarkdownThemeFontDefaults.heading6,
        codeFont: MarkdownNativeFont = MarkdownThemeFontDefaults.code,
        codeBlockFont: MarkdownNativeFont = MarkdownThemeFontDefaults.codeBlock,
        latexInlineFontSize: CGFloat = 13,
        latexBlockFontSize: CGFloat = 20,
        mermaidFontSize: CGFloat = 13,
        textColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        linkColor: Color = .accentColor,
        codeBackgroundColor: Color = Color(white: 0.95),
        blockQuoteBorderColor: Color = Color(white: 0.75),
        syntaxColors: SyntaxColors = .default,
        paragraphSpacing: CGFloat = 12,
        listItemSpacing: CGFloat = 4,
        indentation: CGFloat = 20,
        codeBlockPadding: CGFloat = 12,
        codeLineSpacing: CGFloat = 8,
        textAlignment: HorizontalAlignment = .leading
    ) {
        self.bodyFont = bodyFont
        self.heading1Font = heading1Font
        self.heading2Font = heading2Font
        self.heading3Font = heading3Font
        self.heading4Font = heading4Font
        self.heading5Font = heading5Font
        self.heading6Font = heading6Font
        self.codeFont = codeFont
        self.codeBlockFont = codeBlockFont
        self.latexBlockFontSize = latexBlockFontSize
        self.latexInlineFontSize = latexInlineFontSize
        self.mermaidFontSize = mermaidFontSize
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeBackgroundColor = codeBackgroundColor
        self.blockQuoteBorderColor = blockQuoteBorderColor
        self.syntaxColors = syntaxColors
        self.paragraphSpacing = paragraphSpacing
        self.listItemSpacing = listItemSpacing
        self.indentation = indentation
        self.codeBlockPadding = codeBlockPadding
        self.codeLineSpacing = codeLineSpacing
        self.textAlignment = textAlignment
    }

    /// Returns the native font for the specified heading level.
    public func headingFont(level: Int) -> MarkdownNativeFont {
        switch level {
        case 1: return heading1Font
        case 2: return heading2Font
        case 3: return heading3Font
        case 4: return heading4Font
        case 5: return heading5Font
        case 6: return heading6Font
        default: return heading6Font
        }
    }

    public func headingSwiftUIFont(level: Int) -> Font {
        headingFont(level: level).swiftUIFont
    }

    public var bodySwiftUIFont: Font {
        bodyFont.swiftUIFont
    }

    public var codeSwiftUIFont: Font {
        codeFont.swiftUIFont
    }

    public var codeBlockSwiftUIFont: Font {
        codeBlockFont.swiftUIFont
    }

    var layoutSignature: String {
        [
            bodyFont.markdownSignature,
            heading1Font.markdownSignature,
            heading2Font.markdownSignature,
            heading3Font.markdownSignature,
            heading4Font.markdownSignature,
            heading5Font.markdownSignature,
            heading6Font.markdownSignature,
            codeFont.markdownSignature,
            codeBlockFont.markdownSignature,
            "\(latexInlineFontSize)",
            "\(latexBlockFontSize)",
            "\(paragraphSpacing)",
            "\(listItemSpacing)",
            "\(indentation)",
            "\(codeBlockPadding)",
            "\(codeLineSpacing)",
            "\(textAlignment.markdownSignature)"
        ].joined(separator: "|")
    }

    public func toTextAlignment() -> TextAlignment {
        switch textAlignment {
        case .center: return .center
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .leading
        }
    }
}

// MARK: - Built-in Themes

public extension MarkdownTheme {

    static let `default` = MarkdownTheme()

    static let gitHub = MarkdownTheme(
        bodyFont: MarkdownThemeFontDefaults.system(size: 16),
        heading1Font: MarkdownThemeFontDefaults.system(size: 32, weight: .bold),
        heading2Font: MarkdownThemeFontDefaults.system(size: 24, weight: .bold),
        heading3Font: MarkdownThemeFontDefaults.system(size: 20, weight: .bold),
        heading4Font: MarkdownThemeFontDefaults.system(size: 16, weight: .bold),
        heading5Font: MarkdownThemeFontDefaults.system(size: 14, weight: .bold),
        heading6Font: MarkdownThemeFontDefaults.system(size: 13, weight: .bold),
        codeFont: MarkdownThemeFontDefaults.monospaced(size: 14),
        codeBlockFont: MarkdownThemeFontDefaults.monospaced(size: 13),
        linkColor: Color(red: 0.0, green: 0.4, blue: 0.8),
        codeBackgroundColor: Color(red: 0.96, green: 0.97, blue: 0.98),
        syntaxColors: .gitHub,
        paragraphSpacing: 16,
        listItemSpacing: 4,
        indentation: 24,
        codeBlockPadding: 16
    )

    static let compact = MarkdownTheme(
        bodyFont: MarkdownThemeFontDefaults.system(size: 14),
        heading1Font: MarkdownThemeFontDefaults.system(size: 22, weight: .bold),
        heading2Font: MarkdownThemeFontDefaults.system(size: 20, weight: .bold),
        heading3Font: MarkdownThemeFontDefaults.system(size: 17, weight: .semibold),
        heading4Font: MarkdownThemeFontDefaults.system(size: 15, weight: .semibold),
        heading5Font: MarkdownThemeFontDefaults.system(size: 13, weight: .semibold),
        heading6Font: MarkdownThemeFontDefaults.system(size: 12, weight: .semibold),
        codeFont: MarkdownThemeFontDefaults.monospaced(size: 12),
        codeBlockFont: MarkdownThemeFontDefaults.monospaced(size: 11),
        paragraphSpacing: 8,
        listItemSpacing: 2,
        indentation: 16,
        codeBlockPadding: 8
    )
}

// MARK: - Environment Key

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue = MarkdownTheme.default
}

public extension EnvironmentValues {
    /// The current Markdown theme used by ``MarkdownView`` instances.
    var markdownTheme: MarkdownTheme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
}

private extension HorizontalAlignment {
    var markdownSignature: String {
        switch self {
        case .center: return "center"
        case .leading: return "leading"
        case .trailing: return "trailing"
        default: return "leading"
        }
    }
}
