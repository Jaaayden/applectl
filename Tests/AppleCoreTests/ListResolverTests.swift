import Testing

@testable import RemindCore

struct ListResolverTests {
  @Test("List resolver matches exact, case-insensitive, normalized names, and ID prefixes")
  func resolvesListTargets() throws {
    let lists = [
      ReminderList(id: "AAAA-1111", title: "Work"),
      ReminderList(id: "BBBB-2222", title: "🗓️ Weekly 513"),
    ]

    #expect(try ListResolver.resolve("Work", in: lists).id == "AAAA-1111")
    #expect(try ListResolver.resolve("work", in: lists).id == "AAAA-1111")
    #expect(try ListResolver.resolve("Weekly 513", in: lists).id == "BBBB-2222")
    #expect(try ListResolver.resolveID("BBBB", in: lists).title == "🗓️ Weekly 513")
  }

  @Test("List resolver rejects ambiguous normalized names")
  func rejectsAmbiguousNames() {
    let lists = [
      ReminderList(id: "AAAA-1111", title: "Weekly 513"),
      ReminderList(id: "BBBB-2222", title: "🗓️ Weekly 513"),
    ]

    #expect(throws: RemindCoreError.self) {
      _ = try ListResolver.resolve("Weekly513", in: lists)
    }
  }

  @Test("List resolver rejects duplicate exact names for mutation targets")
  func rejectsDuplicateExactNames() throws {
    let lists = [
      ReminderList(id: "AAAA-1111", title: "Work"),
      ReminderList(id: "BBBB-2222", title: "Work"),
    ]

    #expect(throws: RemindCoreError.self) {
      _ = try ListResolver.resolve("Work", in: lists)
    }
    #expect(try ListResolver.resolveForRead("Work", in: lists).map(\.id) == ["AAAA-1111", "BBBB-2222"])
  }

  @Test("List resolver does not fuzzy match empty normalized names")
  func rejectsEmptyNormalizedFuzzyMatch() throws {
    let lists = [
      ReminderList(id: "AAAA-1111", title: "🛒")
    ]

    #expect(try ListResolver.resolve("🛒", in: lists).id == "AAAA-1111")
    #expect(throws: RemindCoreError.self) {
      _ = try ListResolver.resolve("!!!", in: lists)
    }
  }
}
