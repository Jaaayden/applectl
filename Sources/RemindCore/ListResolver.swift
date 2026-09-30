import Foundation

public enum ListResolver {
  public static func normalizedName(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .unicodeScalars
      .filter { scalar in
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
          return true
        default:
          return false
        }
      }
      .map(String.init)
      .joined()
      .lowercased()
  }

  public static func resolve(_ name: String, in lists: [ReminderList]) throws -> ReminderList {
    let exactMatches = lists.filter { $0.title == name }
    if exactMatches.count == 1, let match = exactMatches.first {
      return match
    }
    if exactMatches.count > 1 {
      throw RemindCoreError.ambiguousList(name, matches: exactMatches.map(summary))
    }

    let caseMatches = lists.filter { $0.title.compare(name, options: [.caseInsensitive]) == .orderedSame }
    if caseMatches.count == 1, let match = caseMatches.first {
      return match
    }
    if caseMatches.count > 1 {
      throw RemindCoreError.ambiguousList(name, matches: caseMatches.map(summary))
    }

    let normalized = normalizedName(name)
    guard !normalized.isEmpty else {
      throw RemindCoreError.listNotFound(name)
    }
    let normalizedMatches = lists.filter {
      let title = normalizedName($0.title)
      return !title.isEmpty && title == normalized
    }
    if normalizedMatches.count == 1, let match = normalizedMatches.first {
      return match
    }
    if normalizedMatches.count > 1 {
      throw RemindCoreError.ambiguousList(name, matches: normalizedMatches.map(summary))
    }

    throw RemindCoreError.listNotFound(name)
  }

  public static func resolveForRead(_ name: String, in lists: [ReminderList]) throws -> [ReminderList] {
    let exactMatches = lists.filter { $0.title == name }
    if !exactMatches.isEmpty {
      return exactMatches
    }

    return [try resolve(name, in: lists)]
  }

  public static func resolveID(_ id: String, in lists: [ReminderList]) throws -> ReminderList {
    let matches = lists.filter { $0.id.lowercased().hasPrefix(id.lowercased()) }
    if matches.count == 1, let match = matches.first {
      return match
    }
    if matches.count > 1 {
      throw RemindCoreError.ambiguousList(id, matches: matches.map(summary))
    }
    throw RemindCoreError.listNotFound(id)
  }

  private static func summary(_ list: ReminderList) -> String {
    "\(list.title) (\(list.id))"
  }
}
