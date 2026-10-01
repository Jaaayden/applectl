import Foundation

/// EventKit may deliver permission results on any system queue.
/// Only the Sendable result crosses back to the caller's actor.
public enum AuthorizationRequest {
  public typealias Completion = @Sendable (Bool, (any Error)?) -> Void

  public static func perform(
    isolation: isolated (any Actor)? = #isolation,
    start: (@escaping Completion) -> Void
  ) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      start { @Sendable granted, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: granted) }
      }
    }
  }
}
