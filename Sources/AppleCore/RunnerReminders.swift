@preconcurrency import EventKit
import Foundation
import RemindCore

extension Runner {
    func listTarget(_ options: Options) throws -> ReminderListTarget? {
        try options.exclusive("list", "list-id")
        if let id = options.value("list-id") { return .id(id) }
        if let name = options.value("list") { return .name(name) }
        return nil
    }

    func lists(_ action: String, _ rest: [String]) async throws -> JSONValue {
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

    func url(_ value: String?) throws -> URL? {
        guard let value else { return nil }
        guard let url = URL(string: value), url.scheme != nil else { throw ToolError("invalid_url", "URL must include a scheme.") }
        return url
    }

    func reminderOptions(_ action: String, _ rest: [String]) throws -> Options {
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

    func reminders(_ action: String, _ rest: [String]) async throws -> JSONValue {
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
            let update = ReminderUpdate(
                title: options.value("title"), notes: options.value("notes"),
                url: options.flag("clear-url") ? .some(nil) : link.map { .some($0) },
                dueDate: options.flag("clear-due") ? .some(nil) : due.map { .some($0) },
                alarmDate: options.flag("clear-alarm") ? .some(nil) : alarm.map { .some($0) },
                recurrenceRule: options.flag("no-repeat") ? .some(nil) : recurrence.map { .some($0) },
                priority: priority, listTarget: target, isCompleted: options.flag("incomplete") ? false : nil)
            guard !update.isEmpty else { throw ToolError("invalid_arguments", "No update fields were provided.") }
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
            return try JSONValue.encode(await store.updateReminder(id: before.id, update: update))
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
