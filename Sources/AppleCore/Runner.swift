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

    private func execute(_ arguments: [String]) async throws -> JSONValue {
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

    private func requireDelete(_ options: Options) throws {
        guard options.flag("force") || options.flag("dry-run") else {
            throw ToolError("confirmation_required", "Deletion requires --force, or use --dry-run first.")
        }
    }

    private func dryRun(_ value: JSONValue, _ options: Options) -> JSONValue {
        options.flag("dry-run") ? .object(["dryRun": .bool(true), "preview": value]) : value
    }

    private func calendars(_ action: String, _ rest: [String]) async throws -> JSONValue {
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

    private func eventOptions(_ action: String, _ rest: [String]) throws -> Options {
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

    private func eventChanges(_ options: Options, calendar: Calendar, adding: Bool) throws -> EventChanges {
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

    private func events(_ action: String, _ rest: [String]) async throws -> JSONValue {
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
            guard rest.contains(where: { ["--title", "--start", "--end", "--timezone", "--notes", "--location", "--url", "--repeat", "--alarm-minutes", "--all-day", "--timed", "--no-repeat", "--clear-notes", "--clear-location", "--clear-url", "--clear-alarms"].contains($0) }) else {
                throw ToolError("invalid_arguments", "No update fields were provided.")
            }
            return dryRun(try JSONValue.encode(service.update(id: options.require("id"), occurrence: occurrence, scope: scope,
                                                             revision: options.value("expected-revision"), changes: changes, dryRun: options.flag("dry-run"))), options)
        default: return dryRun(try JSONValue.encode(service.delete(id: options.require("id"), occurrence: occurrence, scope: scope,
                                                                 revision: options.value("expected-revision"), dryRun: options.flag("dry-run"))), options)
        }
    }

    private func listTarget(_ options: Options) throws -> ReminderListTarget? {
        try options.exclusive("list", "list-id")
        if let id = options.value("list-id") { return .id(id) }
        if let name = options.value("list") { return .name(name) }
        return nil
    }

    private func lists(_ action: String, _ rest: [String]) async throws -> JSONValue {
        let options: Options
        switch action {
        case "list": options = try Options(rest, flags: ["json"])
        case "create": options = try Options(rest, values: ["name"], flags: ["json", "dry-run"]); _ = try options.require("name")
        case "rename": options = try Options(rest, values: ["id", "name"], flags: ["json", "dry-run"]); _ = try options.require("id"); _ = try options.require("name")
        case "delete": options = try Options(rest, values: ["id"], flags: ["json", "force", "dry-run"]); _ = try options.require("id"); try requireDelete(options)
        default: throw ToolError("invalid_arguments", "Unknown lists command: \(action)")
        }
        let store = RemindersStore()
        try await store.requestAccess()
        switch action {
        case "list": return try JSONValue.encode(await store.lists())
        case "create":
            if options.flag("dry-run") { return dryRun(.object(["title": .string(try options.require("name"))]), options) }
            return try JSONValue.encode(await store.createList(name: options.require("name")))
        default:
            let before = try await store.writableList(.id(options.require("id")))
            guard before.id == options.value("id") else { throw ToolError("invalid_arguments", "Use the full list ID for rename/delete.") }
            if !options.flag("dry-run") {
                if action == "rename" { try await store.renameList(target: .id(before.id), newName: options.require("name")) }
                else { try await store.deleteList(target: .id(before.id)) }
            }
            if options.flag("dry-run") {
                return .object(["dryRun": .bool(true), "before": try JSONValue.encode(before),
                                "changes": action == "rename" ? .object(["title": .string(try options.require("name"))]) : .object(["delete": .bool(true)])])
            }
            return try JSONValue.encode(action == "rename" ? ReminderList(id: before.id, title: options.require("name")) : before)
        }
    }

    private func url(_ value: String?) throws -> URL? {
        guard let value else { return nil }
        guard let url = URL(string: value), url.scheme != nil else { throw ToolError("invalid_url", "URL must include a scheme.") }
        return url
    }

    private func reminderOptions(_ action: String, _ rest: [String]) throws -> Options {
        let values: Set<String> = ["id", "title", "list", "list-id", "due", "alarm", "notes", "url", "priority", "repeat", "interval", "timezone"]
        switch action {
        case "list": return try Options(rest, values: ["list", "list-id", "filter", "query", "timezone"], flags: ["json"])
        case "get": return try Options(rest, values: ["id"], flags: ["json"])
        case "add": return try Options(rest, values: values.subtracting(["id"]), flags: ["json", "dry-run"])
        case "edit": return try Options(rest, values: values, flags: ["json", "dry-run", "clear-due", "clear-alarm", "clear-url", "no-repeat", "incomplete"])
        case "complete": return try Options(rest, values: ["id"], flags: ["json", "dry-run"])
        case "delete": return try Options(rest, values: ["id"], flags: ["json", "dry-run", "force"])
        default: throw ToolError("invalid_arguments", "Unknown reminders command: \(action)")
        }
    }

    private func reminders(_ action: String, _ rest: [String]) async throws -> JSONValue {
        let options = try reminderOptions(action, rest)
        let calendar = try Dates.calendar(timezone: options.value("timezone"))
        let target = try listTarget(options)
        try options.exclusive("due", "clear-due"); try options.exclusive("alarm", "clear-alarm")
        try options.exclusive("url", "clear-url"); try options.exclusive("repeat", "no-repeat")
        let due = try options.value("due").map { try Dates.parse($0, calendar: calendar) }
        let alarm = try options.value("alarm").map { try Dates.parse($0, calendar: calendar) }
        let link = try url(options.value("url"))
        let priority = try options.value("priority").map { value in
            guard let priority = ReminderPriority(rawValue: value) else { throw ToolError("invalid_arguments", "Priority must be none, low, medium or high.") }
            return priority
        }
        var recurrence: RecurrenceRule?
        if let frequency = options.value("repeat") {
            guard let frequency = RecurrenceFrequency(rawValue: frequency) else { throw ToolError("invalid_arguments", "Invalid repeat frequency.") }
            let interval = try options.integer("interval") ?? 1
            guard interval > 0 else { throw ToolError("invalid_arguments", "Repeat interval must be positive.") }
            recurrence = RecurrenceRule(frequency: frequency, interval: interval)
        } else if options.value("interval") != nil { throw ToolError("invalid_arguments", "--interval requires --repeat.") }
        if action == "add" { _ = try options.require("title") }
        if options.value("title") != nil { _ = try options.require("title") }
        if ["get", "edit", "complete", "delete"].contains(action) { _ = try options.require("id") }
        if action == "delete" { try requireDelete(options) }
        let store = RemindersStore(calendar: calendar)
        try await store.requestAccess()
        switch action {
        case "list":
            guard let filter = ReminderFiltering.parse(options.value("filter") ?? "open", calendar: calendar) else { throw ToolError("invalid_arguments", "Unknown reminder filter.") }
            let items = try await store.reminders(matching: target)
            var result = ReminderFiltering.sort(ReminderFiltering.apply(items, filter: filter, calendar: calendar))
            if let query = options.value("query") {
                result = result.filter { [$0.title, $0.notes ?? "", $0.url?.absoluteString ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } }
            }
            return try JSONValue.encode(result)
        case "get": return try JSONValue.encode(await store.reminderItem(id: options.require("id")))
        case "add":
            let title = try options.require("title")
            let list: ReminderListTarget
            if let target { list = target }
            else if let defaultList = await store.defaultList() { list = .id(defaultList.id) }
            else { throw ToolError("not_found", "No default reminder list. Provide --list-id.") }
            let destination = try await store.writableList(list)
            if options.flag("dry-run") {
                let notification = alarm ?? (due?.isDateOnly == false ? due : nil)
                return dryRun(.object([
                    "title": .string(title), "listID": .string(destination.id), "listName": .string(destination.title),
                    "dueDate": due.map { .string(Dates.iso($0.date, timezone: calendar.timeZone)) } ?? .null,
                    "dueDateIsAllDay": due.map { .bool($0.isDateOnly) } ?? .null,
                    "alarmDate": notification.map { .string(Dates.iso($0.date, timezone: calendar.timeZone)) } ?? .null,
                    "notes": options.value("notes").map(JSONValue.string) ?? .null,
                    "url": link.map { .string($0.absoluteString) } ?? .null,
                    "priority": .string((priority ?? .none).rawValue),
                    "recurrenceRule": try recurrence.map { try JSONValue.encode($0) } ?? .null,
                ]), options)
            }
            return try JSONValue.encode(await store.createReminder(ReminderDraft(title: title, notes: options.value("notes"), url: link,
                                                                                 dueDate: due, alarmDate: alarm, recurrenceRule: recurrence, priority: priority ?? .none), target: list))
        case "edit":
            let before = try await store.reminderItem(id: options.require("id"))
            _ = try await store.writableList(.id(before.listID))
            guard rest.contains(where: { ["--title", "--list", "--list-id", "--due", "--alarm", "--notes", "--url", "--priority", "--repeat", "--clear-due", "--clear-alarm", "--clear-url", "--no-repeat", "--incomplete"].contains($0) }) else {
                throw ToolError("invalid_arguments", "No update fields were provided.")
            }
            if let target { _ = try await store.writableList(target) }
            if options.flag("dry-run") {
                var changes: [String: JSONValue] = [:]
                for name in ["title", "list", "list-id", "notes", "priority", "repeat", "interval"] {
                    if let value = options.value(name) { changes[name] = .string(value) }
                }
                if let due { changes["dueDate"] = .string(Dates.iso(due.date, timezone: calendar.timeZone)); changes["dueDateIsAllDay"] = .bool(due.isDateOnly) }
                if let alarm { changes["alarmDate"] = .string(Dates.iso(alarm.date, timezone: calendar.timeZone)) }
                if let link { changes["url"] = .string(link.absoluteString) }
                for (flag, field) in [("clear-due", "dueDate"), ("clear-alarm", "alarmDate"), ("clear-url", "url"), ("no-repeat", "recurrenceRule")] {
                    if options.flag(flag) { changes[field] = .null }
                }
                if options.flag("incomplete") { changes["isCompleted"] = .bool(false) }
                return .object(["dryRun": .bool(true), "before": try JSONValue.encode(before), "changes": .object(changes)])
            }
            return try JSONValue.encode(await store.updateReminder(id: before.id, update: ReminderUpdate(
                title: options.value("title"), notes: options.value("notes"),
                url: options.flag("clear-url") ? .some(nil) : link.map { .some($0) },
                dueDate: options.flag("clear-due") ? .some(nil) : due.map { .some($0) },
                alarmDate: options.flag("clear-alarm") ? .some(nil) : alarm.map { .some($0) },
                recurrenceRule: options.flag("no-repeat") ? .some(nil) : recurrence.map { .some($0) },
                priority: priority, listTarget: target, isCompleted: options.flag("incomplete") ? false : nil)))
        default:
            let before = try await store.reminderItem(id: options.require("id"))
            _ = try await store.writableList(.id(before.listID))
            if options.flag("dry-run") { return dryRun(try JSONValue.encode(before), options) }
            if action == "complete" { return try JSONValue.encode(await store.completeReminders(ids: [before.id])) }
            _ = try await store.deleteReminders(ids: [before.id])
            return .object(["deleted": .bool(true), "id": .string(before.id)])
        }
    }
}
