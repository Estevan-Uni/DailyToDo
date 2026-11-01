import Foundation

public enum ModelValidator {
    public static func title(_ value: String, notes: String = "") throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DomainError.emptyTitle }
        guard value.count <= 200 else { throw DomainError.titleTooLong }
        guard notes.count <= 10_000 else { throw DomainError.notesTooLong }
    }
    public static func category(_ value: TodoCategory) throws {
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 12 else { throw DomainError.invalidCategoryName }
        guard value.colorHex.count == 7, value.colorHex.first == "#",
              value.colorHex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw DomainError.invalidColor }
        guard !value.isSystemDefault || (value.id == TodoCategory.defaults[0].id && name == "通用") else {
            throw DomainError.invalidCategoryName
        }
    }
    public static func task(_ value: TodoItem, categories: Set<UUID>) throws {
        try title(value.title, notes: value.notes)
        guard value.scheduledDay.isUserSelectable else { throw DomainError.invalidDate }
        guard ScheduledTime.isValid(value.scheduledMinute) else { throw DomainError.invalidTime }
        guard categories.contains(value.categoryID) else { throw DomainError.missingCategory }
        let linkage = [value.seriesID != nil, value.ruleVersionID != nil, value.occurrenceDay != nil]
        guard linkage.allSatisfy({ $0 }) || linkage.allSatisfy({ !$0 }) else {
            throw DomainError.invalidSnapshot("重复实例关联不完整")
        }
        guard value.revision > 0, !(value.isRuleSuppressed && (value.seriesID == nil || value.completedAt != nil)) else {
            throw DomainError.invalidSnapshot("任务状态或修订号无效")
        }
    }
    public static func rule(_ value: TodoSeriesRule, categories: Set<UUID>) throws {
        try title(value.title, notes: value.notes)
        guard value.effectiveFromDay.isUserSelectable, value.endDay?.isUserSelectable != false,
              ScheduledTime.isValid(value.minute),
              value.endDay == nil || value.endDay! >= value.effectiveFromDay,
              value.weekdays.isSubset(of: Set(1...7)),
              value.frequency != .weekly || !value.weekdays.isEmpty,
              value.reminderOffsetMinutes == nil || (0...10080).contains(value.reminderOffsetMinutes!) else {
            throw DomainError.invalidRecurrence
        }
        if value.reminderOffsetMinutes != nil, !ScheduledTime.hasTime(value.minute) { throw DomainError.recurringReminderNeedsTime }
        guard categories.contains(value.categoryID) else { throw DomainError.missingCategory }
        if let end = value.endDay, value.frequency == .weekly {
            let firstWeek = min(6, value.effectiveFromDay.distance(to: end))
            guard (0...firstWeek).contains(where: { offset in
                guard let day = try? value.effectiveFromDay.adding(days: offset) else { return false }
                return value.matches(day)
            }) else { throw DomainError.invalidRecurrence }
        }
    }
    public static func snapshot(_ value: StoreSnapshot) throws {
        guard value.schemaVersion == 1 else { throw DomainError.unsupportedVersion }
        func unique<T: Identifiable>(_ values: [T], _ name: String) throws where T.ID: Hashable {
            guard Set(values.map(\.id)).count == values.count else { throw DomainError.invalidSnapshot("\(name)存在重复 ID") }
        }
        try unique(value.categories, "类型"); try unique(value.tasks, "待办")
        try unique(value.series, "系列"); try unique(value.rules, "规则")
        try unique(value.exclusions, "排除标记"); try unique(value.countdowns, "倒计时")
        let categories = Set(value.categories.map(\.id))
        let roots = Set(value.series.map(\.id))
        let rules = Dictionary(uniqueKeysWithValues: value.rules.map { ($0.id, $0) })
        for category in value.categories { try self.category(category) }
        guard value.categories.filter(\.isSystemDefault).count == 1,
              Set(value.categories.map(\.normalizedName)).count == value.categories.count else { throw DomainError.duplicateCategory }
        guard Set(value.tasks.map(\.occurrenceKey)).count == value.tasks.count,
              Set(value.exclusions.map(\.occurrenceKey)).count == value.exclusions.count else { throw DomainError.invalidSnapshot("发生键重复") }
        var activeVersionKeys = Set<String>()
        for rule in value.rules {
            try self.rule(rule, categories: categories)
            guard roots.contains(rule.seriesID) else { throw DomainError.invalidSnapshot("规则缺少系列") }
            if !rule.isSupersededForExpansion {
                let key = OccurrenceIdentity.key(seriesID: rule.seriesID, day: rule.effectiveFromDay)
                guard activeVersionKeys.insert(key).inserted else { throw DomainError.invalidSnapshot("规则生效日冲突") }
            }
        }
        for root in value.series {
            guard root.revision > 0, root.stoppedFromDay?.isUserSelectable != false else { throw DomainError.invalidRecurrence }
        }
        for task in value.tasks {
            try self.task(task, categories: categories)
            if let seriesID = task.seriesID, let ruleID = task.ruleVersionID {
                guard roots.contains(seriesID), rules[ruleID]?.seriesID == seriesID,
                      task.occurrenceDay?.isUserSelectable == true else { throw DomainError.invalidSnapshot("实例缺少有效系列或版本") }
            }
        }
        for exclusion in value.exclusions {
            guard roots.contains(exclusion.seriesID), exclusion.day.isUserSelectable else { throw DomainError.invalidSnapshot("排除标记关联失效") }
        }
        for event in value.countdowns {
            try title(event.title, notes: event.notes)
            guard event.targetDay.isUserSelectable, event.revision > 0 else { throw DomainError.invalidDate }
        }
    }
}

public enum SnapshotCodec {
    public static let maximumBytes = 100 * 1024 * 1024
    public static func encode(_ snapshot: StoreSnapshot) throws -> Data {
        try ModelValidator.snapshot(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumBytes else { throw DomainError.invalidSnapshot("文件超过 100 MiB 导出恢复上限") }
        return data
    }
    public static func decode(_ data: Data) throws -> StoreSnapshot {
        guard data.count <= maximumBytes else { throw DomainError.invalidSnapshot("文件超过 100 MiB 恢复上限") }
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = header["schemaVersion"] as? Int, version == 1 else { throw DomainError.unsupportedVersion }
        let value = try JSONDecoder().decode(StoreSnapshot.self, from: data)
        try ModelValidator.snapshot(value)
        return value
    }
}
