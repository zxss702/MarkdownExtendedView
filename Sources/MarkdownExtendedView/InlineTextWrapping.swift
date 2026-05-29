import Foundation

enum MarkdownInlineTextWrapping {
    private static let maxCJKUnitLength = 8

    static func units(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var units: [String] = []
        var currentStartIndex = text.startIndex
        var currentCJKStartIndex = text.startIndex
        
        var hasCurrent = false
        var hasCJK = false
        var cjkCount = 0

        func flushCurrent(upTo index: String.Index) {
            if hasCurrent {
                units.append(String(text[currentStartIndex..<index]))
                hasCurrent = false
            }
        }

        func flushCJK(upTo index: String.Index) {
            if hasCJK {
                units.append(String(text[currentCJKStartIndex..<index]))
                hasCJK = false
                cjkCount = 0
            }
        }

        var currentIndex = text.startIndex
        while currentIndex < text.endIndex {
            let character = text[currentIndex]
            let nextIndex = text.index(after: currentIndex)

            if character.isNewline {
                flushCurrent(upTo: currentIndex)
                flushCJK(upTo: currentIndex)
                units.append(String(text[currentIndex..<nextIndex]))
                currentIndex = nextIndex
                continue
            }

            if character.isWhitespace {
                if hasCJK {
                    flushCJK(upTo: currentIndex)
                }
                if !hasCurrent {
                    currentStartIndex = currentIndex
                }
                hasCurrent = true
                flushCurrent(upTo: nextIndex)
                currentIndex = nextIndex
                continue
            }

            if character.isCJKLineBreakUnit {
                flushCurrent(upTo: currentIndex)
                if !hasCJK {
                    currentCJKStartIndex = currentIndex
                    hasCJK = true
                }
                cjkCount += 1
                if cjkCount >= maxCJKUnitLength {
                    flushCJK(upTo: nextIndex)
                }
                currentIndex = nextIndex
                continue
            }

            flushCJK(upTo: currentIndex)
            if !hasCurrent {
                currentStartIndex = currentIndex
                hasCurrent = true
            }
            currentIndex = nextIndex
        }

        flushCurrent(upTo: text.endIndex)
        flushCJK(upTo: text.endIndex)
        return units
    }
}

private extension Character {
    var isCJKLineBreakUnit: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF,
                 0x2E80...0xA4CF,
                 0xAC00...0xD7AF,
                 0xF900...0xFAFF,
                 0xFE30...0xFE4F,
                 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}
