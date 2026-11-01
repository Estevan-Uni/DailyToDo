import Foundation

/// A Gregorian civil date, independent of time zone and absolute midnight.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        // 10000-01-01 exists only as an exclusive upper bound for year 9999.
        guard (1900...9999).contains(year) || (year == 10000 && month == 1 && day == 1),
              (1...12).contains(month), (1...31).contains(day) else { throw DomainError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let value = calendar.date(from: components),
              calendar.component(.year, from: value) == year,
              calendar.component(.month, from: value) == month,
              calendar.component(.day, from: value) == day else { throw DomainError.invalidDate }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            throw DomainError.invalidDate
        }
        try self.init(year: y, month: m, day: d)
        guard description == text else { throw DomainError.invalidDate }
    }

    public init(_ instant: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        year = calendar.component(.year, from: instant)
        month = calendar.component(.month, from: instant)
        day = calendar.component(.day, from: instant)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var isUserSelectable: Bool { (1900...9999).contains(year) }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) throws -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let result = calendar.date(byAdding: .day, value: days, to: noon(timeZone: calendar.timeZone)) else {
            throw DomainError.invalidDate
        }
        return try Self(year: calendar.component(.year, from: result), month: calendar.component(.month, from: result), day: calendar.component(.day, from: result))
    }

    public func distance(to other: Self) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.day], from: noon(timeZone: calendar.timeZone), to: other.noon(timeZone: calendar.timeZone)).day!
    }

    public func noon(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// ISO weekday: Monday = 1, Sunday = 7.
    public var weekday: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (calendar.component(.weekday, from: noon(timeZone: calendar.timeZone)) + 5) % 7 + 1
    }

    /// Repeated wall times choose the first occurrence; gaps advance to the next legal instant.
    public func instant(minute: Int, timeZone: TimeZone = .current) throws -> Date {
        try resolveTime(minute: minute, timeZone: timeZone).instant
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public struct DayInterval: Hashable, Sendable {
    public let start: LocalDate
    public let endExclusive: LocalDate
    public init(start: LocalDate, endExclusive: LocalDate) throws {
        guard start < endExclusive, start.distance(to: endExclusive) <= 366 else { throw DomainError.invalidRange }
        self.start = start
        self.endExclusive = endExclusive
    }
    public static func days(from start: LocalDate, count: Int) throws -> Self {
        try Self(start: start, endExclusive: start.adding(days: count))
    }
    public static func month(containing day: LocalDate) throws -> Self {
        let first = try LocalDate(year: day.year, month: day.month, day: 1)
        let next = try LocalDate(year: day.month == 12 ? day.year + 1 : day.year, month: day.month == 12 ? 1 : day.month + 1, day: 1)
        return try Self(start: first, endExclusive: next)
    }
    /// A calendar week is Monday through Sunday, clipped at the supported edge.
    public static func week(containing day: LocalDate) throws -> Self {
        let start = try day.adding(days: 1 - day.weekday)
        let maximum = try LocalDate(year: 9999, month: 12, day: 31)
        let count = min(7, start.distance(to: maximum) + 1)
        return try .days(from: start, count: count)
    }
    public func contains(_ day: LocalDate) -> Bool { start <= day && day < endExclusive }
    public var dates: [LocalDate] {
        (0..<start.distance(to: endExclusive)).compactMap { try? start.adding(days: $0) }
    }
}
