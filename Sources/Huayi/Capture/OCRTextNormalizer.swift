import Foundation

enum OCRTextNormalizer {
    static let maximumUTF16Length = 5_000

    static func normalize(_ blocks: [OCRTextBlock]) -> String {
        let ordered = blocks
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                let lineTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.55
                if verticalDistance <= lineTolerance {
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }

        var lines: [String] = []
        for block in ordered {
            let value = block.text
                .replacingOccurrences(of: "\u{00a0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            if let last = lines.last,
               shouldJoin(previous: last, next: value) {
                lines[lines.count - 1] = join(previous: last, next: value)
            } else {
                lines.append(value)
            }
        }
        return truncateUTF16(lines.joined(separator: "\n"), limit: maximumUTF16Length)
    }

    static func truncateUTF16(_ text: String, limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        let utf16 = Array(text.utf16.prefix(limit))
        return String(decoding: utf16, as: UTF16.self)
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        guard let last = previous.last, let first = next.first else { return false }
        if isCJK(last), isCJK(first) { return true }
        if last == "-", first.isLetter { return true }
        if last.isLetter || last.isNumber {
            return first.isLowercase && !previous.hasSuffix(".")
        }
        return false
    }

    private static func join(previous: String, next: String) -> String {
        if previous.hasSuffix("-") {
            return String(previous.dropLast()) + next
        }
        guard let last = previous.last, let first = next.first else { return previous + next }
        return isCJK(last) && isCJK(first) ? previous + next : previous + " " + next
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }
}
