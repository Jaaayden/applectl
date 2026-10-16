@testable import AppleCore
import Foundation
import RemindCore
import XCTest

final class EditEmptinessTests: XCTestCase {
    func testEmptyEventChangesAreDetected() {
        XCTAssertTrue(EventChanges().isEmpty)
        var changes = EventChanges(); changes.clearAlarms = true
        XCTAssertFalse(changes.isEmpty)
        changes = EventChanges(); changes.title = "x"
        XCTAssertFalse(changes.isEmpty)
        changes = EventChanges(); changes.allDay = false
        XCTAssertFalse(changes.isEmpty)
    }

    func testEmptyReminderUpdateIsDetected() {
        XCTAssertTrue(ReminderUpdate().isEmpty)
        XCTAssertFalse(ReminderUpdate(title: "x").isEmpty)
        XCTAssertFalse(ReminderUpdate(dueDate: .some(nil)).isEmpty, "clearing the due date is a change")
        XCTAssertFalse(ReminderUpdate(url: .some(nil)).isEmpty)
        XCTAssertFalse(ReminderUpdate(isCompleted: false).isEmpty)
    }

    @MainActor
    func testGroupHelpIsScopedAndSafe() async throws {
        let response = await Runner().run(["events", "--help"])
        XCTAssertTrue(response.ok)
        guard case .object(let data)? = response.data, case .string(let text)? = data["help"] else { return XCTFail("missing help") }
        XCTAssertTrue(text.contains("applectl events add"))
        XCTAssertFalse(text.contains("applectl reminders add"))
    }

    func testFloatingDatesKeepTheRequestedDayInAnyMacZone() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let requested = try Dates.parse("2027-11-01", calendar: Dates.calendar(timezone: "America/New_York")).date
        for mac in [newYork, shanghai, losAngeles] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = mac
            let stored = Dates.floating(requested, from: newYork, into: mac)
            XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: stored),
                           DateComponents(year: 2027, month: 11, day: 1, hour: 0), "Mac zone \(mac.identifier)")
        }
    }
}
