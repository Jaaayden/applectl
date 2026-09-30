import Foundation
import RemindCore

public struct ToolError: LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
}

public enum Dates {
    public static func calendar(timezone: String? = nil) throws -> Calendar {
        var result = Calendar(identifier: .gregorian)
        if let timezone {
            guard let zone = TimeZone(identifier: timezone) else {
                throw ToolError("invalid_timezone", "Unknown timezone: \(timezone)")
            }
            result.timeZone = zone
        } else { result.timeZone = .current }
        return result
    }

    public static func parse(_ value: String, calendar: Calendar) throws -> ParsedUserDate {
        let canonical = value.range(of: #"\A(?:\d{4}-\d{2}-\d{2}(?:[ T].+)?|today|tomorrow|yesterday|now)\z"#,
                                    options: .regularExpression) != nil
        guard canonical, let parsed = DateParsing.parseUserDateWithMetadata(value, calendar: calendar) else {
            throw ToolError("invalid_date", "Invalid date: \(value). Use YYYY-MM-DD or ISO 8601.")
        }
        return parsed
    }

    public static func iso(_ date: Date, timezone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timezone
        return formatter.string(from: date)
    }

    public static func validateRange(start: Date, end: Date) throws {
        guard end > start else { throw ToolError("invalid_range", "End must be after start.") }
    }

    public static func queryRange(start: Date, end: Date) throws {
        try validateRange(start: start, end: end)
        guard end.timeIntervalSince(start) <= 366 * 86400 else {
            throw ToolError("range_too_large", "Query at most 366 days at once.")
        }
    }
}

public struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    public init(_ args: [String], values valueNames: Set<String> = [], flags flagNames: Set<String> = []) throws {
        var index = 0
        while index < args.count {
            let token = args[index]
            guard token.hasPrefix("--") else { throw ToolError("invalid_arguments", "Unexpected argument: \(token)") }
            let name = String(token.dropFirst(2))
            guard self.values[name] == nil, !self.flags.contains(name) else {
                throw ToolError("invalid_arguments", "Duplicate option: \(token)")
            }
            if flagNames.contains(name) { self.flags.insert(name); index += 1; continue }
            guard valueNames.contains(name), index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                throw ToolError("invalid_arguments", "Unknown option or missing value: \(token)")
            }
            self.values[name] = args[index + 1]
            index += 2
        }
    }
    public func value(_ name: String) -> String? { values[name] }
    public func flag(_ name: String) -> Bool { flags.contains(name) }
    public func require(_ name: String) throws -> String {
        guard let value = values[name], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError("invalid_arguments", "Provide --\(name).")
        }
        return value
    }
    public func integer(_ name: String) throws -> Int? {
        guard let text = values[name] else { return nil }
        guard let value = Int(text) else { throw ToolError("invalid_arguments", "--\(name) must be an integer.") }
        return value
    }
    public func exclusive(_ names: String...) throws {
        guard names.filter({ values[$0] != nil || flags.contains($0) }).count <= 1 else {
            throw ToolError("invalid_arguments", "Conflicting options: \(names.map { "--" + $0 }.joined(separator: ", "))")
        }
    }
}

public enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Dates.iso(date))
        }
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
}

public struct Response: Codable, Sendable {
    public let ok: Bool
    public let data: JSONValue?
    public let error: [String: String]?
    public let meta: Metadata
    public struct Metadata: Codable, Sendable {
        public let version: String
        public let command: String
        public let exitCode: Int32
    }
    public static func success(_ data: JSONValue, command: String) -> Response {
        Response(ok: true, data: data, error: nil, meta: Metadata(version: "0.1.0", command: command, exitCode: 0))
    }
    public static func failure(_ error: Error, command: String) -> Response {
        let code = (error as? ToolError)?.code ?? "operation_failed"
        return Response(ok: false, data: nil, error: ["code": code, "message": error.localizedDescription],
                        meta: Metadata(version: "0.1.0", command: command, exitCode: 1))
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public enum EventScope: String, Sendable { case this, future, all }
public struct OccurrenceKey: Hashable, Sendable {
    public let calendar: String
    public let id: String
    public let start: Date
    public init(calendar: String, id: String, start: Date) { self.calendar = calendar; self.id = id; self.start = start }
}

public enum RecurrenceSafety {
    public static func validate(recurring: Bool, scope: EventScope, occurrence: Date?) throws {
        if recurring && scope != .all && occurrence == nil {
            throw ToolError("occurrence_required", "Recurring events require --occurrence-start for this/future scope.")
        }
        if scope == .all && occurrence != nil {
            throw ToolError("invalid_arguments", "--scope all must not include --occurrence-start.")
        }
    }
}
