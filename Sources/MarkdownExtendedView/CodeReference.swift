//
//  MCodeReference.swift
//  LogorythiaShare
//
//  Created by OpenAI Codex on 2026-04-05.
//

import Foundation
import Markdown

public let canonicalMCodeReferenceFormat = "`/.../name:<start>-<end>`"

public enum MCodeReferenceSelectionError: Error, Sendable {
    case lineOutOfRange(totalLineCount: Int)
    case invalidLineRange(totalLineCount: Int)
}

public enum MCodeReference: Hashable, Sendable {
    case directory(url: URL)
    case entire(url: URL)
    case singleLine(url: URL, line: Int)
    case multipleLines(url: URL, start: Int, end: Int)
    case selections(url: URL, ranges: [ClosedRange<Int>])

    public init?(_ reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let rangedReference = rangedMCodeReference(from: trimmed) {
            self = rangedReference
            return
        }

        guard let fileURL = URL(content: trimmed), fileURL.isFileURL else {
            return nil
        }

        guard !fileURL.lastPathComponent.contains(":") else {
            return nil
        }

        self = MCodeReferenceForFilesystemObject(at: fileURL)
    }

    public var referenceString: String {
        switch self {
        case .directory(let url):
            return normalizedFileURL(from: url, isDirectory: true).filePathString()
        case .entire(let url):
            return normalizedFileURL(from: url, isDirectory: false).filePathString()
        case .singleLine(let url, let line):
            let actualLine = max(line, 1)
            return normalizedFileURL(from: url, isDirectory: false).filePathString() + ":<\(actualLine)>"
        case .multipleLines(let url, let start, let end):
            let actualStart = max(min(start, end), 1)
            let actualEnd = max(max(start, end), 1)
            let base = normalizedFileURL(from: url, isDirectory: false).filePathString()

            if actualStart == actualEnd {
                return base + ":<\(actualStart)>"
            }

            return base + ":<\(actualStart)>-<\(actualEnd)>"
        case .selections(let url, let ranges):
            let base = normalizedFileURL(from: url, isDirectory: false).filePathString()
            let selectionText = normalizedRanges(ranges)
                .map { range in
                    if range.lowerBound == range.upperBound {
                        return "\(range.lowerBound)"
                    }
                    return "\(range.lowerBound)-\(range.upperBound)"
                }
                .joined(separator: "、")
            return base + ":\(selectionText)"
        }
    }

    public var url: URL {
        switch self {
        case .directory(let url), .entire(let url), .singleLine(let url, _), .multipleLines(let url, _, _), .selections(let url, _):
            return url
        }
    }

    public var fileName: String {
        let trimmedPath = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            return url.lastPathComponent.isEmpty ? url.path(percentEncoded: false) : url.lastPathComponent
        }
        return url.lastPathComponent.isEmpty ? trimmedPath : url.lastPathComponent
    }

    public var lineDescription: String? {
        switch self {
        case .directory, .entire:
            return nil
        case .singleLine(_, let line):
            return "Line \(max(line, 1))"
        case .multipleLines(_, let start, let end):
            let actualStart = max(min(start, end), 1)
            let actualEnd = max(max(start, end), 1)
            if actualStart == actualEnd {
                return "Line \(actualStart)"
            }
            return "Lines \(actualStart)-\(actualEnd)"
        case .selections(_, let ranges):
            let text = normalizedRanges(ranges)
                .map { range in
                    if range.lowerBound == range.upperBound {
                        return "\(range.lowerBound)"
                    }
                    return "\(range.lowerBound)-\(range.upperBound)"
                }
                .joined(separator: ", ")
            return "Lines \(text)"
        }
    }

    public var lineRanges: [ClosedRange<Int>] {
        switch self {
        case .directory, .entire:
            return []
        case .singleLine(_, let line):
            let actualLine = max(line, 1)
            return [actualLine...actualLine]
        case .multipleLines(_, let start, let end):
            let actualStart = max(min(start, end), 1)
            let actualEnd = max(max(start, end), 1)
            return [actualStart...actualEnd]
        case .selections(_, let ranges):
            return normalizedRanges(ranges)
        }
    }
}

private func rangedMCodeReference(from rawReference: String) -> MCodeReference? {
    guard let split = splitFileReferenceAndSelection(rawReference) else {
        return nil
    }

    let normalizedURL = normalizedFileURL(from: split.url, isDirectory: false)
    guard let ranges = parseLineRanges(from: split.selection), !ranges.isEmpty else {
        return nil
    }

    if ranges.count == 1 {
        let range = ranges[0]
        if range.lowerBound == range.upperBound {
            return .singleLine(url: normalizedURL, line: range.lowerBound)
        }
        return .multipleLines(url: normalizedURL, start: range.lowerBound, end: range.upperBound)
    }

    return .selections(url: normalizedURL, ranges: ranges)
}

private func MCodeReferenceForFilesystemObject(at fileURL: URL) -> MCodeReference {
    let filePath = fileURL.path
    var isDirectory = ObjCBool(false)

    if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory), isDirectory.boolValue {
        return .directory(url: normalizedFileURL(from: fileURL, isDirectory: true))
    }

    return .entire(url: normalizedFileURL(from: fileURL, isDirectory: false))
}

func readReferencedTextFile(at fileURL: URL) throws -> (Data, String) {
    let data = try Data(contentsOf: fileURL)
    let encodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16BigEndian,
        .utf16LittleEndian,
        .utf32,
        .ascii,
        .isoLatin1,
        .shiftJIS,
        .japaneseEUC,
    ]

    for encoding in encodings {
        if let content = String(data: data, encoding: encoding) {
            return (data, content)
        }
    }

    throw CocoaError(.fileReadInapplicableStringEncoding)
}

func renderedSnippet(for reference: MCodeReference, from fileContent: String) throws -> String {
    let lines = fileContent.components(separatedBy: .newlines)
    var result = ""
    for selectedRange in try selectedLineRanges(for: reference, in: lines) {
        for index in selectedRange {
            result += "<\(index + 1)>\(lines[index])\n"
        }
    }
    return result
}

private func selectedLineRanges(for reference: MCodeReference, in lines: [String]) throws -> [Range<Int>] {
    switch reference {
    case .directory:
        throw MCodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
    case .entire:
        return [0..<lines.count]
    case .singleLine, .multipleLines, .selections:
        let ranges = reference.lineRanges
        guard !ranges.isEmpty else {
            throw MCodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
        }

        return try ranges.map { range in
            let actualStartLine = max(range.lowerBound, 1)
            let actualEndLine = max(range.upperBound, actualStartLine)
            let actualStartIndex = actualStartLine - 1

            guard actualStartIndex < lines.count else {
                throw MCodeReferenceSelectionError.lineOutOfRange(totalLineCount: lines.count)
            }

            let boundedEndLine = min(actualEndLine, lines.count)
            guard boundedEndLine >= actualStartLine else {
                throw MCodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
            }

            return actualStartIndex..<boundedEndLine
        }
    }
}

public extension URL {
    func MCodeReferenceString(startLine: Int, endLine: Int) -> String {
        MCodeReference.multipleLines(
            url: self,
            start: startLine,
            end: endLine
        ).referenceString
    }
}

private func normalizedFileURL(from url: URL, isDirectory: Bool) -> URL {
    url.standardizedFileURL
}

nonisolated extension URL {
    func filePathString() -> String {
        let path = self.path(percentEncoded: false)
        return path.removingPercentEncoding ?? path
    }

    init?(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
#if os(Windows)
        let isWindowsAbsolutePath = Self.looksLikeWindowsAbsolutePath(trimmed)
#else
        let isWindowsAbsolutePath = false
#endif

        if let schemeRange = trimmed.range(of: "://") {
            let scheme = String(trimmed[..<schemeRange.lowerBound]).lowercased()
            let rest = String(trimmed[schemeRange.upperBound...])

            switch scheme {
            case "file":
                self = Self.localFileURL(from: rest)
            case "http", "https", "ftp", "mailto", "tel":
                if let url = URL(string: trimmed) {
                    self = url
                } else {
                    guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                        return nil
                    }
                    self.init(string: encoded)
                }
            default:
                self.init(string: trimmed)
            }
        } else if isWindowsAbsolutePath {
            self = Self.localFileURL(from: trimmed)
        } else if trimmed.hasPrefix("/") {
            self = Self.localFileURL(from: trimmed)
        } else if trimmed.hasPrefix("~") {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            self = Self.localFileURL(from: expanded)
        } else {
            if let url = URL(string: trimmed) {
                self = url
            } else {
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    return nil
                }
                self.init(string: encoded)
            }
        }
    }

    private static func localFileURL(from rawPath: String) -> URL {
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
#if os(Windows)
        let normalizedPath = normalizeWindowsAbsolutePath(decodedPath)
#else
        let normalizedPath = decodedPath
#endif
        return URL(fileURLWithPath: normalizedPath)
    }

#if os(Windows)
    private static func looksLikeWindowsAbsolutePath(_ path: String) -> Bool {
        guard path.count >= 3 else { return false }
        let characters = Array(path)
        return characters[0].isLetter && characters[1] == ":" && (characters[2] == "\\" || characters[2] == "/")
    }

    private static func normalizeWindowsAbsolutePath(_ path: String) -> String {
        guard !path.isEmpty else { return path }

        if (path.hasPrefix("/") || path.hasPrefix("\\")), path.count >= 3 {
            let trimmed = String(path.dropFirst())
            let characters = Array(trimmed)
            if characters.count >= 2, characters[0].isLetter, characters[1] == ":" {
                return trimmed
            }
        }

        return path
    }
#endif
}

func parseMCodeReferences(from rawText: String) -> [MCodeReference]? {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let looksLikeFileReference = trimmed.hasPrefix("file://") || trimmed.hasPrefix("/")
    guard looksLikeFileReference else {
        return nil
    }

    let segments = splitFileReferenceSegments(trimmed)
    if segments.count > 1 {
        var references: [MCodeReference] = []
        for segment in segments {
            guard let reference = MCodeReference(segment) else {
                return nil
            }
            references.append(reference)
        }
        return references.isEmpty ? nil : references
    }

    if let singleReference = MCodeReference(trimmed) {
        return [singleReference]
    }

    return nil
}

/// Splits a block into absolute file-reference segments.
/// New segments start only at `file://` markers, or at `/` / `file://` after a delimiter
/// (so selection commas inside one path are preserved).
private func splitFileReferenceSegments(_ text: String) -> [String] {
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，、;；"))

    if text.hasPrefix("file://") {
        let fileURLMarker = "file://"
        var markerRanges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: fileURLMarker, range: searchStart..<text.endIndex) {
            markerRanges.append(range)
            searchStart = range.upperBound
        }

        guard markerRanges.count > 1 else { return [text] }

        var segments: [String] = []
        for (index, markerRange) in markerRanges.enumerated() {
            let nextStart = index + 1 < markerRanges.count ? markerRanges[index + 1].lowerBound : text.endIndex
            let segment = String(text[markerRange.lowerBound..<nextStart]).trimmingCharacters(in: separators)
            if !segment.isEmpty {
                segments.append(segment)
            }
        }
        return segments
    }

    var startIndices: [String.Index] = [text.startIndex]
    var index = text.startIndex
    while index < text.endIndex {
        guard let scalar = text[index].unicodeScalars.first, separators.contains(scalar) else {
            index = text.index(after: index)
            continue
        }

        var afterSeparators = index
        while afterSeparators < text.endIndex,
              let s = text[afterSeparators].unicodeScalars.first,
              separators.contains(s) {
            afterSeparators = text.index(after: afterSeparators)
        }

        if afterSeparators < text.endIndex {
            let remainder = text[afterSeparators...]
            if remainder.hasPrefix("/") || remainder.hasPrefix("file://") {
                startIndices.append(afterSeparators)
                index = afterSeparators
                continue
            }
        }
        index = afterSeparators < text.endIndex ? afterSeparators : text.endIndex
    }

    guard startIndices.count > 1 else { return [text] }

    var segments: [String] = []
    for (i, start) in startIndices.enumerated() {
        let end = i + 1 < startIndices.count ? startIndices[i + 1] : text.endIndex
        let segment = String(text[start..<end]).trimmingCharacters(in: separators)
        if !segment.isEmpty {
            segments.append(segment)
        }
    }
    return segments
}

private func splitFileReferenceAndSelection(_ rawReference: String) -> (url: URL, selection: String)? {
    guard let separatorIndex = rawReference.lastIndex(of: ":") else {
        return nil
    }

    let urlText = String(rawReference[..<separatorIndex])
    let selectionText = String(rawReference[rawReference.index(after: separatorIndex)...])

    guard let url = URL(content: urlText), url.isFileURL else {
        return nil
    }

    return (url, selectionText)
}

private func parseLineRanges(from rawSelection: String) -> [ClosedRange<Int>]? {
    let trimmed = rawSelection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let normalizedSelection = trimmed
        .replacingOccurrences(of: "，", with: ",")
        .replacingOccurrences(of: "、", with: ",")
        .replacingOccurrences(of: "；", with: ",")
        .replacingOccurrences(of: ";", with: ",")

    let parts = normalizedSelection
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !parts.isEmpty else {
        return nil
    }

    var ranges: [ClosedRange<Int>] = []
    for part in parts {
        guard !part.isEmpty, let range = parseSingleLineRange(from: part) else {
            return nil
        }
        ranges.append(range)
    }

    return normalizedRanges(ranges)
}

private func parseSingleLineRange(from rawPart: String) -> ClosedRange<Int>? {
    let normalized = unwrapRangeToken(rawPart)
    guard !normalized.isEmpty else {
        return nil
    }

    if normalized.contains("-") {
        let bounds = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2 else {
            return nil
        }

        let startText = unwrapRangeToken(String(bounds[0]))
        let endText = unwrapRangeToken(String(bounds[1]))
        guard
            let start = Int(startText),
            let end = Int(endText)
        else {
            return nil
        }

        let actualStart = max(min(start, end), 1)
        let actualEnd = max(max(start, end), 1)
        return actualStart...actualEnd
    }

    guard let line = Int(normalized) else {
        return nil
    }

    let actualLine = max(line, 1)
    return actualLine...actualLine
}

private func unwrapRangeToken(_ token: String) -> String {
    token
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "<", with: "")
        .replacingOccurrences(of: ">", with: "")
}

private func normalizedRanges(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
    guard !ranges.isEmpty else {
        return []
    }

    let sorted = ranges.sorted {
        if $0.lowerBound == $1.lowerBound {
            return $0.upperBound < $1.upperBound
        }
        return $0.lowerBound < $1.lowerBound
    }

    var merged: [ClosedRange<Int>] = []
    for range in sorted {
        if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
            merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }

    return merged
}
