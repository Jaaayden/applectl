@preconcurrency import EventKit
import Foundation
import RemindCore

extension Runner {
    func calendars(_ action: String, _ rest: [String]) async throws -> JSONValue {
        let options: Options
        switch action {
        case "list": options = try Options(rest, flags: ["json"])
        case "create": options = try Options(rest, values: ["name"], flags: ["json", "dry-run"]); _ = try options.require("name")
        case "delete": options = try Options(rest, values: ["id"], flags: ["json", "dry-run", "force"]); _ = try options.require("id"); try requireDelete(options)
        default: throw ToolError("invalid_arguments", "Unknown calendars command: \(action)")
        }
        let service = CalendarService()
        _ = try await service.authorize()
        switch action {
        case "list": return try JSONValue.encode(service.calendars())
        case "create":
            if options.flag("dry-run") { return dryRun(.object(["title": .string(try options.require("name"))]), options) }
            return try JSONValue.encode(service.createCalendar(title: options.require("name")))
        default: return dryRun(try JSONValue.encode(service.deleteCalendar(id: options.require("id"), dryRun: options.flag("dry-run"))), options)
        }
    }

    func eventOptions(_ action: String, _ rest: [String]) throws -> Options {
        let readValues: Set<String> = ["id", "from", "to", "calendar", "timezone", "occurrence-start"]
        let mutationValues: Set<String> = ["id", "calendar", "title", "start", "end", "timezone", "notes", "location", "url",
                                           "repeat", "interval", "count", "until", "alarm-minutes", "scope", "occurrence-start", "expected-revision"]
        switch action {
        case "list": return try Options(rest, values: readValues.subtracting(["id", "occurrence-start"]), flags: ["json"])
        case "get": return try Options(rest, values: ["id", "occurrence-start", "timezone"], flags: ["json"])
        case "add": return try Options(rest, values: mutationValues.subtracting(["id", "scope", "occurrence-start", "expected-revision"]), flags: ["json", "dry-run", "all-day"])
        case "edit": return try Options(rest, values: mutationValues.subtracting(["calendar"]), flags: ["json", "dry-run", "all-day", "timed", "clear-notes", "clear-location", "clear-url", "clear-alarms", "no-repeat"])
        case "delete": return try Options(rest, values: ["id", "scope", "occurrence-start", "timezone", "expected-revision"], flags: ["json", "dry-run", "force"])
        default: throw ToolError("invalid_arguments", "Unknown events command: \(action)")
        }
    }

    func eventChanges(_ options: Options, calendar: Calendar, adding: Bool) throws -> EventChanges {
        try options.exclusive("all-day", "timed")
        try options.exclusive("notes", "clear-notes")
        try options.exclusive("location", "clear-location")
        try options.exclusive("url", "clear-url")
        try options.exclusive("alarm-minutes", "clear-alarms")
        try options.exclusive("repeat", "no-repeat")
        try options.exclusive("count", "until")
        var changes = EventChanges()
        changes.title = adding ? try options.require("title") : options.value("title")
        changes.start = try options.value("start").map { try Dates.parse($0, calendar: calendar).date }
        changes.end = try options.value("end").map { try Dates.parse($0, calendar: calendar).date }
        if adding { _ = try options.require("start"); _ = try options.require("end") }
        if let start = changes.start, let end = changes.end { try Dates.validateRange(start: start, end: end) }
        changes.timezone = adding || options.value("timezone") != nil ? calendar.timeZone : nil
        changes.allDay = options.flag("all-day") ? true : (options.flag("timed") || adding ? false : nil)
        changes.notes = options.value("notes"); changes.location = options.value("location")
        changes.url = try url(options.value("url"))
        changes.clearNotes = options.flag("clear-notes"); changes.clearLocation = options.flag("clear-location")
        changes.clearURL = options.flag("clear-url"); changes.clearAlarms = options.flag("clear-alarms")
        changes.clearRecurrence = options.flag("no-repeat")
        changes.alarmMinutes = try options.integer("alarm-minutes")
        if let frequency = options.value("repeat") {
            let frequencies: [String: EKRecurrenceFrequency] = ["daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly]
            guard let frequency = frequencies[frequency] else { throw ToolError("invalid_arguments", "Invalid repeat frequency.") }
            let interval = try options.integer("interval") ?? 1
            guard interval > 0 else { throw ToolError("invalid_arguments", "Repeat interval must be positive.") }
            var end: EKRecurrenceEnd?
            if let count = try options.integer("count") {
                guard count > 0 else { throw ToolError("invalid_arguments", "Repeat count must be positive.") }
                end = EKRecurrenceEnd(occurrenceCount: count)
            }
            if let until = options.value("until") { end = EKRecurrenceEnd(end: try Dates.parse(until, calendar: calendar).date) }
            changes.recurrence = EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end)
        } else if ["interval", "count", "until"].contains(where: { options.value($0) != nil }) {
            throw ToolError("invalid_arguments", "--interval/--count/--until require --repeat.")
        }
        return changes
    }

    func events(_ action: String, _ rest: [String]) async throws -> JSONValue {
        let options = try eventOptions(action, rest)
        var calendar = try Dates.calendar(timezone: options.value("timezone"))
        let occurrence = try options.value("occurrence-start").map { try Dates.parse($0, calendar: calendar).date }
        guard let scope = EventScope(rawValue: options.value("scope") ?? "this") else { throw ToolError("invalid_arguments", "Invalid scope. Use this, future or all.") }
        if ["get", "edit", "delete"].contains(action) { _ = try options.require("id") }
        if action == "delete" { try requireDelete(options) }
        var prevalidatedChanges: EventChanges?
        if action == "add" { prevalidatedChanges = try eventChanges(options, calendar: calendar, adding: true) }
        let service = CalendarService()
        _ = try await service.authorize()
        switch action {
        case "list":
            let now = calendar.startOfDay(for: Date())
            let start = try options.value("from").map { try Dates.parse($0, calendar: calendar).date } ?? now
            guard let fallbackEnd = calendar.date(byAdding: .day, value: 7, to: start) else { throw ToolError("invalid_date", "Could not calculate the query range.") }
            let end = try options.value("to").map { try Dates.parse($0, calendar: calendar).date } ?? fallbackEnd
            return try JSONValue.encode(service.events(from: start, to: end, calendar: options.value("calendar")))
        case "get": return try JSONValue.encode(service.event(id: options.require("id"), occurrence: occurrence))
        case "add":
            guard let changes = prevalidatedChanges else { throw ToolError("invalid_arguments", "Missing event fields.") }
            return dryRun(try JSONValue.encode(service.create(calendar: options.value("calendar"), changes: changes, dryRun: options.flag("dry-run"))), options)
        case "edit":
            let existing = try service.event(id: options.require("id"), occurrence: occurrence)
            if options.value("timezone") == nil { calendar = try Dates.calendar(timezone: existing.timezone) }
            let changes = try eventChanges(options, calendar: calendar, adding: false)
            guard !changes.isEmpty else { throw ToolError("invalid_arguments", "No update fields were provided.") }
            return dryRun(try JSONValue.encode(service.update(id: options.require("id"), occurrence: occurrence, scope: scope,
                                                             revision: options.value("expected-revision"), changes: changes, dryRun: options.flag("dry-run"))), options)
        default: return dryRun(try JSONValue.encode(service.delete(id: options.require("id"), occurrence: occurrence, scope: scope,
                                                                 revision: options.value("expected-revision"), dryRun: options.flag("dry-run"))), options)
        }
    }
}
