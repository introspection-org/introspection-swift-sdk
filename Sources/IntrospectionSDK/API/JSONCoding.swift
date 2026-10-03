import Foundation

/// The SDK's JSON coders. Models declare explicit `CodingKeys` for their
/// snake_case wire names; no key-coding strategy is set, because one would
/// also rewrite the keys of open-ended `JSONValue` objects such as metadata.
public enum JSONCoding {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let text = try container.decode(String.self)
            guard let date = ISO8601.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(text)")
            }
            return date
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.format(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// ISO-8601 parsing tolerant of the shapes the API emits: with or without
/// fractional seconds (up to microseconds), with `Z`, an offset, or no zone
/// (read as UTC).
public enum ISO8601 {
    public static func parse(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.contains(" "), !value.contains("T") {
            value = value.replacingOccurrences(of: " ", with: "T")
        }
        if !hasZone(value) { value += "Z" }
        // Normalize fractional seconds to milliseconds, which the formatter accepts.
        if let dot = value.firstIndex(of: ".") {
            let afterDot = value.index(after: dot)
            let digitsEnd = value[afterDot...].firstIndex(where: { !$0.isNumber }) ?? value.endIndex
            let digits = String(value[afterDot..<digitsEnd])
            let millis = String((digits + "000").prefix(3))
            value = String(value[..<dot]) + "." + millis + String(value[digitsEnd...])
        }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    public static func format(_ date: Date) -> String {
        fractional.string(from: date)
    }

    private static func hasZone(_ value: String) -> Bool {
        if value.hasSuffix("Z") || value.hasSuffix("z") { return true }
        guard let tIndex = value.firstIndex(of: "T") else { return false }
        let time = value[tIndex...]
        return time.contains("+") || time.dropFirst().contains("-")
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
