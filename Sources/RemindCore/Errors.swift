import Foundation

public enum RemindCoreError: LocalizedError, Sendable, Equatable {
  case accessDenied
  case writeOnlyAccess
  case listNotFound(String)
  case ambiguousList(String, matches: [String])
  case reminderNotFound(String)
  case ambiguousIdentifier(String, matches: [String])
  case invalidIdentifier(String)
  case invalidDate(String)
  case unsupported(String)
  case operationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Reminders access denied. Run applectl auth grant --reminders and allow AppleCtl in System Settings > Privacy & Security > Reminders."
    case .writeOnlyAccess:
      return [
        "Reminders access is write-only.",
        "Switch to Full Access in System Settings > Privacy & Security > Reminders.",
      ].joined(separator: " ")
    case .listNotFound(let name):
      return "List not found: \"\(name)\"."
    case .ambiguousList(let name, let matches):
      return "List \"\(name)\" matches multiple lists: \(matches.joined(separator: ", "))."
    case .reminderNotFound(let id):
      return "Reminder not found: \"\(id)\"."
    case .ambiguousIdentifier(let input, let matches):
      return "Identifier \"\(input)\" matches multiple reminders: \(matches.joined(separator: ", "))."
    case .invalidIdentifier(let input):
      return "Invalid identifier: \"\(input)\"."
    case .invalidDate(let input):
      return "Invalid date: \"\(input)\"."
    case .unsupported(let message):
      return message
    case .operationFailed(let message):
      return message
    }
  }
}
