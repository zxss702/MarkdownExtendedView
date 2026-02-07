// Checkbox+Helpers.swift
//  MarkdownExtendedView
//
//  Created by 知阳 on 2026-02-07.
// Licensed under MIT License

import Markdown

/// Extension to add convenience properties to the Checkbox type from swift-markdown.
public extension Checkbox {

    /// Returns `true` for both checked and unchecked checkboxes.
    ///
    /// This is useful when you need to determine if a list item is a task list item
    /// vs a regular list item (which would have `checkbox == nil`).
    var isTask: Bool {
        switch self {
        case .checked, .unchecked:
            return true
        }
    }

    /// Returns `true` if the checkbox is in the checked state.
    var isChecked: Bool {
        switch self {
        case .checked:
            return true
        case .unchecked:
            return false
        }
    }
}
