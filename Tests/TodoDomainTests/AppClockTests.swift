import Foundation
import Testing
import TodoDomain

@Suite struct AppClockTests {
    @Test func injectedInstantAndZoneDriveTheSameCivilDateAndCalendar() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-31T23:30:00Z"))
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let clock = AppClock(now: { instant }, timeZone: { zone })
        #expect(clock.today == (try LocalDate("2027-01-01")))
        #expect(clock.calendar.identifier == .gregorian && clock.calendar.timeZone == zone)
        #expect(clock.calendar.component(.hour, from: clock.now()) == 7)
        #expect(clock.day(at: instant.addingTimeInterval(-8 * 3600)) == (try LocalDate("2026-12-31")))
        let utc = AppClock(now: { instant }, timeZone: { TimeZone(secondsFromGMT: 0)! })
        #expect(clock.formatted(instant, date: .numeric, time: .omitted) != utc.formatted(instant, date: .numeric, time: .omitted))
    }
    @Test func injectedCalendarUsesTheActualDSTDayBoundary() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2027-03-14T08:00:00Z"))
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let clock = AppClock(now: { instant }, timeZone: { zone })
        let next = try #require(clock.calendar.date(byAdding: .day, value: 1, to: clock.calendar.startOfDay(for: clock.now())))
        #expect(next.timeIntervalSince(clock.now()) == 23 * 3600)
        #expect(AgendaClock.nextChange(items: [], now: clock.now(), timeZone: clock.timeZone()) == next)
        #expect(clock.day(at: next) == (try LocalDate("2027-03-15")))
    }
}
