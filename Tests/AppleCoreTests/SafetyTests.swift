@testable import AppleCore
import Foundation
import RemindCore
import XCTest

final class SafetyTests: XCTestCase {
    func testDateOnlyDoesNotShiftInNegativeTimezone() throws {
        let calendar = try Dates.calendar(timezone: "America/New_York")
        let value = try Dates.parse("2026-10-01", calendar: calendar)
        XCTAssertTrue(value.isDateOnly)
        XCTAssertEqual(calendar.component(.day, from: value.date), 1)
        XCTAssertEqual(calendar.component(.hour, from: value.date), 0)
        XCTAssertTrue(Dates.iso(value.date, timezone: calendar.timeZone).hasPrefix("2026-10-01T00:00:00"))
    }

    func testDateOnlyDSTAndShanghaiUseRequestedTimezone() throws {
        for zone in ["Asia/Shanghai", "Europe/Berlin", "America/Los_Angeles"] {
            let calendar = try Dates.calendar(timezone: zone)
            let value = try Dates.parse("2026-03-29", calendar: calendar)
            XCTAssertEqual(calendar.component(.day, from: value.date), 29)
            XCTAssertEqual(calendar.component(.hour, from: value.date), 0)
        }
    }

    func testOffsetTakesPrecedenceOverDefaultTimezone() throws {
        let calendar = try Dates.calendar(timezone: "America/New_York")
        let value = try Dates.parse("2026-10-01T09:00:00+08:00", calendar: calendar)
        XCTAssertEqual(Dates.iso(value.date, timezone: TimeZone(secondsFromGMT: 0)!), "2026-10-01T01:00:00.000Z")
    }

    func testRejectsInvalidCalendarDatesAndTrailingData() throws {
        let calendar = try Dates.calendar(timezone: "Asia/Shanghai")
        for value in ["2026-02-30", "2026-13-01", "2026-10-01 garbage", "2026-10-01T25:00:00", "10/01/2026"] {
            XCTAssertThrowsError(try Dates.parse(value, calendar: calendar), value)
        }
    }

    func testRejectsReverseAndUnboundedRanges() throws {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertThrowsError(try Dates.validateRange(start: start, end: start))
        XCTAssertThrowsError(try Dates.validateRange(start: start, end: start.addingTimeInterval(-1)))
        XCTAssertThrowsError(try Dates.queryRange(start: start, end: start.addingTimeInterval(367 * 86400)))
    }

    func testDifferentOccurrencesAndCalendarsStayDistinct() {
        let start = Date(timeIntervalSince1970: 0)
        let first = OccurrenceKey(calendar: "a", id: "series", start: start)
        let second = OccurrenceKey(calendar: "a", id: "series", start: start.addingTimeInterval(86400))
        let otherCalendar = OccurrenceKey(calendar: "b", id: "series", start: start)
        XCTAssertEqual(Set([first, first, second, otherCalendar]).count, 3)
    }

    func testRecurringMutationsRequireOccurrenceForThisAndFuture() throws {
        for scope in [EventScope.this, .future] {
            XCTAssertThrowsError(try RecurrenceSafety.validate(recurring: true, scope: scope, occurrence: nil))
            XCTAssertNoThrow(try RecurrenceSafety.validate(recurring: true, scope: scope, occurrence: Date()))
        }
        XCTAssertNoThrow(try RecurrenceSafety.validate(recurring: true, scope: .all, occurrence: nil))
        XCTAssertThrowsError(try RecurrenceSafety.validate(recurring: true, scope: .all, occurrence: Date()))
    }

    func testRejectsUnknownDuplicateMissingAndConflictingOptions() throws {
        XCTAssertThrowsError(try Options(["--force"], values: ["id"]))
        XCTAssertThrowsError(try Options(["--id", "a", "--id", "b"], values: ["id"]))
        XCTAssertThrowsError(try Options(["--id"], values: ["id"]))
        let options = try Options(["--due", "2026-10-01", "--clear-due"], values: ["due"], flags: ["clear-due"])
        XCTAssertThrowsError(try options.exclusive("due", "clear-due"))
        let negative = try Options(["--alarm-minutes", "-15"], values: ["alarm-minutes"])
        XCTAssertEqual(try negative.integer("alarm-minutes"), -15)
    }

    func testOverdueIncludesTimedReminderEarlierTodayButNotTodaysAllDayReminder() throws {
        let calendar = try Dates.calendar(timezone: "Asia/Shanghai")
        let now = try Dates.parse("2026-10-01T12:00:00+08:00", calendar: calendar).date
        let timed = reminder(id: "timed", due: now.addingTimeInterval(-3600), allDay: false)
        let allDay = reminder(id: "all-day", due: calendar.startOfDay(for: now), allDay: true)
        let future = reminder(id: "future", due: now.addingTimeInterval(3600), allDay: false)
        XCTAssertEqual(ReminderFiltering.apply([timed, allDay, future], filter: .overdue, now: now, calendar: calendar).map(\.id), ["timed"])
    }

    private func reminder(id: String, due: Date, allDay: Bool) -> ReminderItem {
        ReminderItem(id: id, title: id, notes: nil, isCompleted: false, completionDate: nil, priority: .none,
                     dueDate: due, dueDateIsAllDay: allDay, listID: "list", listName: "List")
    }

    @MainActor
    func testMalformedMutationsFailBeforePermissionAndReturnStructuredErrors() async throws {
        let cases = [
            ["events", "add", "--title", "Test", "--start", "2026-10-01", "--end", "2026-09-30"],
            ["reminders", "add", "--title", "Test", "--due", "2026-02-30"],
            ["reminders", "edit", "--id", "test", "--title", " ", "--dry-run"],
            ["events", "delete", "--id", "test"],
            ["reminders", "delete", "--id", "test"],
            ["calendars", "delete", "--id", "test"],
        ]
        for arguments in cases {
            let response = await Runner().run(arguments)
            XCTAssertFalse(response.ok)
            XCTAssertNotNil(response.error?["code"])
            XCTAssertNotEqual(response.error?["code"], "permission_denied")
            XCTAssertEqual(response.meta.exitCode, 1)
            XCTAssertNoThrow(try JSONDecoder().decode(Response.self, from: response.encoded()))
        }
    }
}
