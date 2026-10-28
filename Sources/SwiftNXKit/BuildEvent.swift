import Foundation

/// One line of `build_ipa_from_nsp.py --progress json`.
public struct BuildEvent: Decodable, Sendable {
    public enum Kind: String, Sendable {
        case stage
        case step
        case progress
        case stageEnd = "stage_end"
        case say
        case unknown
    }

    public let kind: Kind
    public let k: Int?
    public let n: Int?
    public let name: String?
    public let step: String?
    public let ok: Bool?
    public let summary: String?
    public let elapsed: Double?
    public let message: String?
    public let done: Int?
    public let total: Int?
    public let unit: String?
    public let estimated: Bool?
    public let note: String?
    public let fraction: Double?
    public let eta: Double?

    public init(
        kind: Kind,
        k: Int? = nil,
        n: Int? = nil,
        name: String? = nil,
        step: String? = nil,
        ok: Bool? = nil,
        summary: String? = nil,
        elapsed: Double? = nil,
        message: String? = nil,
        done: Int? = nil,
        total: Int? = nil,
        unit: String? = nil,
        estimated: Bool? = nil,
        note: String? = nil,
        fraction: Double? = nil,
        eta: Double? = nil
    ) {
        self.kind = kind
        self.k = k
        self.n = n
        self.name = name
        self.step = step
        self.ok = ok
        self.summary = summary
        self.elapsed = elapsed
        self.message = message
        self.done = done
        self.total = total
        self.unit = unit
        self.estimated = estimated
        self.note = note
        self.fraction = fraction
        self.eta = eta
    }

    private enum CodingKeys: String, CodingKey {
        case ev, k, n, name, step, ok, summary, elapsed, msg, done, total, unit, est, note, frac, eta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decode(String.self, forKey: .ev)) ?? ""
        kind = Kind(rawValue: rawKind) ?? .unknown
        k = try? container.decodeIfPresent(Int.self, forKey: .k)
        n = try? container.decodeIfPresent(Int.self, forKey: .n)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        step = try? container.decodeIfPresent(String.self, forKey: .step)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        elapsed = try? container.decodeIfPresent(Double.self, forKey: .elapsed)
        message = try? container.decodeIfPresent(String.self, forKey: .msg)
        done = try? container.decodeIfPresent(Int.self, forKey: .done)
        total = try? container.decodeIfPresent(Int.self, forKey: .total)
        unit = try? container.decodeIfPresent(String.self, forKey: .unit)
        estimated = try? container.decodeIfPresent(Bool.self, forKey: .est)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        fraction = try? container.decodeIfPresent(Double.self, forKey: .frac)
        eta = try? container.decodeIfPresent(Double.self, forKey: .eta)
    }
}

public enum BuildEventParser {
    /// Decodes one JSON progress line. `nil` for blank or non-JSON lines.
    public static func parse(line: String) -> BuildEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BuildEvent.self, from: data)
    }
}

public enum BuildFormatting {
    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func count(_ value: Int?, unit: String?, estimated: Bool = false) -> String {
        guard let value else { return "—" }
        let prefix = estimated ? "~" : ""
        if unit == "B" {
            return prefix + bytes(value)
        }
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        if let unit, !unit.isEmpty { return "\(formatted) \(unit)" }
        return formatted
    }

    public static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }
}
