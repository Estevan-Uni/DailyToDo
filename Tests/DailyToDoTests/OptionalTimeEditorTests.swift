import Foundation
import Testing
import TodoDomain
@testable import DailyToDo

@Suite @MainActor struct OptionalTimeEditorTests {
    private var day: LocalDate { try! LocalDate("2026-11-02") }
    private var category: UUID { TodoCategory.defaults[0].id }
    @Test func blankTimePreparesWithoutInventingMidnightAndMalformedTimeFails() throws {
        let editor = EditorSession(day: day); editor.task.title = "日期待办"; editor.task.categoryID = category
        try editor.prepare()
        #expect(editor.task.minute == ScheduledTime.unspecified)
        #expect(try editor.manualTimeConfirmation() == nil)
        editor.didSave()
        let next = editor.nextEntry()
        #expect(next.timeText.isEmpty && next.task.categoryID == category && !next.dirty)
        editor.timeText = "18:99"
        #expect(throws: DomainError.invalidTime) { try editor.prepare() }
        #expect(editor.task.title == "日期待办")
        editor.timeText = "00:00"; try editor.prepare(); #expect(editor.task.minute == 0)
        editor.timeText = "  \n"; try editor.prepare(); #expect(editor.task.minute == ScheduledTime.unspecified)
    }
    @Test func clearingTimePreservesAbsoluteReminderAndCanBeReopened() throws {
        var item = TodoItem(title: "保留提醒", scheduledDay: day, scheduledMinute: 600, categoryID: category)
        item.reminderAt = Date(timeIntervalSince1970: 1_800_000_000)
        var config = StoreSnapshot(); config.categories = TodoCategory.defaults
        let editor = EditorSession(item: item, configuration: config)
        editor.timeText = ""; editor.dayText = try day.adding(days: 1).description; editor.adjustReminderWithSchedule = true
        #expect(!editor.isChangingReminderSchedule && editor.reminderRescheduleProposal == nil)
        try editor.prepare()
        #expect(editor.task.reminderAt == item.reminderAt && editor.task.minute == ScheduledTime.unspecified)
        item.scheduledMinute = ScheduledTime.unspecified
        let reopened = EditorSession(item: item, configuration: config)
        #expect(reopened.timeText.isEmpty && reopened.reminderEnabled && !reopened.dirty)
    }
    @Test func untimedRecurrencePreviewAndCopyWorkAndReminderErrorKeepsDraft() throws {
        let editor = EditorSession(day: day); editor.task.title = "固定日期待办"; editor.task.categoryID = category; editor.task.frequency = .daily
        let preview = try #require(try editor.recurrencePreview(today: day))
        #expect(preview.minute == ScheduledTime.unspecified && preview.days.count == 3)
        try editor.prepare()
        editor.task.reminderOffsetMinutes = 0
        #expect(throws: DomainError.recurringReminderNeedsTime) { try editor.prepare() }
        #expect(editor.task.title == "固定日期待办" && editor.timeText.isEmpty)
        let rule = TodoSeriesRule(seriesID: UUID(), from: day, title: "复制", minute: ScheduledTime.unspecified, categoryID: category, frequency: .daily)
        let copy = EditorSession(copying: rule, today: day)
        #expect(copy.timeText.isEmpty && copy.task.minute == nil && !copy.dirty)
    }
}
