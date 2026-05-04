import Foundation

enum MarkdownInlineTextWrapping {
    private static let maxCJKUnitLength = 8

    static func units(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var units: [String] = []
        var current = ""
        var currentCJK = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            units.append(current)
            current.removeAll(keepingCapacity: true)
        }

        func flushCJK() {
            guard !currentCJK.isEmpty else { return }
            units.append(currentCJK)
            currentCJK.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.isNewline {
                flushCurrent()
                flushCJK()
                units.append(String(character))
                continue
            }

            if character.isWhitespace {
                current.append(character)
                flushCJK()
                flushCurrent()
                continue
            }

            if character.isCJKLineBreakUnit {
                flushCurrent()
                currentCJK.append(character)
                if currentCJK.count >= maxCJKUnitLength {
                    flushCJK()
                }
                continue
            }

            flushCJK()
            current.append(character)
        }

        flushCurrent()
        flushCJK()
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
