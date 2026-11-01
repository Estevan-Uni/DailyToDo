import Foundation

/// Time status is a projection, never a persisted field or an automatic reminder.
public enum AgendaClock {
    public static func hasPassed(_ item: TodoItem, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard item.completedAt == nil, item.deletedAt == nil, !item.isRuleSuppressed,
              item.scheduledDay == LocalDate(now, timeZone: timeZone),
              let instant = try? item.scheduledDay.instant(minute: item.scheduledMinute, timeZone: timeZone) else { return false }
        return instant <= now
    }
    public static func nextChange(items: [TodoItem], now: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let today = LocalDate(now, timeZone: timeZone)
        return items.lazy.filter { $0.scheduledDay == today && $0.completedAt == nil && $0.deletedAt == nil && !$0.isRuleSuppressed }
            .compactMap { try? $0.scheduledDay.instant(minute: $0.scheduledMinute, timeZone: timeZone) }
            .filter { $0 > now }.min().map { min($0, midnight) } ?? midnight
    }
}
