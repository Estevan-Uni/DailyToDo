import Foundation

public struct AgendaProjection: Sendable {
    public let items: [TodoItem]
    public let missingInstances: [TodoItem]
    public let totalCount: Int
    public let completedCount: Int
}

/// Pure, bounded recurrence projection. Repository callers supply both original-day
/// matches and actual-day overrides; no database or wall-clock reads occur here.
public enum AgendaCalculator {
    public static func rule(for day: LocalDate, seriesID: UUID, rules: [TodoSeriesRule]) -> TodoSeriesRule? {
        rules.filter { $0.seriesID == seriesID && !$0.isSupersededForExpansion && $0.effectiveFromDay <= day }
            .max { $0.effectiveFromDay < $1.effectiveFromDay }
    }

    public static func project(interval: DayInterval, tasks: [TodoItem], series: [TodoSeries], rules: [TodoSeriesRule],
                               exclusions: [TodoOccurrenceExclusion], now: Date, timeZone: TimeZone = .current,
                               includeCompleted: Bool = false) throws -> AgendaProjection {
        guard Set(tasks.map(\.occurrenceKey)).count == tasks.count else { throw DomainError.invalidSnapshot("发生键重复") }
        let existing = Dictionary(uniqueKeysWithValues: tasks.map { ($0.occurrenceKey, $0) })
        let roots = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let excluded = Set(exclusions.map(\.occurrenceKey))
        var generated: [TodoItem] = []
        for day in interval.dates where day.isUserSelectable {
            for root in series {
                guard root.stoppedFromDay == nil || day < root.stoppedFromDay!,
                      let rule = rule(for: day, seriesID: root.id, rules: rules), rule.matches(day) else { continue }
                let key = OccurrenceIdentity.key(seriesID: root.id, day: day)
                guard existing[key] == nil, !excluded.contains(key) else { continue }
                var item = TodoItem(id: OccurrenceIdentity.id(seriesID: root.id, day: day), title: rule.title,
                                    scheduledDay: day, scheduledMinute: rule.minute, categoryID: rule.categoryID)
                item.notes = rule.notes; item.seriesID = root.id; item.ruleVersionID = rule.id; item.occurrenceDay = day
                item.isImportant = rule.isImportant
                item.createdAt = now; item.updatedAt = now
                if let offset = rule.reminderOffsetMinutes {
                    item.reminderAt = try day.instant(minute: rule.minute, timeZone: timeZone).addingTimeInterval(-Double(offset * 60))
                }
                generated.append(item)
            }
        }
        let visibleExisting = tasks.filter { task in
            guard interval.contains(task.scheduledDay), task.deletedAt == nil, !task.isRuleSuppressed else { return false }
            if task.completedAt != nil { return true }
            if let seriesID = task.seriesID, let origin = task.occurrenceDay {
                guard let root = roots[seriesID], root.stoppedFromDay == nil || origin < root.stoppedFromDay! else { return false }
                guard !excluded.contains(task.occurrenceKey) else { return false }
                if !task.isOverride {
                    return rule(for: origin, seriesID: seriesID, rules: rules)?.matches(origin) == true
                }
            }
            return true
        }
        let all = (visibleExisting + generated).sorted(by: taskOrder)
        return AgendaProjection(items: includeCompleted ? all : all.filter { $0.completedAt == nil },
                                missingInstances: generated, totalCount: all.count,
                                completedCount: all.filter { $0.completedAt != nil }.count)
    }

    public static func taskOrder(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.scheduledDay != b.scheduledDay { return a.scheduledDay < b.scheduledDay }
        if a.scheduledMinute != b.scheduledMinute { return a.scheduledMinute < b.scheduledMinute }
        if a.isImportant != b.isImportant { return a.isImportant }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    public static func countdowns(_ events: [CountdownEvent], today: LocalDate, archived: Bool = false) -> [CountdownEvent] {
        events.filter { $0.deletedAt == nil && ($0.archivedAt != nil) == archived }.sorted { a, b in
            let aPast = a.targetDay < today, bPast = b.targetDay < today
            if aPast != bPast { return !aPast }
            if a.targetDay != b.targetDay { return aPast ? a.targetDay > b.targetDay : a.targetDay < b.targetDay }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
