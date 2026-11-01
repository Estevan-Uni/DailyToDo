import Foundation
import TodoDomain

public struct UndoAction: Sendable, Identifiable {
    public let id = UUID()
    public let title: String
    var tasks: [TodoItem] = []
    var series: [TodoSeries] = []
    var countdowns: [CountdownEvent] = []
    var expectations: [RevisionExpectation] = []
    var removeExclusions: Set<UUID> = []
    var restoreExclusions: [TodoOccurrenceExclusion] = []

    /// Call only after `undone` committed successfully. The restored contents
    /// have a newer revision; older local undo entries can follow that exact
    /// revision chain without weakening protection against unrelated writes.
    public func rebased(after undone: UndoAction) -> UndoAction {
        var result = self
        for index in result.expectations.indices {
            let expected = result.expectations[index]
            let oldRevision: Int64?
            switch expected.entity {
            case .task: oldRevision = undone.tasks.first { $0.id == expected.id }?.revision
            case .series: oldRevision = undone.series.first { $0.id == expected.id }?.revision
            case .countdown: oldRevision = undone.countdowns.first { $0.id == expected.id }?.revision
            default: oldRevision = nil
            }
            if oldRevision == expected.revision,
               let committed = undone.expectations.first(where: { $0.entity == expected.entity && $0.id == expected.id }) {
                result.expectations[index] = .init(entity: expected.entity, id: expected.id, revision: committed.revision + 1)
            }
        }
        return result
    }
}

public struct TaskSaveResult: Sendable {
    public let task: TodoItem
    public let undo: UndoAction?
}
public struct CountdownSaveResult: Sendable {
    public let event: CountdownEvent
    public let undo: UndoAction?
}

/// One repository owns all command writes for the app. No await occurs between
/// reading a revision and committing its changes, so commands cannot interleave.
public actor TodoRepository {
    let store: SQLiteStore
    let now: @Sendable () -> Date
    let timeZone: @Sendable () -> TimeZone

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() },
                timeZone: @escaping @Sendable () -> TimeZone = { .current }) throws {
        store = try SQLiteStore(url: url); self.now = now; self.timeZone = timeZone
    }

    public func configuration() throws -> StoreSnapshot { try store.configuration() }
    public func task(id: UUID) throws -> TodoItem? { try store.task(id: id) }
    public func countdown(id: UUID) throws -> CountdownEvent? {
        let values: [CountdownEvent] = try store.records(.countdown, matching: "id == %@", values: [.uuid(id)])
        return values.first
    }
    public func close() throws { try store.close() }

    /// Startup/day-boundary maintenance. Recurring occurrences keep their own day;
    /// a missed one-off advances directly to today after several days offline.
    /// Stable ID, wall time and explicit absolute reminder are preserved.
    @discardableResult
    public func rolloverUnfinishedSingles() throws -> Int {
        let clock = now()
        let today = LocalDate(clock, timeZone: timeZone())
        let overdue: [TodoItem] = try store.records(.task,
            matching: "seriesID == nil AND completedAt == nil AND deletedAt == nil AND isRuleSuppressed == NO AND scheduledDay < %@",
            values: [.text(today.description)])
        guard !overdue.isEmpty else { return 0 }
        var changes = StoreChanges()
        changes.tasks = overdue.map { original in
            var task = original; task.scheduledDay = today; task.updatedAt = clock; task.revision += 1; return task
        }
        changes.expectations = overdue.map { .init(entity: .task, id: $0.id, revision: $0.revision) }
        try store.commit(changes)
        return overdue.count
    }

    public func agenda(_ interval: DayInterval, includeCompleted: Bool = false) throws -> AgendaProjection {
        let data = try store.agendaInput(in: interval)
        let result = try AgendaCalculator.project(interval: interval, tasks: data.tasks, series: data.series,
            rules: data.rules, exclusions: data.exclusions, now: now(), timeZone: timeZone(), includeCompleted: includeCompleted)
        if !result.missingInstances.isEmpty {
            var changes = StoreChanges(); changes.tasks = result.missingInstances
            changes.expectations = result.missingInstances.map { .init(entity: .task, id: $0.id, revision: 0) }
            try store.commit(changes)
        }
        return result
    }

    public func saveTask(_ draft: TaskDraft, reviewed: SeriesReview? = nil) throws -> TaskSaveResult {
        let config = try store.configuration()
        let clock = now(), today = LocalDate(clock, timeZone: timeZone())
        let previous = try store.task(id: draft.id)
        if draft.baseRevision > 0 && previous == nil { throw DomainError.notFound }
        guard (draft.baseRevision == 0 && previous == nil) || previous?.revision == draft.baseRevision else { throw DomainError.conflict }
        guard previous?.deletedAt == nil, previous?.isRuleSuppressed != true else { throw DomainError.notFound }
        if let reviewed {
            guard draft.scope == .thisAndFollowing, let original = previous, let id = original.seriesID, let day = original.occurrenceDay else { throw DomainError.conflict }
            try validateReview(reviewed, id: id, from: day, change: draft.frequency == nil ? .detach(selectedID: original.id) : .update(selectedID: original.id))
        }
        guard let minute = draft.minute, (0..<1440).contains(minute) else { throw DomainError.invalidTime }
        guard let categoryID = draft.categoryID, config.categories.contains(where: { $0.id == categoryID }) else { throw DomainError.missingCategory }
        try ModelValidator.title(draft.title, notes: draft.notes)
        guard draft.day.isUserSelectable else { throw DomainError.invalidDate }
        if let reminder = draft.reminderAt, reminder != previous?.reminderAt, reminder <= clock { throw DomainError.invalidReminder }
        var item = previous ?? TodoItem(id: draft.id, title: draft.title, scheduledDay: draft.day, scheduledMinute: minute, categoryID: categoryID)
        if previous == nil { item.createdAt = clock }
        item.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = draft.notes; item.scheduledDay = draft.day; item.scheduledMinute = minute
        item.categoryID = categoryID; item.isImportant = draft.isImportant; item.reminderAt = draft.reminderAt
        item.updatedAt = clock; item.revision = (previous?.revision ?? 0) + 1
        var changes = StoreChanges()
        changes.expectations = [.init(entity: .task, id: item.id, revision: draft.baseRevision)]
        var undo: UndoAction?

        if let original = previous, let seriesID = original.seriesID, let origin = original.occurrenceDay {
            if draft.scope == .onlyThis || original.completedAt != nil {
                item.isOverride = true
                undo = taskUndo(original, result: item, config: config, title: "编辑待办")
                changes.tasks = [item]
            } else {
                guard let root = config.series.first(where: { $0.id == seriesID }), draft.seriesRevision == root.revision else { throw DomainError.conflict }
                let cut = draft.effectiveFromDay ?? origin
                guard cut >= today, cut == origin else { throw DomainError.invalidRecurrence }
                if let frequency = draft.frequency {
                    let rule = try makeRule(draft, seriesID: seriesID, from: cut, frequency: frequency, categories: config.categories)
                    changes.rules = config.rules.filter { $0.seriesID == seriesID && !$0.isSupersededForExpansion && $0.effectiveFromDay >= cut }.map { old in
                        var value = old; value.isSupersededForExpansion = true; return value
                    } + [rule]
                    var revisedRoot = root; revisedRoot.revision += 1; revisedRoot.updatedAt = clock
                    guard root.stoppedFromDay == nil || cut < root.stoppedFromDay! else { throw DomainError.invalidRecurrence }
                    changes.series = [revisedRoot]
                    changes.expectations.append(.init(entity: .series, id: root.id, revision: root.revision))
                    let affected = try seriesTasks(seriesID)
                    for current in affected where current.occurrenceDay! >= cut && current.completedAt == nil && current.deletedAt == nil {
                        if current.isOverride && current.id != original.id { continue }
                        var updated = current
                        if rule.matches(current.occurrenceDay!) {
                            try apply(rule, to: &updated, day: current.occurrenceDay!, clock: clock)
                        } else {
                            updated.isRuleSuppressed = true; updated.revision += 1; updated.updatedAt = clock
                        }
                        changes.tasks.append(updated)
                    }
                    if let updated = changes.tasks.first(where: { $0.id == original.id }) { item = updated }
                } else {
                    // Detach this item, exclude the old occurrence, and stop the old series.
                    item.seriesID = nil; item.ruleVersionID = nil; item.occurrenceDay = nil; item.isOverride = false
                    item.isRuleSuppressed = false
                    changes.tasks = [item]
                    changes.exclusions = [exclusion(seriesID, origin, .detached, config: config)]
                    var stopped = root; stopped.stoppedFromDay = cut; stopped.revision += 1; stopped.updatedAt = clock
                    changes.series = [stopped]
                    changes.expectations.append(.init(entity: .series, id: root.id, revision: root.revision))
                    for current in try seriesTasks(seriesID) where current.id != item.id && current.occurrenceDay! >= cut && current.completedAt == nil && current.deletedAt == nil {
                        var updated = current; updated.isRuleSuppressed = true; updated.updatedAt = clock; updated.revision += 1
                        changes.tasks.append(updated)
                    }
                }
            }
        } else if let frequency = draft.frequency {
            guard item.completedAt == nil, draft.day >= today else { throw DomainError.invalidRecurrence }
            var root = TodoSeries(); root.createdAt = clock; root.updatedAt = clock
            let rule = try makeRule(draft, seriesID: root.id, from: draft.day, frequency: frequency, categories: config.categories)
            var firstDay: LocalDate?
            for offset in 0...6 {
                guard let candidate = try? draft.day.adding(days: offset), candidate.isUserSelectable else { break }
                if rule.matches(candidate) { firstDay = candidate; break }
            }
            guard let firstDay else { throw DomainError.invalidRecurrence }
            item.seriesID = root.id; item.ruleVersionID = rule.id; item.occurrenceDay = firstDay
            item.scheduledDay = firstDay; item.isOverride = false
            if let offset = rule.reminderOffsetMinutes { item.reminderAt = try firstDay.instant(minute: rule.minute, timeZone: timeZone()).addingTimeInterval(-Double(offset * 60)) }
            changes.series = [root]; changes.rules = [rule]; changes.tasks = [item]
        } else {
            changes.tasks = [item]
            if let previous { undo = taskUndo(previous, result: item, config: config, title: "编辑待办") }
        }
        try store.commit(changes)
        return TaskSaveResult(task: item, undo: undo)
    }

    /// Field-level shortcuts always affect one occurrence and share the same
    /// validation, revision protection and undo semantics as the full editor.
    public func quickEditTask(id: UUID, baseRevision: Int64, change: TaskQuickChange) throws -> TaskSaveResult {
        guard let item = try store.task(id: id), item.deletedAt == nil, !item.isRuleSuppressed else { throw DomainError.notFound }
        guard item.revision == baseRevision else { throw DomainError.conflict }
        var draft = TaskDraft(task: item)
        switch change {
        case .moveToTomorrow:
            draft.day = try LocalDate(now(), timeZone: timeZone()).adding(days: 1)
            guard draft.day.isUserSelectable else { throw DomainError.invalidDate }
        case .setImportant(let value): draft.isImportant = value
        }
        if draft.day == item.scheduledDay, draft.isImportant == item.isImportant { return TaskSaveResult(task: item, undo: nil) }
        return try saveTask(draft)
    }

    public func setCompletion(id: UUID, completed: Bool) throws -> UndoAction? {
        guard let original = try store.task(id: id), original.deletedAt == nil, !original.isRuleSuppressed else { throw DomainError.notFound }
        if (original.completedAt != nil) == completed { return nil }
        let config = try store.configuration()
        var item = original
        item.completedAt = completed ? now() : nil; item.revision += 1; item.updatedAt = now()
        var changes = StoreChanges()
        var action = taskUndo(original, result: item, config: config, title: completed ? "完成待办" : "取消完成")
        if !completed, let seriesID = original.seriesID, let origin = original.occurrenceDay,
           !isScheduled(seriesID, origin, config: config) {
            let marker = exclusion(seriesID, origin, .detached, config: config)
            changes.exclusions = [marker]
            if !config.exclusions.contains(where: { $0.id == marker.id }) { action.removeExclusions.insert(marker.id) }
            item.seriesID = nil; item.ruleVersionID = nil; item.occurrenceDay = nil; item.isOverride = false
        }
        item.isRuleSuppressed = false
        changes.tasks = [item]; changes.expectations = [.init(entity: .task, id: id, revision: original.revision)]
        try store.commit(changes)
        return action
    }

    public func deleteTask(id: UUID) throws -> UndoAction {
        guard let original = try store.task(id: id), original.deletedAt == nil else { throw DomainError.notFound }
        let config = try store.configuration()
        var item = original; item.deletedAt = now(); item.updatedAt = now(); item.revision += 1
        var changes = StoreChanges(); changes.tasks = [item]
        changes.expectations = [.init(entity: .task, id: id, revision: original.revision)]
        var action = taskUndo(original, result: item, config: config, title: "删除待办")
        if let seriesID = item.seriesID, let origin = item.occurrenceDay {
            let marker = exclusion(seriesID, origin, .userDeleted, config: config)
            changes.exclusions = [marker]
            if let old = config.exclusions.first(where: { $0.id == marker.id }) { action.restoreExclusions = [old] }
            else { action.removeExclusions.insert(marker.id) }
        }
        try store.commit(changes)
        return action
    }

    public func stopSeries(id: UUID, from day: LocalDate, baseRevision: Int64, reviewed: SeriesReview? = nil) throws -> UndoAction {
        let config = try store.configuration()
        guard let root = config.series.first(where: { $0.id == id }) else { throw DomainError.notFound }
        guard day >= LocalDate(now(), timeZone: timeZone()), root.revision == baseRevision else { throw DomainError.conflict }
        if let reviewed { try validateReview(reviewed, id: id, from: day, change: .stop) }
        var stopped = root; stopped.stoppedFromDay = min(root.stoppedFromDay ?? day, day)
        stopped.revision += 1; stopped.updatedAt = now()
        var changes = StoreChanges(); changes.series = [stopped]
        changes.expectations = [.init(entity: .series, id: id, revision: root.revision)]
        var action = UndoAction(title: "停止固定待办")
        action.series = [root]; action.expectations = [.init(entity: .series, id: id, revision: stopped.revision)]
        for old in try seriesTasks(id) where old.occurrenceDay! >= day && old.completedAt == nil && old.deletedAt == nil {
            var item = old; item.isRuleSuppressed = true; item.revision += 1; item.updatedAt = now()
            changes.tasks.append(item); action.tasks.append(old)
            action.expectations.append(.init(entity: .task, id: old.id, revision: item.revision))
        }
        try store.commit(changes)
        return action
    }

    public func undo(_ action: UndoAction) throws {
        var changes = StoreChanges(); changes.expectations = action.expectations
        for old in action.tasks {
            guard let expected = action.expectations.first(where: { $0.entity == .task && $0.id == old.id }) else { throw DomainError.conflict }
            var item = old; item.revision = expected.revision + 1; item.updatedAt = now(); changes.tasks.append(item)
        }
        for old in action.series {
            guard let expected = action.expectations.first(where: { $0.entity == .series && $0.id == old.id }) else { throw DomainError.conflict }
            var root = old; root.revision = expected.revision + 1; root.updatedAt = now(); changes.series.append(root)
        }
        for old in action.countdowns {
            guard let expected = action.expectations.first(where: { $0.entity == .countdown && $0.id == old.id }) else { throw DomainError.conflict }
            var event = old; event.revision = expected.revision + 1; event.updatedAt = now(); changes.countdowns.append(event)
        }
        changes.removals[.exclusion] = action.removeExclusions
        changes.exclusions = action.restoreExclusions
        try store.commit(changes)
    }

    public func restoreTask(id: UUID) throws {
        guard var item = try store.task(id: id), item.deletedAt != nil else { throw DomainError.notFound }
        let config = try store.configuration()
        var changes = StoreChanges()
        changes.expectations = [.init(entity: .task, id: id, revision: item.revision)]
        item.deletedAt = nil; item.isRuleSuppressed = false; item.revision += 1; item.updatedAt = now()
        if let seriesID = item.seriesID, let origin = item.occurrenceDay {
            let markers = config.exclusions.filter { $0.seriesID == seriesID && $0.day == origin }
            if isScheduled(seriesID, origin, config: config) {
                changes.removals[.exclusion] = Set(markers.map(\.id)); item.isOverride = true
            } else {
                changes.exclusions = [exclusion(seriesID, origin, .detached, config: config)]
                item.seriesID = nil; item.ruleVersionID = nil; item.occurrenceDay = nil; item.isOverride = false
            }
        }
        changes.tasks = [item]; try store.commit(changes)
    }

    public func saveCategory(_ category: TodoCategory, baseRevision: Int64) throws -> TodoCategory {
        let config = try store.configuration(), clock = now()
        let old = config.categories.first { $0.id == category.id }
        guard old?.revision ?? 0 == baseRevision else { throw DomainError.conflict }
        var value = category; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.isSystemDefault = old?.isSystemDefault ?? false
        value.createdAt = old?.createdAt ?? clock; value.updatedAt = clock; value.revision = baseRevision + 1
        if old?.isSystemDefault == true && value.name != "通用" { throw DomainError.invalidCategoryName }
        try ModelValidator.category(value)
        if config.categories.contains(where: { $0.id != value.id && $0.normalizedName == value.normalizedName }) { throw DomainError.duplicateCategory }
        var changes = StoreChanges(); changes.categories = [value]
        changes.expectations = [.init(entity: .category, id: value.id, revision: baseRevision)]
        try store.commit(changes); return value
    }

    public func replaceCategory(id: UUID, with replacementID: UUID, baseRevision: Int64) throws {
        let config = try store.configuration()
        guard let old = config.categories.first(where: { $0.id == id }), !old.isSystemDefault,
              old.revision == baseRevision, replacementID != id, config.categories.contains(where: { $0.id == replacementID }) else { throw DomainError.missingCategory }
        var changes = StoreChanges(); changes.removals[.category] = [id]
        changes.expectations = [.init(entity: .category, id: id, revision: baseRevision)]
        let tasks: [TodoItem] = try store.records(.task, matching: "categoryID == %@", values: [.uuid(id)])
        changes.tasks = tasks.map { old in var item = old; item.categoryID = replacementID; item.updatedAt = now(); item.revision += 1; return item }
        changes.rules = config.rules.filter { $0.categoryID == id }.map { old in var rule = old; rule.categoryID = replacementID; return rule }
        let affected = Set(changes.rules.map(\.seriesID))
        changes.series = config.series.filter { affected.contains($0.id) }.map { old in var root = old; root.revision += 1; root.updatedAt = now(); return root }
        try store.commit(changes)
    }

    public func countdowns(archived: Bool = false) throws -> [CountdownEvent] {
        let values: [CountdownEvent] = try store.records(.countdown, matching: "deletedAt == nil")
        return AgendaCalculator.countdowns(values, today: LocalDate(now(), timeZone: timeZone()), archived: archived)
    }

    public func saveCountdown(_ draft: CountdownDraft) throws -> CountdownEvent {
        try saveCountdownWithUndo(draft).event
    }
    public func saveCountdownWithUndo(_ draft: CountdownDraft) throws -> CountdownSaveResult {
        let old = try countdown(id: draft.id)
        if old == nil && draft.baseRevision > 0 { throw DomainError.notFound }
        guard old?.revision ?? 0 == draft.baseRevision else { throw DomainError.conflict }
        guard old?.deletedAt == nil else { throw DomainError.notFound }
        try ModelValidator.title(draft.title, notes: draft.notes)
        guard draft.day.isUserSelectable else { throw DomainError.invalidDate }
        if let reminder = draft.reminderAt, reminder != old?.reminderAt, reminder <= now() { throw DomainError.invalidReminder }
        var event = old ?? CountdownEvent(id: draft.id, title: draft.title, targetDay: draft.day)
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines); event.notes = draft.notes
        event.targetDay = draft.day; event.reminderAt = draft.reminderAt
        event.revision = draft.baseRevision + 1; event.updatedAt = now()
        if old == nil { event.createdAt = now() }
        var changes = StoreChanges(); changes.countdowns = [event]
        changes.expectations = [.init(entity: .countdown, id: event.id, revision: draft.baseRevision)]
        try store.commit(changes)
        var action: UndoAction?
        if let old {
            action = UndoAction(title: "编辑倒计时", countdowns: [old], expectations: [.init(entity: .countdown, id: event.id, revision: event.revision)])
        }
        return .init(event: event, undo: action)
    }

    @discardableResult
    public func setCountdownState(id: UUID, archived: Bool? = nil, deleted: Bool? = nil) throws -> UndoAction? {
        guard var item = try countdown(id: id) else { throw DomainError.notFound }
        guard item.deletedAt == nil || deleted == false else { throw DomainError.notFound }
        let original = item
        guard archived.map({ $0 != (item.archivedAt != nil) }) == true || deleted.map({ $0 != (item.deletedAt != nil) }) == true else { return nil }
        var changes = StoreChanges(); changes.expectations = [.init(entity: .countdown, id: id, revision: item.revision)]
        if let archived { item.archivedAt = archived ? now() : nil }
        if let deleted { item.deletedAt = deleted ? now() : nil }
        item.revision += 1; item.updatedAt = now(); changes.countdowns = [item]
        try store.commit(changes)
        // Restoring from Trash is deliberately outside business undo.
        guard deleted != false else { return nil }
        let title = deleted == true ? "删除倒计时" : archived == true ? "归档倒计时" : "取消归档倒计时"
        return UndoAction(title: title, countdowns: [original], expectations: [.init(entity: .countdown, id: id, revision: item.revision)])
    }

    public func completed(after cursor: RecordCursor? = nil, search: String = "") throws -> RecordPage<TodoItem> {
        try taskPage(timestamp: "completedAt", cursor: cursor, search: search, excludeDeleted: true)
    }

    public func deletedTasks(after cursor: RecordCursor? = nil) throws -> RecordPage<TodoItem> {
        try taskPage(timestamp: "deletedAt", cursor: cursor, search: "", excludeDeleted: false)
    }

    public func deletedCountdowns() throws -> [CountdownEvent] {
        try store.records(.countdown, matching: "deletedAt != nil", order: [.init("deletedAt", ascending: false)])
    }

    public func permanentlyDeleteTask(id: UUID) throws {
        guard let item = try store.task(id: id), item.deletedAt != nil else { throw DomainError.notFound }
        var changes = StoreChanges(); changes.removals[.task] = [id]
        changes.expectations = [.init(entity: .task, id: id, revision: item.revision)]
        try store.commit(changes)
    }

    public func permanentlyDeleteCountdown(id: UUID) throws {
        let records: [CountdownEvent] = try store.records(.countdown, matching: "id == %@ AND deletedAt != nil", values: [.uuid(id)])
        guard let event = records.first else { throw DomainError.notFound }
        var changes = StoreChanges(); changes.removals[.countdown] = [id]
        changes.expectations = [.init(entity: .countdown, id: id, revision: event.revision)]
        try store.commit(changes)
    }

    public func purgeExpiredTrash() throws {
        let cutoff = now().addingTimeInterval(-30 * 86400)
        let tasks: [TodoItem] = try store.records(.task, matching: "deletedAt < %@", values: [.date(cutoff)])
        let events: [CountdownEvent] = try store.records(.countdown, matching: "deletedAt < %@", values: [.date(cutoff)])
        var changes = StoreChanges(); changes.removals[.task] = Set(tasks.map(\.id)); changes.removals[.countdown] = Set(events.map(\.id))
        try store.commit(changes)
    }

    public func exportData() throws -> Data {
        var snapshot = try store.snapshot(); snapshot.exportedAt = now(); return try SnapshotCodec.encode(snapshot)
    }

    /// Materialize a finite horizon, then fetch the next 48 future reminders.
    public func reminderCandidates() throws -> (tasks: [TodoItem], events: [CountdownEvent]) {
        let today = LocalDate(now(), timeZone: timeZone())
        let last = try LocalDate(year: 9999, month: 12, day: 31)
        let horizon = try agenda(.days(from: today, count: min(30, today.distance(to: last) + 1)))
        let config = try store.configuration()
        let absolute: [TodoItem] = try store.records(.task,
            matching: "reminderAt > %@ AND deletedAt == nil AND completedAt == nil AND isRuleSuppressed == NO AND (seriesID == nil OR isOverride == YES)",
            values: [.date(now())], order: [.init("reminderAt", ascending: true)])
        // A normal recurring instance follows local wall time after a zone change.
        // Single-instance overrides retain their explicitly saved absolute reminder.
        let recurring = try horizon.items.filter { $0.seriesID != nil && !$0.isOverride }.compactMap { original -> TodoItem? in
            guard let rule = config.rules.first(where: { $0.id == original.ruleVersionID }), let offset = rule.reminderOffsetMinutes else { return nil }
            var task = original
            task.reminderAt = try task.scheduledDay.instant(minute: task.scheduledMinute, timeZone: timeZone()).addingTimeInterval(-Double(offset * 60))
            return task.reminderAt! > now() ? task : nil
        }
        let tasks = (absolute + recurring).sorted { $0.reminderAt! < $1.reminderAt! }
        let events: [CountdownEvent] = try store.records(.countdown,
            matching: "reminderAt > %@ AND deletedAt == nil AND archivedAt == nil",
            values: [.date(now())], order: [.init("reminderAt", ascending: true)])
        return (tasks, events)
    }

    /// File backup and draft coordination happen in the app before this atomic replacement.
    public func restoreData(_ data: Data) throws { try store.replace(with: SnapshotCodec.decode(data)) }

    private func taskPage(timestamp: String, cursor: RecordCursor?, search: String, excludeDeleted: Bool) throws -> RecordPage<TodoItem> {
        // timestamp is one of two private constants, never user-controlled SQL/predicate text.
        var format = "\(timestamp) != nil"
        var arguments: [StoreQueryValue] = []
        if excludeDeleted { format += " AND deletedAt == nil" }
        if let cursor {
            format += " AND (\(timestamp) < %@ OR (\(timestamp) == %@ AND id > %@))"
            arguments += [.date(cursor.timestamp), .date(cursor.timestamp), .uuid(cursor.id)]
        }
        if !search.isEmpty { format += " AND (title CONTAINS[cd] %@ OR notes CONTAINS[cd] %@)"; arguments += [.text(search), .text(search)] }
        let items: [TodoItem] = try store.records(.task, matching: format, values: arguments,
            order: [.init(timestamp, ascending: false), .init("id", ascending: true)], limit: 51)
        let page = Array(items.prefix(50))
        let date = timestamp == "completedAt" ? page.last?.completedAt : page.last?.deletedAt
        let next = items.count > 50 ? date.map { RecordCursor(timestamp: $0, id: page.last!.id) } : nil
        return RecordPage(items: page, nextCursor: next)
    }

    func seriesTasks(_ id: UUID) throws -> [TodoItem] {
        try store.records(.task, matching: "seriesID == %@", values: [.uuid(id)])
    }
    private func isScheduled(_ id: UUID, _ day: LocalDate, config: StoreSnapshot) -> Bool {
        guard let root = config.series.first(where: { $0.id == id }), root.stoppedFromDay == nil || day < root.stoppedFromDay! else { return false }
        return AgendaCalculator.rule(for: day, seriesID: id, rules: config.rules)?.matches(day) == true
    }
    private func exclusion(_ id: UUID, _ day: LocalDate, _ reason: ExclusionReason, config: StoreSnapshot) -> TodoOccurrenceExclusion {
        var value = config.exclusions.first { $0.seriesID == id && $0.day == day } ?? TodoOccurrenceExclusion(seriesID: id, day: day, reason: reason)
        value.reason = reason; value.createdAt = now(); return value
    }
    private func makeRule(_ draft: TaskDraft, seriesID: UUID, from: LocalDate, frequency: RepeatFrequency, categories: [TodoCategory]) throws -> TodoSeriesRule {
        guard let minute = draft.minute, let category = draft.categoryID else { throw DomainError.invalidRecurrence }
        var rule = TodoSeriesRule(seriesID: seriesID, from: from, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  minute: minute, categoryID: category, frequency: frequency, weekdays: draft.weekdays)
        rule.notes = draft.notes; rule.isImportant = draft.isImportant; rule.endDay = draft.endDay; rule.reminderOffsetMinutes = draft.reminderOffsetMinutes
        try ModelValidator.rule(rule, categories: Set(categories.map(\.id)))
        return rule
    }
    private func apply(_ rule: TodoSeriesRule, to item: inout TodoItem, day: LocalDate, clock: Date) throws {
        item.title = rule.title; item.notes = rule.notes; item.scheduledDay = day; item.scheduledMinute = rule.minute
        item.categoryID = rule.categoryID; item.isImportant = rule.isImportant; item.ruleVersionID = rule.id
        item.isOverride = false; item.isRuleSuppressed = false; item.updatedAt = clock; item.revision += 1
        item.reminderAt = try rule.reminderOffsetMinutes.map { offset in try day.instant(minute: rule.minute, timeZone: timeZone()).addingTimeInterval(-Double(offset * 60)) }
    }
    private func taskUndo(_ original: TodoItem, result: TodoItem, config: StoreSnapshot, title: String) -> UndoAction {
        var action = UndoAction(title: title); action.tasks = [original]
        action.expectations = [.init(entity: .task, id: original.id, revision: result.revision)]
        if let seriesID = original.seriesID, let root = config.series.first(where: { $0.id == seriesID }) {
            action.expectations.append(.init(entity: .series, id: seriesID, revision: root.revision))
        }
        return action
    }
}
