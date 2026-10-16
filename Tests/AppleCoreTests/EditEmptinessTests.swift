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
}
