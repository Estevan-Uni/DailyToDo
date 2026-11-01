import Foundation

/// An explicit editor operation, separate from rollover and quick date changes.
/// Preserve the absolute interval between the original local plan and reminder.
public struct ReminderRescheduling: Equatable, Sendable {
    public let day: LocalDate
    public let minute: Int
    public let reminderAt: Date
    public init(day: LocalDate, minute: Int, reminderAt: Date) {
        self.day = day; self.minute = minute; self.reminderAt = reminderAt
    }
    public func proposed(day target: LocalDate, minute targetMinute: Int, timeZone: TimeZone = .current) throws -> Date {
        guard day.isUserSelectable, target.isUserSelectable else { throw DomainError.invalidDate }
        let original = try day.instant(minute: minute, timeZone: timeZone)
        let changed = try target.instant(minute: targetMinute, timeZone: timeZone)
        let result = reminderAt.addingTimeInterval(changed.timeIntervalSince(original))
        guard result.timeIntervalSinceReferenceDate.isFinite, LocalDate(result, timeZone: timeZone).isUserSelectable else { throw DomainError.invalidReminder }
        return result
    }
}
