@preconcurrency import EventKit
import Foundation
import RemindCore

@MainActor
public struct Runner {
    public init() {}
    public static let help = """
    applectl \(ToolVersion.current) — Apple Calendar and Reminders

    All operations return JSON. Dates use local time unless --timezone is provided.

    applectl auth status
    applectl auth grant --calendar|--reminders|--all
    applectl calendars list
    applectl calendars create --name NAME [--dry-run]
    applectl calendars delete --id ID --force [--dry-run]
    applectl events list [--from DATE --to DATE --calendar ID --timezone ZONE]
    applectl events get --id ID [--occurrence-start ISO_DATE]
    applectl events add --title TITLE --start DATE --end DATE [--calendar ID --timezone ZONE]
    applectl events edit --id ID [--title TITLE --start DATE --end DATE ...]
    applectl events delete --id ID --force [--scope this|future|all --occurrence-start DATE]
    applectl lists list
    applectl lists create --name NAME [--dry-run]
    applectl lists rename --id ID --name NAME [--dry-run]
    applectl lists delete --id ID --force [--dry-run]
    applectl reminders list [--list-id ID --filter today|overdue|open|completed|all --query TEXT]
    applectl reminders get --id ID
    applectl reminders add --title TITLE [--list-id ID --due DATE --alarm DATE --repeat daily|weekly|monthly|yearly]
    applectl reminders edit --id ID [--title TITLE --due DATE --alarm DATE --notes TEXT ...]
    applectl reminders complete --id ID [--dry-run]
    applectl reminders delete --id ID --force [--dry-run]

    Common: --json (JSON is already the default), --dry-run for mutations.
    Events: --all-day, --repeat, --interval N, --count N, --until DATE, --alarm-minutes N.
    Event edits: --scope this (default), future, all; --occurrence-start from a fresh listing;
      --expected-revision VALUE; --clear-notes, --clear-location, --clear-url, --clear-alarms, --no-repeat.
    Reminder edits: --clear-due, --clear-alarm, --clear-url, --no-repeat, --incomplete.
    Event list ranges are [from,to), defaulting to the next 7 days, maximum 366 days.
    Native tags, smart lists, sections and reminder attachments are unavailable through EventKit.
    """

    public func run(_ arguments: [String]) async -> Response {
        let command = arguments.prefix(2).joined(separator: " ")
        do { return .success(try await execute(arguments), command: command) }
        catch { return .failure(error, command: command) }
    }

    /// `applectl <group> --help` returns just that group's usage lines, as JSON like every other result.
    private func helpData(_ arguments: [String]) -> JSONValue {
        let group = arguments.first.flatMap { $0.hasPrefix("-") ? nil : $0 }
        let lines = Self.help.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let usage = group.map { name in lines.filter { $0.hasPrefix("applectl \(name) ") } } ?? []
        return .object(["help": .string(usage.isEmpty ? Self.help : usage.joined(separator: "\n"))])
    }

    private func execute(_ arguments: [String]) async throws -> JSONValue {
        if arguments.contains("--help") || arguments.contains("-h") { return helpData(arguments) }
        guard arguments.count >= 2 else { throw ToolError("invalid_arguments", "Provide a group and command. Use --help.") }
        let group = arguments[0], action = arguments[1], rest = Array(arguments.dropFirst(2))
        switch group {
        case "auth": return try await auth(action, rest)
        case "calendars": return try await calendars(action, rest)
        case "events": return try await events(action, rest)
        case "lists": return try await lists(action, rest)
        case "reminders": return try await reminders(action, rest)
        default: throw ToolError("invalid_arguments", "Unknown group: \(group)")
        }
    }

    private func auth(_ action: String, _ rest: [String]) async throws -> JSONValue {
        if action == "status" {
            _ = try Options(rest, flags: ["json"])
            return .object(["calendar": .string(CalendarService.authorization),
                            "reminders": .string(RemindersStore.authorizationStatus().rawValue)])
        }
        guard action == "grant" else { throw ToolError("invalid_arguments", "Use auth status or grant.") }
        let options = try Options(rest, flags: ["calendar", "reminders", "all", "json"])
        guard options.flag("calendar") || options.flag("reminders") || options.flag("all") else {
            throw ToolError("invalid_arguments", "Select --calendar, --reminders or --all.")
        }
        if options.flag("calendar") || options.flag("all") { _ = try await CalendarService().authorize() }
        if options.flag("reminders") || options.flag("all") { try await RemindersStore().requestAccess() }
        return try await auth("status", [])
    }

    func requireDelete(_ options: Options) throws {
        guard options.flag("force") || options.flag("dry-run") else {
            throw ToolError("confirmation_required", "Deletion requires --force, or use --dry-run first.")
        }
    }

    func dryRun(_ value: JSONValue, _ options: Options) -> JSONValue {
        options.flag("dry-run") ? .object(["dryRun": .bool(true), "preview": value]) : value
    }
}
