import Foundation
import Testing
@testable import TodoDomain

@Suite struct OptionalTimeTests {
    @Test func unsetAndMidnightHaveDistinctSortingAndClockBehavior() throws {
        let day = try LocalDate("2026-11-02"), category = TodoCategory.defaults[0].id
        let unset = TodoItem(title: "当天事项", scheduledDay: day, categoryID: category)
        let midnight = TodoItem(title: "零点事项", scheduledDay: day, scheduledMinute: 0, categoryID: category)
        #expect([midnight, unset].sorted(by: AgendaCalculator.taskOrder).map(\.id) == [unset.id, midnight.id])
        #expect(unset.timeLabel.isEmpty && midnight.timeLabel == "00:00")
        let zone = TimeZone(secondsFromGMT: 0)!, now = try day.instant(minute: 600, timeZone: zone)
        #expect(!AgendaClock.hasPassed(unset, now: now, timeZone: zone))
        #expect(AgendaClock.hasPassed(midnight, now: now, timeZone: zone))
        #expect(AgendaClock.nextChange(items: [unset], now: now, timeZone: zone) == (try day.adding(days: 1).instant(minute: 0, timeZone: zone)))
        var reminded = unset; reminded.reminderAt = now.addingTimeInterval(60)
        let request = try #require(ReminderPlan(tasks: [reminded], events: [], now: now).requests.first)
        #expect(request.body == "待办 · 2026-11-02" && request.date == reminded.reminderAt)
    }
    @Test func untimedRulesAndSnapshotsValidateButRelativeRemindersNeedTime() throws {
        let day = try LocalDate("2026-11-02"), category = TodoCategory.defaults[0].id
        var item = TodoItem(title: "当天事项", scheduledDay: day, categoryID: category)
        try ModelValidator.task(item, categories: [category])
        for invalid in [-2, 1440] {
            item.scheduledMinute = invalid
            #expect(throws: DomainError.invalidTime) { try ModelValidator.task(item, categories: [category]) }
        }
        var rule = TodoSeriesRule(seriesID: UUID(), from: day, title: "每日", minute: ScheduledTime.unspecified, categoryID: category, frequency: .daily)
        try ModelValidator.rule(rule, categories: [category])
        #expect(RecurrencePreview.summary(frequency: .daily, weekdays: [], minute: rule.minute, category: "通用") == "每日 未设时间 · 通用")
        rule.reminderOffsetMinutes = 0
        #expect(throws: DomainError.recurringReminderNeedsTime) { try ModelValidator.rule(rule, categories: [category]) }
        rule.minute = 0
        try ModelValidator.rule(rule, categories: [category])
    }
}
