@testable import AppleCore
import Foundation
import XCTest

final class ArgumentTests: XCTestCase {
    func testInlineAndSeparateValuesAreEquivalent() throws {
        let spaced = try Options(["--title", "Plan", "--force"], values: ["title"], flags: ["force"])
        let inline = try Options(["--title=Plan", "--force"], values: ["title"], flags: ["force"])
        XCTAssertEqual(spaced.value("title"), inline.value("title"))
        XCTAssertTrue(inline.flag("force"))
    }

    func testInlineValueMayContainEqualsAndLeadingDashes() throws {
        let options = try Options(["--notes=a=b", "--title=--odd"], values: ["notes", "title"])
        XCTAssertEqual(options.value("notes"), "a=b")
        XCTAssertEqual(options.value("title"), "--odd")
    }

    func testInlineFlagsUnknownAndDuplicateOptionsAreRejected() {
        XCTAssertThrowsError(try Options(["--force=yes"], flags: ["force"]))
        XCTAssertThrowsError(try Options(["--nope=1"], values: ["title"]))
        XCTAssertThrowsError(try Options(["--title=a", "--title", "b"], values: ["title"]))
        XCTAssertThrowsError(try Options(["--title"], values: ["title"]))
    }

    func testEmptyInlineValueIsRejectedWhenRequired() throws {
        let options = try Options(["--title="], values: ["title"])
        XCTAssertThrowsError(try options.require("title"))
    }

    func testFailuresCarryActionableHints() {
        let denied = Response.failure(ToolError("permission_denied", "x"), command: "events list")
        XCTAssertTrue(denied.error?["hint"]?.contains("auth grant") == true)
        let unknown = Response.failure(ToolError("not_found", "x"), command: "events get")
        XCTAssertNil(unknown.error?["hint"])
    }

    @MainActor
    func testGroupWithoutCommandExplainsUsage() async {
        let response = await Runner().run(["reminders"])
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?["code"], "invalid_arguments")
        XCTAssertTrue(response.error?["message"]?.contains("applectl reminders add") == true)
        XCTAssertFalse(response.error?["message"]?.contains("applectl events") == true)
    }
}
