import Dispatch
import Testing
@testable import RemindCore

private enum PermissionFailure: Error { case unavailable }

private actor PermissionCaller {
  func authorize() async throws -> Bool {
    try await AuthorizationRequest.perform { completion in
      DispatchQueue.global().async { completion(true, nil) }
    }
  }
}

struct AuthorizationRequestTests {
  @Test("Background permission completion resumes a MainActor caller")
  @MainActor
  func backgroundCompletionFromMainActor() async throws {
    let granted = try await AuthorizationRequest.perform { completion in
      DispatchQueue.global().async { completion(true, nil) }
    }
    MainActor.assertIsolated()
    #expect(granted)
  }

  @Test("Background permission completion resumes a non-main actor caller")
  func backgroundCompletionFromActor() async throws {
    #expect(try await PermissionCaller().authorize())
  }

  @Test("Permission refusal returns false rather than success")
  @MainActor
  func deniedPermission() async throws {
    let granted = try await AuthorizationRequest.perform { completion in
      DispatchQueue.global().async { completion(false, nil) }
    }
    #expect(!granted)
  }

  @Test("Permission errors cross the background callback")
  @MainActor
  func permissionError() async {
    await #expect(throws: PermissionFailure.unavailable) {
      try await AuthorizationRequest.perform { completion in
        DispatchQueue.global().async { completion(false, PermissionFailure.unavailable) }
      }
    }
  }
}
