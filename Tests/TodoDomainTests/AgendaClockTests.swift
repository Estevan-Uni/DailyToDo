import Foundation
import Testing
@testable import TodoDomain

@Suite struct AgendaClockTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func item(_ day: LocalDate, _ minute: Int) -> TodoItem {
        TodoItem(title: "安排", scheduledDay: day, scheduledMinute: minute, categoryID: UUID())
    }
    @Test func onlyOpenTodayGetsStatusAtItsBoundary() throws {
        let day = try LocalDate("2026-11-01"), boundary = try day.instant(minute: 600, timeZone: utc)
        let task = item(day, 600)
        #expect(!AgendaClock.hasPassed(task, now: boundary.addingTimeInterval(-0.01), timeZone: utc))
        #expect(AgendaClock.hasPassed(task, now: boundary, timeZone: utc))
        #expect(!AgendaClock.hasPassed(task, now: boundary.addingTimeInterval(86400), timeZone: utc))
        var done = task; done.completedAt = boundary
        var deleted = task; deleted.deletedAt = boundary
        var suppressed = task; suppressed.isRuleSuppressed = true
        for hidden in [done, deleted, suppressed] { #expect(!AgendaClock.hasPassed(hidden, now: boundary, timeZone: utc)) }
    }
    @Test func nextBoundarySkipsPastHiddenAndFutureDates() throws {
        let day = try LocalDate("2026-11-01"), now = try day.instant(minute: 600, timeZone: utc)
        var done = item(day, 601); done.completedAt = now
        var deleted = item(day, 602); deleted.deletedAt = now
        let next = item(day, 630)
        let tasks = [item(day, 500), item(day, 600), item(try day.adding(days: 1), 0), done, deleted, next]
        #expect(AgendaClock.nextChange(items: tasks, now: now, timeZone: utc) == (try day.instant(minute: 630, timeZone: utc)))
        #expect(AgendaClock.nextChange(items: tasks, now: try day.instant(minute: 700, timeZone: utc), timeZone: utc) == (try day.adding(days: 1).instant(minute: 0, timeZone: utc)))
    }
    @Test func midnightAndLocalTimeRespectDSTAndZone() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!, day = try LocalDate("2026-03-08")
        let midnight = try day.instant(minute: 0, timeZone: zone)
        let nextMidnight = try day.adding(days: 1).instant(minute: 0, timeZone: zone)
        #expect(AgendaClock.nextChange(items: [], now: midnight, timeZone: zone) == nextMidnight)
        #expect(nextMidnight.timeIntervalSince(midnight) == 23 * 3600)
        let gap = item(day, 150), resolved = try day.instant(minute: 150, timeZone: zone)
        #expect(!AgendaClock.hasPassed(gap, now: resolved.addingTimeInterval(-1), timeZone: zone))
        #expect(AgendaClock.hasPassed(gap, now: resolved, timeZone: zone))
    }
}
