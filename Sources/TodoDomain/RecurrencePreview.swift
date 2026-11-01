import Foundation

/// Date-only preview; jumps across gaps instead of expanding intervening years.
public enum RecurrencePreview {
    public static func dates(frequency: RepeatFrequency, weekdays: Set<Int>, from start: LocalDate,
                             through end: LocalDate? = nil, limit: Int = 3) throws -> [LocalDate] {
        guard start.isUserSelectable, end?.isUserSelectable != false, end == nil || end! >= start,
              weekdays.isSubset(of: Set(1...7)), frequency != .weekly || !weekdays.isEmpty,
              (1...20).contains(limit) else { throw DomainError.invalidRecurrence }
        var cursor = start, result: [LocalDate] = []
        while result.count < limit {
            let offset = frequency == .daily ? 0 : weekdays.map { ($0 - cursor.weekday + 7) % 7 }.min()!
            guard let day = try? cursor.adding(days: offset), day.isUserSelectable, end == nil || day <= end! else { break }
            result.append(day)
            guard let next = try? day.adding(days: 1), next.isUserSelectable else { break }
            cursor = next
        }
        return result
    }
    public static func summary(frequency: RepeatFrequency, weekdays: Set<Int>, minute: Int, category: String) -> String {
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        let days = weekdays.filter { (1...7).contains($0) }.sorted().map { names[$0 - 1] }.joined(separator: "、")
        return "\(frequency == .daily ? "每日" : "每周" + days) \(String(format: "%02d:%02d", minute / 60, minute % 60)) · \(category)"
    }
}

public struct OccurrencePreview: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let day: LocalDate
    public let minute: Int
    public let originalDay: LocalDate
    public let isOverride: Bool
    public var timeLabel: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public init(id: UUID, title: String, day: LocalDate, minute: Int, originalDay: LocalDate, isOverride: Bool) {
        self.id = id; self.title = title; self.day = day; self.minute = minute; self.originalDay = originalDay; self.isOverride = isOverride
    }
}

extension TaskDraft {
    /// Saving this unsaved draft creates a new series through the ordinary path.
    /// A previous end/stop date is deliberately not reused for the new series.
    public init(copying rule: TodoSeriesRule, starting day: LocalDate) {
        self.init(day: day)
        title = rule.title; notes = rule.notes; minute = rule.minute; categoryID = rule.categoryID
        isImportant = rule.isImportant; frequency = rule.frequency; weekdays = rule.weekdays
        reminderOffsetMinutes = rule.reminderOffsetMinutes
    }
}
