// Calendar access is adapted from sichengchen/apple-calendar-cli and informed by acal.
// Their MIT notices are retained under licenses/.
@preconcurrency import EventKit
import Foundation
import RemindCore

public struct CalendarRecord: Codable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let writable: Bool
}

public struct EventRecord: Codable, Sendable {
    public let id: String
    public let calendarId: String
    public let title: String
    public let start: String
    public let end: String
    public let occurrenceStart: String
    public let timezone: String
    public let allDay: Bool
    public let recurring: Bool
    public let detached: Bool
    public let notes: String?
    public let location: String?
    public let url: String?
    public let recurrence: [RecurrenceRecord]
    public let alarms: [CalendarAlarmRecord]
    public let revision: String?
}

public struct CalendarAlarmRecord: Codable, Sendable {
    public let relativeMinutes: Double?
    public let absoluteDate: String?
    public let locationBased: Bool
}

public struct RecurrenceRecord: Codable, Sendable {
    public let frequency: String
    public let interval: Int
    public let count: Int?
    public let until: String?
}

public struct EventChanges {
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var timezone: TimeZone?
    public var allDay: Bool?
    public var notes: String?
    public var location: String?
    public var url: URL?
    public var clearNotes = false
    public var clearLocation = false
    public var clearURL = false
    public var recurrence: EKRecurrenceRule?
    public var clearRecurrence = false
    public var alarmMinutes: Int?
    public var clearAlarms = false
    public init() {}
}

@MainActor
public final class CalendarService {
    private let store = EKEventStore()
    public init() {}

    public static var authorization: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return "full-access"
        case .writeOnly: return "write-only"
        case .notDetermined: return "not-determined"
        case .restricted: return "restricted"
        default: return "denied"
        }
    }

    public func authorize() async throws -> String {
        if Self.authorization == "not-determined" {
            let granted = try await AuthorizationRequest.perform { completion in
                store.requestFullAccessToEvents(completion: completion)
            }
            if !granted { throw ToolError("permission_denied", "Allow AppleCtl in System Settings > Privacy & Security > Calendars.") }
        }
        try requireAccess()
        return Self.authorization
    }

    private func requireAccess() throws {
        guard Self.authorization == "full-access" else {
            throw ToolError("permission_denied", "Calendar full access is required. Run applectl auth grant --calendar.")
        }
    }

    public func calendars() throws -> [CalendarRecord] {
        try requireAccess()
        return store.calendars(for: .event).map(record).sorted { $0.title < $1.title }
    }

    public func resolveCalendar(_ nameOrID: String?) throws -> EKCalendar {
        try requireAccess()
        guard let nameOrID else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw ToolError("not_found", "No default calendar. Provide --calendar.")
            }
            return calendar
        }
        let calendars = store.calendars(for: .event)
        if let exact = calendars.first(where: { $0.calendarIdentifier == nameOrID }) { return exact }
        let matches = calendars.filter { $0.title == nameOrID }
        guard matches.count == 1, let match = matches.first else {
            throw ToolError(matches.isEmpty ? "not_found" : "ambiguous_calendar", "Calendar name is missing or ambiguous; use its full ID.")
        }
        return match
    }

    public func createCalendar(title: String) throws -> CalendarRecord {
        try requireAccess()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError("invalid_arguments", "Calendar title cannot be empty.") }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.source = store.sources.first(where: { $0.sourceType == .local }) ?? store.defaultCalendarForNewEvents?.source
        guard calendar.source != nil else { throw ToolError("not_found", "No writable calendar source is available.") }
        try store.saveCalendar(calendar, commit: true)
        return record(calendar)
    }

    public func deleteCalendar(id: String, dryRun: Bool) throws -> CalendarRecord {
        let calendar = try resolveCalendar(id)
        guard calendar.calendarIdentifier == id else { throw ToolError("invalid_arguments", "Delete calendars by full ID.") }
        try writable(calendar)
        let before = record(calendar)
        if !dryRun { try store.removeCalendar(calendar, commit: true) }
        return before
    }

    public func events(from start: Date, to end: Date, calendar nameOrID: String? = nil) throws -> [EventRecord] {
        try requireAccess()
        try Dates.queryRange(start: start, end: end)
        let calendars = try nameOrID.map { [try resolveCalendar($0)] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let items = store.events(matching: predicate)
        var seen: Set<OccurrenceKey> = []
        return items.filter { event in
            seen.insert(OccurrenceKey(calendar: event.calendar.calendarIdentifier,
                                      id: event.calendarItemIdentifier, start: event.startDate)).inserted
        }.sorted { $0.startDate < $1.startDate }.map { record($0) }
    }

    public func event(id: String, occurrence: Date? = nil) throws -> EventRecord {
        try requireAccess()
        return record(try resolveEvent(id: id, occurrence: occurrence))
    }

    private func resolveEvent(id: String, occurrence: Date?) throws -> EKEvent {
        guard let base = store.calendarItem(withIdentifier: id) as? EKEvent else {
            throw ToolError("not_found", "Event not found; list events again to get current IDs.")
        }
        guard let occurrence else { return base }
        let predicate = store.predicateForEvents(withStart: occurrence.addingTimeInterval(-1),
                                                end: occurrence.addingTimeInterval(1), calendars: [base.calendar])
        let matches = store.events(matching: predicate).filter { item in
            let sameSeries = item.calendarItemIdentifier == id ||
                (base.calendarItemExternalIdentifier != nil && item.calendarItemExternalIdentifier == base.calendarItemExternalIdentifier)
            return sameSeries && abs(item.startDate.timeIntervalSince(occurrence)) < 0.001
        }
        guard matches.count == 1, let match = matches.first else {
            throw ToolError("occurrence_not_found", "The requested occurrence is missing or ambiguous. Refresh the date range first.")
        }
        return match
    }

    public func create(calendar nameOrID: String?, changes: EventChanges, dryRun: Bool) throws -> EventRecord {
        let calendar = try resolveCalendar(nameOrID)
        try writable(calendar)
        guard let title = changes.title, let start = changes.start, let end = changes.end else {
            throw ToolError("invalid_arguments", "Provide title, start and end.")
        }
        try Dates.validateRange(start: start, end: end)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        try apply(changes, to: event)
        if !dryRun { try store.save(event, span: .thisEvent, commit: true) }
        return record(event, identifier: dryRun ? "pending" : nil)
    }

    public func update(id: String, occurrence: Date?, scope: EventScope, revision: String?,
                       changes: EventChanges, dryRun: Bool) throws -> EventRecord {
        try requireAccess()
        let base = try resolveEvent(id: id, occurrence: nil)
        try RecurrenceSafety.validate(recurring: base.hasRecurrenceRules || base.isDetached, scope: scope, occurrence: occurrence)
        if scope == .all && base.isDetached {
            throw ToolError("series_required", "Use the original series ID for an all-occurrences edit.")
        }
        let event = try resolveEvent(id: id, occurrence: occurrence)
        try writable(event.calendar)
        try verifyRevision(revision, event: event)
        try apply(changes, to: event)
        if !dryRun { try store.save(event, span: scope == .this ? .thisEvent : .futureEvents, commit: true) }
        return record(event)
    }

    public func delete(id: String, occurrence: Date?, scope: EventScope, revision: String?, dryRun: Bool) throws -> EventRecord {
        try requireAccess()
        let base = try resolveEvent(id: id, occurrence: nil)
        try RecurrenceSafety.validate(recurring: base.hasRecurrenceRules || base.isDetached, scope: scope, occurrence: occurrence)
        if scope == .all && base.isDetached { throw ToolError("series_required", "Use the original series ID for deleting all occurrences.") }
        let event = try resolveEvent(id: id, occurrence: occurrence)
        try writable(event.calendar)
        try verifyRevision(revision, event: event)
        let before = record(event)
        if !dryRun { try store.remove(event, span: scope == .this ? .thisEvent : .futureEvents, commit: true) }
        return before
    }

    private func writable(_ calendar: EKCalendar) throws {
        guard calendar.allowsContentModifications else { throw ToolError("read_only", "This calendar is read-only.") }
    }

    private func verifyRevision(_ expected: String?, event: EKEvent) throws {
        if let expected, expected != record(event).revision { throw ToolError("conflict", "Event changed since it was read. Read it again before editing.") }
    }

    private func apply(_ changes: EventChanges, to event: EKEvent) throws {
        let start = changes.start ?? event.startDate
        let end = changes.end ?? event.endDate
        guard let start, let end else { throw ToolError("invalid_range", "An event requires start and end.") }
        try Dates.validateRange(start: start, end: end)
        if let title = changes.title {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError("invalid_arguments", "Title cannot be empty.") }
            event.title = title
        }
        event.startDate = start; event.endDate = end
        if let timezone = changes.timezone { event.timeZone = timezone }
        if let allDay = changes.allDay { event.isAllDay = allDay }
        if changes.clearNotes { event.notes = nil } else if let notes = changes.notes { event.notes = notes }
        if changes.clearLocation { event.location = nil } else if let location = changes.location { event.location = location }
        if changes.clearURL { event.url = nil } else if let url = changes.url { event.url = url }
        if changes.clearRecurrence { event.recurrenceRules = nil } else if let recurrence = changes.recurrence { event.recurrenceRules = [recurrence] }
        if changes.clearAlarms { event.alarms = nil }
        else if let minutes = changes.alarmMinutes { event.alarms = [EKAlarm(relativeOffset: Double(minutes) * 60)] }
    }

    private func record(_ calendar: EKCalendar) -> CalendarRecord {
        CalendarRecord(id: calendar.calendarIdentifier, title: calendar.title, source: calendar.source?.title ?? "", writable: calendar.allowsContentModifications)
    }

    private func record(_ event: EKEvent, identifier: String? = nil) -> EventRecord {
        let timezone = event.timeZone ?? .current
        return EventRecord(id: identifier ?? event.calendarItemIdentifier, calendarId: event.calendar?.calendarIdentifier ?? "",
                           title: event.title ?? "", start: Dates.iso(event.startDate, timezone: timezone),
                           end: Dates.iso(event.endDate, timezone: timezone), occurrenceStart: Dates.iso(event.startDate, timezone: timezone),
                           timezone: timezone.identifier, allDay: event.isAllDay, recurring: event.hasRecurrenceRules || event.isDetached,
                           detached: event.isDetached, notes: event.notes, location: event.location, url: event.url?.absoluteString,
                           recurrence: (event.recurrenceRules ?? []).map { rule in
                               let names: [EKRecurrenceFrequency: String] = [.daily: "daily", .weekly: "weekly", .monthly: "monthly", .yearly: "yearly"]
                               return RecurrenceRecord(frequency: names[rule.frequency] ?? "unknown", interval: rule.interval,
                                                       count: (rule.recurrenceEnd?.occurrenceCount ?? 0) > 0 ? rule.recurrenceEnd?.occurrenceCount : nil,
                                                       until: rule.recurrenceEnd?.endDate.map { Dates.iso($0, timezone: timezone) })
                           }, alarms: (event.alarms ?? []).map { alarm in
                               CalendarAlarmRecord(relativeMinutes: alarm.absoluteDate == nil && alarm.structuredLocation == nil ? alarm.relativeOffset / 60 : nil,
                                                   absoluteDate: alarm.absoluteDate.map { Dates.iso($0, timezone: timezone) },
                                                   locationBased: alarm.structuredLocation != nil)
                           },
                           revision: event.lastModifiedDate.map { String(format: "%.6f", $0.timeIntervalSince1970) })
    }
}
