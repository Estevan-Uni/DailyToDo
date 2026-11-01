import Foundation
import Testing
@testable import TodoDomain

@Suite struct ReminderReschedulingTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    @Test func explicitShiftPreservesLeadAcrossDaysAndTimeEdits() throws {
        let old = try LocalDate("2026-11-02"), target = try LocalDate("2026-11-05")
        let originalReminder = try old.instant(minute: 8 * 60 + 45, timeZone: utc)
        let plan = ReminderRescheduling(day: old, minute: 9 * 60, reminderAt: originalReminder)
        #expect(try plan.proposed(day: target, minute: 10 * 60, timeZone: utc) == target.instant(minute: 9 * 60 + 45, timeZone: utc))
        #expect(plan.reminderAt == originalReminder)
        #expect(try plan.proposed(day: old, minute: 9 * 60, timeZone: utc) == originalReminder)
    }
    @Test func daylightSavingUsesActualPlanInterval() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let old = try LocalDate("2026-03-07"), target = try LocalDate("2026-03-08")
        let plan = ReminderRescheduling(day: old, minute: 9 * 60, reminderAt: try old.instant(minute: 8 * 60, timeZone: zone))
        let result = try plan.proposed(day: target, minute: 9 * 60, timeZone: zone)
        #expect(result == (try target.instant(minute: 8 * 60, timeZone: zone)))
        #expect(result.timeIntervalSince(plan.reminderAt) == 23 * 3600)
    }
    @Test func rangeAndTimeAreCheckedAndLateRemindersKeepTheirInterval() throws {
        let old = try LocalDate("2026-11-02")
        let plan = ReminderRescheduling(day: old, minute: 9 * 60, reminderAt: try old.instant(minute: 9 * 60 + 10, timeZone: utc))
        #expect(try plan.proposed(day: old, minute: 10 * 60, timeZone: utc) == old.instant(minute: 10 * 60 + 10, timeZone: utc))
        #expect(throws: DomainError.invalidTime) { try plan.proposed(day: old, minute: 1440, timeZone: utc) }
        let last = try LocalDate("9999-12-31")
        #expect(throws: DomainError.invalidReminder) { try plan.proposed(day: last, minute: 1439, timeZone: utc) }
        let exclusive = try LocalDate(year: 10000, month: 1, day: 1)
        #expect(throws: DomainError.invalidDate) { try plan.proposed(day: exclusive, minute: 1, timeZone: utc) }
    }
}
