import Foundation

public struct LocalTimeResolution: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case exact, advanced, repeated }
    public let day: LocalDate
    public let requestedMinute: Int
    public let resolvedMinute: Int
    public let resolvedSecond: Int
    public let instant: Date
    public let alternative: Date?
    public let timeZoneIdentifier: String
    public let utcOffset: Int
    public let alternativeUTCOffset: Int?
    public var kind: Kind { requestedMinute != resolvedMinute || resolvedSecond != 0 ? .advanced : alternative == nil ? .exact : .repeated }
    public var requestedTimeLabel: String { Self.label(requestedMinute) }
    public var resolvedTimeLabel: String { Self.label(resolvedMinute) + (resolvedSecond == 0 ? "" : String(format: ":%02d", resolvedSecond)) }
    private static func label(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public static func offsetLabel(_ seconds: Int) -> String {
        String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60) + (seconds % 60 == 0 ? "" : String(format: ":%02d", abs(seconds) % 60))
    }
}

extension LocalDate {
    /// Resolve candidates using actual offsets and transitions. Calendar's
    /// nextDate matching skips or misses some half-hour gaps/folds on macOS.
    /// The 96-hour window surrounds every supported zone offset and a date-line
    /// jump; all transitions in that window are visited, with a defensive bound.
    public func resolveTime(minute: Int, timeZone: TimeZone = .current) throws -> LocalTimeResolution {
        guard (0..<1440).contains(minute) else { throw DomainError.invalidTime }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let civil = utc.date(from: DateComponents(year: year, month: month, day: day, hour: minute / 60, minute: minute % 60, second: 0)) else { throw DomainError.unavailableLocalTime }
        let lower = civil.addingTimeInterval(-48 * 3600), upper = civil.addingTimeInterval(48 * 3600)
        var offsets = Set([timeZone.secondsFromGMT(for: lower), timeZone.secondsFromGMT(for: civil), timeZone.secondsFromGMT(for: upper)])
        var cursor = lower, transitions: [Date] = []
        while let transition = timeZone.nextDaylightSavingTimeTransition(after: cursor), transition <= upper {
            guard transition > cursor, transitions.count < 16 else { throw DomainError.unavailableLocalTime }
            transitions.append(transition)
            offsets.insert(timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1)))
            offsets.insert(timeZone.secondsFromGMT(for: transition))
            cursor = transition
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let candidates = offsets.map { civil.addingTimeInterval(-Double($0)) }.filter {
            LocalDate($0, timeZone: timeZone) == self && calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) == minute && calendar.component(.second, from: $0) == 0
        }.sorted()
        let first: Date
        if let candidate = candidates.first { first = candidate }
        else {
            guard let gap = transitions.first(where: { transition in
                let before = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1)), after = timeZone.secondsFromGMT(for: transition)
                return after > before && civil >= transition.addingTimeInterval(Double(before)) && civil < transition.addingTimeInterval(Double(after))
            }), LocalDate(gap, timeZone: timeZone) == self else { throw DomainError.unavailableLocalTime }
            first = gap
        }
        let resolved = calendar.component(.hour, from: first) * 60 + calendar.component(.minute, from: first)
        let alternate = candidates.count > 1 ? candidates.last : nil
        return .init(day: self, requestedMinute: minute, resolvedMinute: resolved, resolvedSecond: calendar.component(.second, from: first), instant: first, alternative: alternate,
                     timeZoneIdentifier: timeZone.identifier, utcOffset: timeZone.secondsFromGMT(for: first),
                     alternativeUTCOffset: alternate.map { timeZone.secondsFromGMT(for: $0) })
    }
}
