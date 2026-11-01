import Foundation
import CryptoKit

public enum DomainError: Error, LocalizedError, Equatable, Sendable {
    case invalidDate, invalidTime, invalidRange, emptyTitle, titleTooLong, notesTooLong
    case recurringReminderNeedsTime
    case missingCategory, invalidColor, invalidCategoryName, duplicateCategory, invalidRecurrence
    case invalidSnapshot(String), conflict, notFound, unsupportedVersion, invalidReminder, unavailableLocalTime
    public var errorDescription: String? {
        switch self {
        case .invalidDate: "请选择有效日期（1900–9999 年）。"
        case .invalidTime: "时间格式应为 HH:mm（00:00–23:59），也可以留空。"
        case .recurringReminderNeedsTime: "重复提醒需要具体时间；请填写时间，或选择不提醒。"
        case .unavailableLocalTime: "该日期与时间在当前时区无法解析，请选择其他日期或时刻。"
        case .invalidRange: "查询日期范围须为 1–366 天。"
        case .emptyTitle: "请填写事项或事件。"
        case .titleTooLong: "事项或事件不能超过 200 个字符。"
        case .notesTooLong: "备注不能超过 10000 个字符。"
        case .missingCategory: "请选择有效的待办类型。"
        case .invalidColor: "请选择有效的不透明颜色。"
        case .invalidCategoryName: "类型名称须为 1–12 个字符。"
        case .duplicateCategory: "已有同名类型，请使用其他名称。"
        case .invalidRecurrence: "请检查重复星期、开始/结束日期和提醒提前量。"
        case .invalidSnapshot(let reason): "数据校验失败：\(reason)"
        case .conflict: "此记录已在其他位置更新，草稿已保留，请重新载入后合并修改。"
        case .notFound: "此记录已不存在。"
        case .unsupportedVersion: "此文件来自尚不支持的数据版本，未更改当前数据。"
        case .invalidReminder: "新设置的提醒必须晚于当前时间。"
        }
    }
}

public struct TodoCategory: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var sortOrder: Int
    public var isSystemDefault: Bool
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var revision: Int64 = 1
    public init(id: UUID = UUID(), name: String, colorHex: String, sortOrder: Int = 0, isSystemDefault: Bool = false) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.sortOrder = sortOrder; self.isSystemDefault = isSystemDefault
    }
    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    public static let defaults: [Self] = [
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "通用", colorHex: "#83908B", sortOrder: 0, isSystemDefault: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "工作", colorHex: "#527FAF", sortOrder: 1),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "学习", colorHex: "#917CB4", sortOrder: 2),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, name: "生活", colorHex: "#64967C", sortOrder: 3)
    ]
}

public struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var notes: String = ""
    public var scheduledDay: LocalDate
    public var scheduledMinute: Int
    public var categoryID: UUID
    public var isImportant: Bool = false
    public var seriesID: UUID?
    public var ruleVersionID: UUID?
    public var occurrenceDay: LocalDate?
    public var isOverride: Bool = false
    public var isRuleSuppressed: Bool = false
    public var completedAt: Date?
    public var reminderAt: Date?
    public var deletedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var revision: Int64 = 1
    public init(id: UUID = UUID(), title: String, scheduledDay: LocalDate, scheduledMinute: Int = ScheduledTime.unspecified, categoryID: UUID) {
        self.id = id; self.title = title; self.scheduledDay = scheduledDay
        self.scheduledMinute = scheduledMinute; self.categoryID = categoryID
    }
    public var occurrenceKey: String {
        if let seriesID, let occurrenceDay { return OccurrenceIdentity.key(seriesID: seriesID, day: occurrenceDay) }
        return "t:\(id.uuidString.lowercased())"
    }
    public var hasScheduledTime: Bool { ScheduledTime.hasTime(scheduledMinute) }
    public var timeLabel: String { ScheduledTime.label(scheduledMinute) }
}

public struct TodoSeries: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var stoppedFromDay: LocalDate?
    public var revision: Int64 = 1
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public init(id: UUID = UUID()) { self.id = id }
}

public enum RepeatFrequency: String, Codable, CaseIterable, Sendable { case daily, weekly }

public struct TodoSeriesRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var seriesID: UUID
    public var effectiveFromDay: LocalDate
    public var endDay: LocalDate?
    public var title: String
    public var notes: String = ""
    public var isImportant = false
    public var minute: Int
    public var categoryID: UUID
    public var frequency: RepeatFrequency
    public var weekdays: Set<Int> = []
    public var reminderOffsetMinutes: Int?
    public var isSupersededForExpansion: Bool = false
    public init(seriesID: UUID, from: LocalDate, title: String, minute: Int, categoryID: UUID, frequency: RepeatFrequency, weekdays: Set<Int> = []) {
        self.seriesID = seriesID; effectiveFromDay = from; self.title = title; self.minute = minute
        self.categoryID = categoryID; self.frequency = frequency; self.weekdays = weekdays
    }
    public func matches(_ day: LocalDate) -> Bool {
        effectiveFromDay <= day && (endDay == nil || day <= endDay!) && (frequency == .daily || weekdays.contains(day.weekday))
    }
}

public enum ExclusionReason: String, Codable, Sendable { case userDeleted, detached }
public struct TodoOccurrenceExclusion: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var seriesID: UUID
    public var day: LocalDate
    public var reason: ExclusionReason
    public var createdAt: Date = Date()
    public init(seriesID: UUID, day: LocalDate, reason: ExclusionReason) { self.seriesID = seriesID; self.day = day; self.reason = reason }
    public var occurrenceKey: String { OccurrenceIdentity.key(seriesID: seriesID, day: day) }
}

public struct CountdownEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var notes: String = ""
    public var targetDay: LocalDate
    public var reminderAt: Date?
    public var archivedAt: Date?
    public var deletedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var revision: Int64 = 1
    public init(id: UUID = UUID(), title: String, targetDay: LocalDate) { self.id = id; self.title = title; self.targetDay = targetDay }
    public func days(from today: LocalDate) -> Int { today.distance(to: targetDay) }
    public func label(from today: LocalDate) -> String {
        let n = days(from: today)
        return n == 0 ? "就是今天" : n > 0 ? "\(n) 天后" : "已过去 \(-n) 天"
    }
}

public struct StoreSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var exportedAt: Date = Date()
    public var categories: [TodoCategory] = TodoCategory.defaults
    public var tasks: [TodoItem] = []
    public var series: [TodoSeries] = []
    public var rules: [TodoSeriesRule] = []
    public var exclusions: [TodoOccurrenceExclusion] = []
    public var countdowns: [CountdownEvent] = []
    public init() {}
}

public enum OccurrenceIdentity {
    public static func key(seriesID: UUID, day: LocalDate) -> String { "r:\(seriesID.uuidString.lowercased()):\(day)" }
    public static func id(seriesID: UUID, day: LocalDate) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key(seriesID: seriesID, day: day).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
