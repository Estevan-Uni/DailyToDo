import Foundation

/// Shared civil-time dependency. The system zone is read on demand so a travel
/// or clock-change refresh uses the new zone without rebuilding the app model.
public struct AppClock: Sendable {
    public let now: @Sendable () -> Date
    public let timeZone: @Sendable () -> TimeZone
    public init(now: @escaping @Sendable () -> Date, timeZone: @escaping @Sendable () -> TimeZone) {
        self.now = now; self.timeZone = timeZone
    }
    public static var system: Self { .init(now: { Date() }, timeZone: { .current }) }
    public var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = timeZone(); return value
    }
    public var today: LocalDate { day(at: now()) }
    public func day(at instant: Date) -> LocalDate { LocalDate(instant, timeZone: timeZone()) }
    public func formatted(_ instant: Date, date: Date.FormatStyle.DateStyle = .abbreviated,
                          time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        var format = Date.FormatStyle(date: date, time: time)
        format.calendar = calendar; format.timeZone = timeZone()
        return instant.formatted(format)
    }
}
