//
//  CodeReference.swift
//  LogorythiaShare
//
//  Created by OpenAI Codex on 2026-04-05.
//

import Foundation

let canonicalCodeReferenceFormat = "`file:///.../name:<start>-<end>`"

enum CodeReferenceSelectionError: Error, Sendable {
    case lineOutOfRange(totalLineCount: Int)
    case invalidLineRange(totalLineCount: Int)
}

enum CodeReference: Hashable, Sendable {
    case directory(url: URL)
    case entire(url: URL)
    case singleLine(url: URL, line: Int)
    case multipleLines(url: URL, start: Int, end: Int)
    case selections(url: URL, ranges: [ClosedRange<Int>])

    init?(_ reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let rangedReference = rangedCodeReference(from: trimmed) {
            self = rangedReference
            return
        }

        guard let fileURL = URL(content: trimmed), fileURL.isFileURL else {
            return nil
        }

        guard !fileURL.lastPathComponent.contains(":") else {
            return nil
        }

        self = codeReferenceForFilesystemObject(at: fileURL)
    }

    var referenceString: String {
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

    var url: URL {
        switch self {
        case .directory(let url), .entire(let url), .singleLine(let url, _), .multipleLines(let url, _, _), .selections(let url, _):
            return url
        }
    }

    var fileName: String {
        let trimmedPath = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            return url.lastPathComponent.isEmpty ? url.path(percentEncoded: false) : url.lastPathComponent
        }
        return url.lastPathComponent.isEmpty ? trimmedPath : url.lastPathComponent
    }

    var lineDescription: String? {
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

    var lineRanges: [ClosedRange<Int>] {
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

private func rangedCodeReference(from rawReference: String) -> CodeReference? {
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

private func codeReferenceForFilesystemObject(at fileURL: URL) -> CodeReference {
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

func renderedSnippet(for reference: CodeReference, from fileContent: String) throws -> String {
    let lines = fileContent.components(separatedBy: .newlines)
    var result = ""
    for selectedRange in try selectedLineRanges(for: reference, in: lines) {
        for index in selectedRange {
            result += "<\(index + 1)>\(lines[index])\n"
        }
    }
    return result
}

private func selectedLineRanges(for reference: CodeReference, in lines: [String]) throws -> [Range<Int>] {
    switch reference {
    case .directory:
        throw CodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
    case .entire:
        return [0..<lines.count]
    case .singleLine, .multipleLines, .selections:
        let ranges = reference.lineRanges
        guard !ranges.isEmpty else {
            throw CodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
        }

        return try ranges.map { range in
            let actualStartLine = max(range.lowerBound, 1)
            let actualEndLine = max(range.upperBound, actualStartLine)
            let actualStartIndex = actualStartLine - 1

            guard actualStartIndex < lines.count else {
                throw CodeReferenceSelectionError.lineOutOfRange(totalLineCount: lines.count)
            }

            let boundedEndLine = min(actualEndLine, lines.count)
            guard boundedEndLine >= actualStartLine else {
                throw CodeReferenceSelectionError.invalidLineRange(totalLineCount: lines.count)
            }

            return actualStartIndex..<boundedEndLine
        }
    }
}

extension URL {
    func codeReferenceString(startLine: Int, endLine: Int) -> String {
        CodeReference.multipleLines(
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
        return "file://" + (path.removingPercentEncoding ?? path)
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

func parseCodeReferences(from rawText: String) -> [CodeReference]? {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let fileURLMarker = "file://"
    var markerRanges: [Range<String.Index>] = []
    var searchStart = trimmed.startIndex
    while let range = trimmed.range(of: fileURLMarker, range: searchStart..<trimmed.endIndex) {
        markerRanges.append(range)
        searchStart = range.upperBound
    }

    let separatorCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，、;；"))
    if markerRanges.count > 1 {
        var references: [CodeReference] = []

        for (index, markerRange) in markerRanges.enumerated() {
            let nextStart = index + 1 < markerRanges.count ? markerRanges[index + 1].lowerBound : trimmed.endIndex
            let rawSegment = String(trimmed[markerRange.lowerBound..<nextStart])
            let segment = rawSegment.trimmingCharacters(in: separatorCharacters)

            guard let reference = CodeReference(segment) else {
                return nil
            }

            references.append(reference)
        }

        return references.isEmpty ? nil : references
    }

    if let singleReference = CodeReference(trimmed) {
        return [singleReference]
    }

    return nil
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
