import Foundation

/// A 64-bit Nintendo Switch title ID.
///
/// Base games use a title ID whose low 12 bits are `0x000`; an update uses the
/// base title ID plus `0x800`. DLC IDs live above the base ID and cannot be
/// told apart reliably from a base ID without the ticket/metadata, so the UI
/// relies on the role the user picked for a file.
public struct TitleID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: UInt64

    public init(value: UInt64) {
        self.value = value
    }

    public init?(hex string: String) {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("0X") { cleaned.removeFirst(2) }
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")
        guard cleaned.count == 16,
              cleaned.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(cleaned, radix: 16)
        else { return nil }
        self.value = value
    }

    public init?(number: String) {
        var cleaned = number.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("0x") {
            cleaned.removeFirst(2)
            guard let value = UInt64(cleaned, radix: 16) else { return nil }
            self.value = value
        } else {
            guard let value = UInt64(cleaned) else { return nil }
            self.value = value
        }
    }

    public var hex: String { String(format: "%016llX", value) }
    public var description: String { hex }

    /// The low 12 bits of the title ID.
    public var suffix: UInt16 { UInt16(value & 0xFFF) }

    /// Updates are the base title ID plus `0x800`.
    public var isUpdate: Bool { suffix == 0x800 }

    /// A plain base-game title ID ends in `0x000`.
    public var isBase: Bool { suffix == 0x000 }

    /// The base-game title ID for an update, or the receiver for a base ID.
    public var baseID: TitleID {
        isUpdate ? TitleID(value: value - 0x800) : self
    }

    public var shortHex: String {
        let text = hex
        return String(text.prefix(4)) + "…" + String(text.suffix(4))
    }

    public static func extract(fromFilename filename: String) -> TitleID? {
        let patterns = [
            "\\[([0-9A-Fa-f]{16})\\]",
            "\\(([0-9A-Fa-f]{16})\\)",
            "\\b(01[0-9A-Fa-f]{14})\\b",
        ]
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = regex.firstMatch(in: filename, range: range),
               match.numberOfRanges > 1,
               let capture = Range(match.range(at: 1), in: filename),
               let id = TitleID(hex: String(filename[capture])) {
                return id
            }
        }
        return nil
    }

    public static func extractVersion(fromFilename filename: String) -> UInt64? {
        let patterns = [
            "\\[v([0-9]+)\\]",
            "\\bv([0-9]{1,10})\\b",
        ]
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            if let match = regex.firstMatch(in: filename, range: range),
               match.numberOfRanges > 1,
               let capture = Range(match.range(at: 1), in: filename) {
                return UInt64(filename[capture])
            }
        }
        return nil
    }
}
