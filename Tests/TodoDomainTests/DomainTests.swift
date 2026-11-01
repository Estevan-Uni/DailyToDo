import Foundation
import Testing
@testable import TodoDomain

@Suite struct DomainTests {
    private let category = TodoCategory.defaults[2].id
    private func d(_ text: String) throws -> LocalDate { try LocalDate(text) }
    private func fixture() throws -> StoreSnapshot {
        var value = StoreSnapshot()
        let root = TodoSeries()
        value.series = [root]
        value.rules = [TodoSeriesRule(seriesID: root.id, from: try d("2026-11-02"), title: "阅读文献", minute: 540,
                                      categoryID: category, frequency: .weekly, weekdays: [1, 3])]
        return value
    }
    private func project(_ value: StoreSnapshot, start: String = "2026-11-02", days: Int = 7, completed: Bool = false) throws -> AgendaProjection {
        try AgendaCalculator.project(interval: .days(from: d(start), count: days), tasks: value.tasks, series: value.series,
                                     rules: value.rules, exclusions: value.exclusions, now: Date(timeIntervalSince1970: 0),
                                     timeZone: TimeZone(secondsFromGMT: 0)!, includeCompleted: completed)
    }

    @Test func testInvalidCivilDatesRejected() {
        for text in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "2026-01-00", "2026-1-01", "today", "2026-01-01junk", "1899-12-31"] {
            #expect(throws: (any Error).self) { try d(text) }
        }
    }
    @Test func testLeapDayAndYearBoundary() throws {
        #expect(try d("2024-02-28").adding(days: 1) == d("2024-02-29"))
        #expect(try d("2026-12-31").adding(days: 1) == d("2027-01-01"))
        #expect(try d("2024-02-28").distance(to: d("2024-03-01")) == 2)
    }
    @Test func testExclusiveUpperSentinel() throws {
        let last = try d("9999-12-31")
        let sentinel = try last.adding(days: 1)
        #expect(last < sentinel)
        #expect(!(sentinel.isUserSelectable))
        #expect(try DayInterval.days(from: last, count: 1).dates == [last])
    }
    @Test func testSevenDaysCrossMonthAndWeek() throws {
        let range = try DayInterval.days(from: d("2026-10-31"), count: 7)
        #expect(range.dates.count == 7)
        #expect(try range.dates.last == d("2026-11-06"))
        #expect(try d("2026-11-02").weekday == 1)
        #expect(try d("2026-11-01").weekday == 7)
    }
    @Test func testMonthBoundsAndQueryLimit() throws {
        #expect(try DayInterval.month(containing: d("2024-02-28")).dates.count == 29)
        #expect(throws: (any Error).self) { try DayInterval.days(from: d("2026-01-01"), count: 0) }
        #expect(throws: (any Error).self) { try DayInterval.days(from: d("2026-01-01"), count: 367) }
    }
    @Test func testDayDifferenceDoesNotUseDSTSeconds() throws {
        #expect(try d("2026-03-07").distance(to: d("2026-03-09")) == 2)
        #expect(try d("2026-10-31").distance(to: d("2026-11-02")) == 2)
    }
    @Test func testWallTimeDSTGapAdvancesAndFoldIsFirst() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let gap = try d("2026-03-08").instant(minute: 150, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        #expect(calendar.component(.hour, from: gap) == 3)
        #expect(calendar.component(.minute, from: gap) == 0)
        let fold = try d("2026-11-01").instant(minute: 90, timeZone: zone)
        #expect(ISO8601DateFormatter().string(from: fold) == "2026-11-01T08:30:00Z")
    }
    @Test func testMidnightAndInvalidMinute() throws {
        let day = try d("2026-11-02")
        let zone = TimeZone(secondsFromGMT: 0)!
        #expect(ISO8601DateFormatter().string(from: try day.instant(minute: 0, timeZone: zone)) == "2026-11-02T00:00:00Z")
        #expect(throws: (any Error).self) { try day.instant(minute: 1440) }
        #expect(throws: (any Error).self) { try day.instant(minute: -1) }
    }
    @Test func testCivilDateChangesWithTimeZone() throws {
        let instant = ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z")!
        #expect(try LocalDate(instant, timeZone: TimeZone(identifier: "Asia/Shanghai")!) == d("2026-11-01"))
        #expect(try LocalDate(instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == d("2026-10-31"))
    }
    @Test func testTypeValidationAndNameNormalization() throws {
        try ModelValidator.category(.init(name: "Work", colorHex: "#1a2b3C"))
        #expect(TodoCategory(name: " Work ", colorHex: "#123456").normalizedName == "work")
        for color in ["red", "#123", "#12345678", "#GGFFFF", "123456", "#１２３４５６"] {
            #expect(throws: (any Error).self) { try ModelValidator.category(.init(name: "自定义", colorHex: color)) }
        }
        #expect(throws: (any Error).self) { try ModelValidator.category(.init(name: "  ", colorHex: "#123456")) }
    }
    @Test func testTaskRequiresAllThreeFields() throws {
        var task = TodoItem(title: "事项", scheduledDay: try d("2026-11-02"), scheduledMinute: 540, categoryID: category)
        try ModelValidator.task(task, categories: [category])
        task.title = "  "; #expect(throws: (any Error).self) { try ModelValidator.task(task, categories: [category]) }
        task.title = "事项"; task.scheduledMinute = 1440; #expect(throws: (any Error).self) { try ModelValidator.task(task, categories: [category]) }
        task.scheduledMinute = 540; #expect(throws: (any Error).self) { try ModelValidator.task(task, categories: []) }
    }
    @Test func testLongTextAndEmojiCount() throws {
        try ModelValidator.title(String(repeating: "👨‍👩‍👧‍👦", count: 200))
        #expect(throws: (any Error).self) { try ModelValidator.title(String(repeating: "事", count: 201)) }
        #expect(throws: (any Error).self) { try ModelValidator.title("事项", notes: String(repeating: "a", count: 10001)) }
    }
    @Test func testWeeklyOccurrenceAndStableIdentity() throws {
        let value = try fixture()
        let first = try project(value), second = try project(value)
        #expect(try first.items.map(\.scheduledDay) == [d("2026-11-02"), d("2026-11-04")])
        #expect(first.items.map(\.id) == second.items.map(\.id))
        #expect(first.items[0].id != first.items[1].id)
    }
    @Test func testDailyCompletionOnlyHidesOneOccurrence() throws {
        var value = try fixture(); value.rules[0].frequency = .daily
        value.tasks = try project(value).missingInstances
        value.tasks[0].completedAt = Date()
        let result = try project(value)
        #expect(result.items.count == 6)
        #expect(result.totalCount == 7)
        #expect(result.completedCount == 1)
        #expect(result.missingInstances.isEmpty)
        #expect(try project(value, completed: true).items.count == 7)
    }
    @Test func testMovedOverrideDoesNotRegenerateOriginalDate() throws {
        var value = try fixture(); value.tasks = try project(value).missingInstances
        value.tasks[0].scheduledDay = try d("2026-11-03"); value.tasks[0].isOverride = true
        let result = try project(value)
        #expect(try result.items.map(\.scheduledDay) == [d("2026-11-03"), d("2026-11-04")])
        #expect(result.missingInstances.isEmpty)
        #expect(try project(value, start: "2026-11-02", days: 1).items.count == 0)
    }
    @Test func testMovedIntoRangeIsMerged() throws {
        var value = try fixture(); value.tasks = try project(value).missingInstances
        value.tasks[0].scheduledDay = try d("2026-11-10"); value.tasks[0].isOverride = true
        #expect(try project(value, start: "2026-11-10", days: 1).items.count == 1)
    }
    @Test func testDeletionMarkerSurvivesPurgedRow() throws {
        var value = try fixture()
        value.exclusions = [.init(seriesID: value.series[0].id, day: try d("2026-11-02"), reason: .userDeleted)]
        let result = try project(value)
        #expect(try result.items.map(\.scheduledDay) == [d("2026-11-04")])
    }
    @Test func testStopDoesNotEraseCompletedHistory() throws {
        var value = try fixture(); value.tasks = try project(value).missingInstances
        value.tasks[1].completedAt = Date()
        value.series[0].stoppedFromDay = try d("2026-11-02")
        let result = try project(value, completed: true)
        #expect(result.items.count == 1)
        #expect(result.items[0].completedAt != nil)
        #expect(result.missingInstances.isEmpty)
    }
    @Test func testLatestEndedRuleNeverFallsBackToOldVersion() throws {
        var value = try fixture()
        var rule = TodoSeriesRule(seriesID: value.series[0].id, from: try d("2026-11-03"), title: "新规则", minute: 600, categoryID: category, frequency: .daily)
        rule.endDay = try d("2026-11-04")
        value.rules.append(rule)
        #expect(try project(value).items.map(\.scheduledDay) == [d("2026-11-02"), d("2026-11-03"), d("2026-11-04")])
    }
    @Test func testInclusiveEndDateAndSupersededVersion() throws {
        var value = try fixture(); value.rules[0].endDay = try d("2026-11-02")
        #expect(try project(value).items.count == 1)
        value.rules[0].isSupersededForExpansion = true
        #expect(try project(value).items.isEmpty)
    }
    @Test func testInvalidWeeklyRuleWithNoOccurrences() throws {
        var value = try fixture(); value.rules[0].weekdays = []
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
        value.rules[0].weekdays = [7]; value.rules[0].endDay = try d("2026-11-03")
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
    }
    @Test func testFarFutureQueryIsBoundedToTargetMonth() throws {
        var value = try fixture(); value.rules[0].frequency = .daily
        let interval = try DayInterval.month(containing: d("2066-11-15"))
        let result = try AgendaCalculator.project(interval: interval, tasks: [], series: value.series, rules: value.rules, exclusions: [], now: Date())
        #expect(result.items.count == 30)
        #expect(try result.items.first?.scheduledDay == d("2066-11-01"))
    }
    @Test func testCountdownTodayPastAndOrdering() throws {
        let today = try d("2026-10-31")
        let future = CountdownEvent(title: "发布", targetDay: try d("2026-11-12"))
        let past = CountdownEvent(title: "昨天", targetDay: try d("2026-10-30"))
        let current = CountdownEvent(title: "今天", targetDay: today)
        #expect(future.days(from: today) == 12)
        #expect(current.label(from: today) == "就是今天")
        #expect(past.label(from: today) == "已过去 1 天")
        #expect(AgendaCalculator.countdowns([past, future, current], today: today).map(\.title) == ["今天", "发布", "昨天"])
    }
    @Test func testSnapshotRoundTripAndFutureVersionRejection() throws {
        var value = try fixture(); value.tasks = try project(value).missingInstances
        let encoded = try SnapshotCodec.encode(value)
        #expect(try SnapshotCodec.decode(encoded) == value)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 999
        #expect(throws: DomainError.unsupportedVersion) { try SnapshotCodec.decode(JSONSerialization.data(withJSONObject: object)) }
    }
    @Test func testSnapshotRejectsDuplicateKeysAndBrokenReferences() throws {
        var value = try fixture(); value.tasks = try project(value).missingInstances
        var duplicate = value.tasks[0]; duplicate.id = UUID(); value.tasks.append(duplicate)
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
        value.tasks.removeLast(); value.tasks[0].categoryID = UUID()
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
        value.tasks.removeAll(); value.rules[0].seriesID = UUID()
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
    }
    @Test func testCategoryDuplicateAndProtectedDefault() throws {
        var value = StoreSnapshot()
        value.categories.append(.init(name: " 学习 ", colorHex: "#123456"))
        #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
        value.categories = []; #expect(throws: (any Error).self) { try ModelValidator.snapshot(value) }
    }
    @Test func testChronologicalOrderPrecedesImportance() throws {
        let day = try d("2026-11-02")
        var early = TodoItem(title: "早", scheduledDay: day, scheduledMinute: 500, categoryID: category)
        var late = early; late.id = UUID(); late.title = "重要但晚"; late.scheduledMinute = 600; late.isImportant = true
        early.isImportant = false
        #expect(AgendaCalculator.taskOrder(early, late))
    }

    @Test func calendarWeekCrossesYearAndContainsAnchor() throws {
        let interval = try DayInterval.week(containing: LocalDate("2027-01-01"))
        #expect(interval.start.description == "2026-12-28")
        #expect(interval.endExclusive.description == "2027-01-04")
        #expect(interval.dates.count == 7)
        #expect(interval.dates.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
    }
    @Test func calendarWeekClipsOnlyAtSupportedMaximum() throws {
        let first = try DayInterval.week(containing: LocalDate("1900-01-01"))
        #expect(first.start.description == "1900-01-01")
        #expect(first.dates.count == 7)
        let last = try DayInterval.week(containing: LocalDate("9999-12-31"))
        #expect(last.endExclusive.description == "10000-01-01")
        #expect(last.dates.allSatisfy { $0.isUserSelectable })
        #expect(last.dates.last?.description == "9999-12-31")
    }

    @Test func reminderBudgetIsSharedAndOmitsInactiveAndPastRecords() throws {
        let clock = Date(timeIntervalSince1970: 1800000000)
        let day = try LocalDate("2027-01-15")
        let tasks = (0..<40).map { index in
            var task = TodoItem(title: "任务 \(index)", scheduledDay: day, scheduledMinute: 540, categoryID: TodoCategory.defaults[0].id)
            task.reminderAt = clock.addingTimeInterval(Double(index * 2 + 1)); return task
        }
        var events = (0..<30).map { index in
            var event = CountdownEvent(title: "事件 \(index)", targetDay: day)
            event.reminderAt = clock.addingTimeInterval(Double(index * 2 + 2)); return event
        }
        var archived = events[0]; archived.id = UUID(); archived.archivedAt = clock; events.append(archived)
        var past = events[0]; past.id = UUID(); past.reminderAt = clock; events.append(past)
        var completed = tasks[0]; completed.id = UUID(); completed.completedAt = clock
        var deleted = tasks[0]; deleted.id = UUID(); deleted.deletedAt = clock
        let plan = ReminderPlan(tasks: tasks + [completed, deleted], events: events, now: clock)
        #expect(plan.eligibleCount == 70)
        #expect(plan.requests.count == 48)
        #expect(plan.deferredCount == 22)
        #expect(plan.requests.filter { $0.id.hasPrefix("task-") }.count == 24)
        #expect(plan.requests.filter { $0.id.hasPrefix("countdown-") }.count == 24)
        #expect(plan.requests.last?.date == clock.addingTimeInterval(48))
    }
}
