import Testing
import TodoDomain

@Suite struct RecurrencePreviewTests {
    private func d(_ value: String) throws -> LocalDate { try LocalDate(value) }
    @Test func weeklyPreviewUsesSelectedDaysAndInclusiveEnd() throws {
        let days = try RecurrencePreview.dates(frequency: .weekly, weekdays: [1, 3], from: d("2026-11-03"), through: d("2026-11-09"))
        #expect(days == (try [d("2026-11-04"), d("2026-11-09")]))
        #expect(RecurrencePreview.summary(frequency: .weekly, weekdays: [3, 1], minute: 540, category: "学习") == "每周一、三 09:00 · 学习")
    }
    @Test func upperYearCannotProduceUnsupportedDates() throws {
        #expect(try RecurrencePreview.dates(frequency: .daily, weekdays: [], from: d("9999-12-30")) == [d("9999-12-30"), d("9999-12-31")])
        #expect(throws: DomainError.invalidRecurrence) { try RecurrencePreview.dates(frequency: .weekly, weekdays: [], from: d("2026-11-02")) }
        #expect(throws: DomainError.invalidRecurrence) { try RecurrencePreview.dates(frequency: .daily, weekdays: [], from: d("2026-11-03"), through: d("2026-11-02")) }
        #expect(throws: DomainError.invalidRecurrence) { try RecurrencePreview.dates(frequency: .daily, weekdays: [], from: d("2026-11-02"), limit: 1000) }
    }
    @Test func copiedDraftHasNoOldIdentityStopOrEnd() throws {
        var rule = TodoSeriesRule(seriesID: .init(), from: try d("2020-01-01"), title: "阅读", minute: 480, categoryID: TodoCategory.defaults[2].id, frequency: .weekly, weekdays: [1, 3])
        rule.endDay = try d("2020-12-31"); rule.reminderOffsetMinutes = 15; rule.notes = "保留内容"
        let copied = TaskDraft(copying: rule, starting: try d("2026-11-02"))
        #expect(copied.baseRevision == 0 && copied.seriesRevision == nil && copied.effectiveFromDay == nil && copied.endDay == nil)
        #expect(copied.title == rule.title && copied.weekdays == rule.weekdays && copied.notes == rule.notes)
        #expect(copied.reminderAt == nil && copied.reminderOffsetMinutes == 15)
    }
}
