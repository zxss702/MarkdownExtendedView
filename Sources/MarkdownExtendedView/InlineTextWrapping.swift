import Foundation

enum MarkdownInlineTextWrapping {
    static func units(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var units: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            units.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in text {
            if character.isNewline {
                flushCurrent()
                units.append(String(character))
                continue
            }

            if character.isWhitespace {
                current.append(character)
                flushCurrent()
                continue
            }

            if character.isCJKLineBreakUnit {
                flushCurrent()
                units.append(String(character))
                continue
            }

            current.append(character)
        }

        flushCurrent()
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
