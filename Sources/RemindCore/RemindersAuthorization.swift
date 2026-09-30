import EventKit
import Foundation

public enum RemindersAuthorizationStatus: String, Codable, Sendable, Equatable {
  case notDetermined = "not-determined"
  case restricted = "restricted"
  case denied = "denied"
  case writeOnly = "write-only"
  case fullAccess = "full-access"

  public init(eventKitStatus: EKAuthorizationStatus) {
    switch eventKitStatus {
    case .notDetermined:
      self = .notDetermined
    case .restricted:
      self = .restricted
    case .denied:
      self = .denied
    case .writeOnly:
      self = .writeOnly
    case .fullAccess, .authorized:
      self = .fullAccess
    @unknown default:
      self = .denied
    }
  }

  public var isAuthorized: Bool {
    self == .fullAccess
  }

  public var displayName: String {
    switch self {
    case .notDetermined:
      return "Not determined"
    case .restricted:
      return "Restricted"
    case .denied:
      return "Denied"
    case .writeOnly:
      return "Write-only"
    case .fullAccess:
      return "Full access"
    }
  }
}
