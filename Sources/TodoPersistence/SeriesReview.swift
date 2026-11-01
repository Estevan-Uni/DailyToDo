import Foundation
import TodoDomain

public enum SeriesChange: Equatable, Sendable {
    case update(selectedID: UUID)
    case detach(selectedID: UUID)
    case stop
}

/// Counts refer to already stored records, never an infinite future series.
/// Revisions make the confirmation a snapshot that can be checked at commit.
public struct SeriesReview: Equatable, Sendable {
    public let seriesID: UUID
    public let from: LocalDate
    public let change: SeriesChange
    public let seriesRevision: Int64
    public let affectedCount: Int
    public let completedCount: Int
    public let exceptions: [OccurrencePreview]
    let taskRevisions: [UUID: Int64]
}

extension TodoRepository {
    public func reviewSeries(id: UUID, from day: LocalDate, change: SeriesChange) throws -> SeriesReview {
        let config = try store.configuration()
        guard day.isUserSelectable, day >= LocalDate(now(), timeZone: timeZone()),
              let root = config.series.first(where: { $0.id == id }) else { throw DomainError.notFound }
        let tasks = try seriesTasks(id)
        let selected: UUID?
        switch change { case .update(let id), .detach(let id): selected = id; case .stop: selected = nil }
        if let selected {
            guard tasks.contains(where: { $0.id == selected && $0.occurrenceDay == day && $0.completedAt == nil && $0.deletedAt == nil && !$0.isRuleSuppressed }) else { throw DomainError.conflict }
        }
        let eligible = tasks.filter { $0.occurrenceDay! >= day && $0.completedAt == nil && $0.deletedAt == nil }
        let exceptions = eligible.filter { $0.isOverride && $0.id != selected }.sorted(by: AgendaCalculator.taskOrder)
        let affected: Int
        switch change {
        case .update: affected = eligible.count - exceptions.count
        case .detach: affected = eligible.filter { $0.id != selected }.count
        case .stop: affected = eligible.count
        }
        return SeriesReview(seriesID: id, from: day, change: change, seriesRevision: root.revision,
            affectedCount: affected, completedCount: tasks.filter { $0.completedAt != nil && $0.deletedAt == nil }.count,
            exceptions: exceptions.map { .init(id: $0.id, title: $0.title, day: $0.scheduledDay, minute: $0.scheduledMinute, originalDay: $0.occurrenceDay!, isOverride: true) },
            taskRevisions: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.revision) }))
    }

    func validateReview(_ review: SeriesReview, id: UUID, from: LocalDate, change: SeriesChange) throws {
        guard review.seriesID == id, review.from == from, review.change == change,
              try reviewSeries(id: id, from: from, change: change) == review else { throw DomainError.conflict }
    }

    /// Read-only real upcoming occurrences, honoring versions, exceptions and
    /// exclusions. At most stored skips plus 3 matches per version are visited.
    public func upcomingSeries(id: UUID, from start: LocalDate, limit: Int = 3) throws -> [OccurrencePreview] {
        guard start.isUserSelectable, (1...20).contains(limit) else { throw DomainError.invalidRange }
        let config = try store.configuration()
        guard let root = config.series.first(where: { $0.id == id }) else { throw DomainError.notFound }
        let versions = config.rules.filter { $0.seriesID == id && !$0.isSupersededForExpansion }.sorted { $0.effectiveFromDay < $1.effectiveFromDay }
        let tasks = try seriesTasks(id)
        let existing = Dictionary(uniqueKeysWithValues: tasks.map { ($0.occurrenceDay!, $0) })
        let excluded = Set(config.exclusions.filter { $0.seriesID == id }.map(\.day))
        var result = tasks.filter {
            $0.isOverride && $0.scheduledDay >= start && $0.completedAt == nil && $0.deletedAt == nil && !$0.isRuleSuppressed &&
            !excluded.contains($0.occurrenceDay!) && (root.stoppedFromDay == nil || $0.occurrenceDay! < root.stoppedFromDay!)
        }.map { OccurrencePreview(id: $0.id, title: $0.title, day: $0.scheduledDay, minute: $0.scheduledMinute, originalDay: $0.occurrenceDay!, isOverride: true) }
        let last = try LocalDate(year: 9999, month: 12, day: 31)
        for (index, rule) in versions.enumerated() {
            if let stop = root.stoppedFromDay, stop <= max(start, rule.effectiveFromDay) { continue }
            var end = min(rule.endDay ?? last, last)
            if index + 1 < versions.count { end = min(end, try versions[index + 1].effectiveFromDay.adding(days: -1)) }
            if let stop = root.stoppedFromDay { end = min(end, try stop.adding(days: -1)) }
            var cursor = max(start, rule.effectiveFromDay), added = 0
            while cursor <= end, added < limit {
                guard let day = try RecurrencePreview.dates(frequency: rule.frequency, weekdays: rule.weekdays, from: cursor, through: end, limit: 1).first else { break }
                if !excluded.contains(day) {
                    if let task = existing[day] {
                        if !task.isOverride, task.completedAt == nil, task.deletedAt == nil, !task.isRuleSuppressed, task.scheduledDay >= start {
                            result.append(.init(id: task.id, title: task.title, day: task.scheduledDay, minute: task.scheduledMinute, originalDay: day, isOverride: false)); added += 1
                        }
                    } else {
                        result.append(.init(id: OccurrenceIdentity.id(seriesID: id, day: day), title: rule.title, day: day, minute: rule.minute, originalDay: day, isOverride: false)); added += 1
                    }
                }
                guard let next = try? day.adding(days: 1), next.isUserSelectable else { break }; cursor = next
            }
        }
        return Array(result.sorted { a, b in a.day != b.day ? a.day < b.day : a.minute != b.minute ? a.minute < b.minute : a.id.uuidString < b.id.uuidString }.prefix(limit))
    }
}
