import Foundation

public enum EditScope: String, CaseIterable, Sendable { case onlyThis, thisAndFollowing }
public enum TaskQuickChange: Sendable {
    case moveToTomorrow
    case setImportant(Bool)
}

public struct TaskDraft: Equatable, Sendable {
    public var id = UUID()
    public var baseRevision: Int64 = 0
    public var title = ""
    public var notes = ""
    public var day: LocalDate
    public var minute: Int?
    public var categoryID: UUID?
    public var isImportant = false
    public var reminderAt: Date?
    public var frequency: RepeatFrequency?
    public var weekdays: Set<Int> = []
    public var endDay: LocalDate?
    public var reminderOffsetMinutes: Int?
    public var scope: EditScope = .onlyThis
    public var seriesRevision: Int64?
    public var effectiveFromDay: LocalDate?

    public init(day: LocalDate) { self.day = day }
    public init(task: TodoItem, rule: TodoSeriesRule? = nil, series: TodoSeries? = nil) {
        id = task.id; baseRevision = task.revision; title = task.title; notes = task.notes
        day = task.scheduledDay; minute = task.hasScheduledTime ? task.scheduledMinute : nil; categoryID = task.categoryID
        isImportant = task.isImportant; reminderAt = task.reminderAt
        frequency = rule?.frequency; weekdays = rule?.weekdays ?? []
        endDay = rule?.endDay; reminderOffsetMinutes = rule?.reminderOffsetMinutes
        seriesRevision = series?.revision; effectiveFromDay = task.occurrenceDay
    }
}

public struct CountdownDraft: Equatable, Sendable {
    public var id = UUID()
    public var baseRevision: Int64 = 0
    public var title = ""
    public var notes = ""
    public var day: LocalDate
    public var reminderAt: Date?
    public init(day: LocalDate) { self.day = day }
    public init(event: CountdownEvent) {
        id = event.id; baseRevision = event.revision; title = event.title; notes = event.notes
        day = event.targetDay; reminderAt = event.reminderAt
    }
}

public struct RecordCursor: Equatable, Sendable {
    public let timestamp: Date
    public let id: UUID
    public init(timestamp: Date, id: UUID) { self.timestamp = timestamp; self.id = id }
}

public struct RecordPage<T: Sendable>: Sendable {
    public let items: [T]
    public let nextCursor: RecordCursor?
    public init(items: [T], nextCursor: RecordCursor?) { self.items = items; self.nextCursor = nextCursor }
}
