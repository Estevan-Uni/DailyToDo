import SwiftUI
import TodoDomain

/// A window owns its draft. Refreshing shared records never replaces typed text.
@MainActor @Observable
final class EditorSession: Identifiable {
    enum Kind { case task, countdown }
    enum Field: Hashable { case title, date, time, category, recurrence, notes, reminder, recovery }
    let id = UUID()
    let kind: Kind
    let clock: AppClock
    var task: TaskDraft
    var countdown: CountdownDraft
    var dayText: String
    var timeText: String
    var endText: String
    var reminderEnabled = false
    var reminderDate: Date
    var error: String?
    var isSaving = false
    var isConflict = false
    var recordUnavailable = false
    var validationField: Field?
    var validationRequest = 0
    var wasRecurring: Bool
    var wasCompleted: Bool
    var completedAt: Date?
    var showDatePicker = false
    var focusTitleOnOpen = true
    var copySourceName: String?
    var adjustReminderWithSchedule = false
    private var reminderOrigin: ReminderRescheduling?
    private struct DraftState: Equatable {
        var task: TaskDraft; var countdown: CountdownDraft
        var day: String; var time: String; var end: String; var reminder: Date?; var adjustReminder: Bool
    }
    private var baseline: DraftState?

    init(day: LocalDate, kind: Kind = .task, clock: AppClock = .system) {
        self.clock = clock; reminderDate = clock.now().addingTimeInterval(3600)
        self.kind = kind; task = TaskDraft(day: day); countdown = CountdownDraft(day: day)
        dayText = day.description; timeText = ""; endText = ""
        wasRecurring = false; wasCompleted = false
        baseline = signature
    }
    init(item: TodoItem, configuration: StoreSnapshot, clock: AppClock = .system) {
        self.clock = clock
        kind = .task
        let rule = configuration.rules.first { $0.id == item.ruleVersionID }
        let series = configuration.series.first { $0.id == item.seriesID }
        task = TaskDraft(task: item, rule: rule, series: series)
        countdown = CountdownDraft(day: item.scheduledDay)
        dayText = item.scheduledDay.description; timeText = item.timeLabel
        endText = rule?.endDay?.description ?? ""
        reminderEnabled = item.reminderAt != nil; reminderDate = item.reminderAt ?? clock.now().addingTimeInterval(3600)
        wasRecurring = item.seriesID != nil; wasCompleted = item.completedAt != nil
        completedAt = item.completedAt
        if item.hasScheduledTime, let reminder = item.reminderAt { reminderOrigin = .init(day: item.scheduledDay, minute: item.scheduledMinute, reminderAt: reminder) }
        baseline = signature
    }
    init(event: CountdownEvent, clock: AppClock = .system) {
        self.clock = clock
        kind = .countdown; task = TaskDraft(day: event.targetDay); countdown = CountdownDraft(event: event)
        dayText = event.targetDay.description; timeText = ""; endText = ""
        reminderEnabled = event.reminderAt != nil; reminderDate = event.reminderAt ?? clock.now().addingTimeInterval(3600)
        wasRecurring = false; wasCompleted = false
        baseline = signature
    }
    init(copying rule: TodoSeriesRule, today: LocalDate, clock: AppClock = .system) {
        self.clock = clock; reminderDate = clock.now().addingTimeInterval(3600)
        kind = .task; task = TaskDraft(copying: rule, starting: today); countdown = CountdownDraft(day: today)
        dayText = ""; timeText = ScheduledTime.label(rule.minute); endText = ""
        wasRecurring = false; wasCompleted = false; copySourceName = rule.title; showDatePicker = true; focusTitleOnOpen = false
        baseline = signature
    }
    var title: String { kind == .task ? (task.baseRevision == 0 ? "新建待办" : "编辑待办") : (countdown.baseRevision == 0 ? "新建倒计时" : "编辑倒计时") }
    var isNew: Bool { kind == .task ? task.baseRevision == 0 : countdown.baseRevision == 0 }
    /// A continuous-entry draft carries only visible scheduling defaults, never
    /// content, reminders, completion or a repeating rule from the saved item.
    func nextEntry() -> EditorSession {
        let next = EditorSession(day: kind == .task ? task.day : countdown.day, kind: kind, clock: clock)
        if kind == .task {
            next.task.categoryID = task.categoryID; next.task.minute = task.minute
            next.timeText = timeText
        }
        next.baseline = next.signature
        return next
    }
    var dirty: Bool { signature != baseline }
    func requestDateSelection() { showDatePicker = true; focusTitleOnOpen = false }
    private var signature: DraftState {
        .init(task: task, countdown: countdown, day: dayText, time: timeText, end: endText, reminder: reminderEnabled ? reminderDate : nil, adjustReminder: adjustReminderWithSchedule && isChangingReminderSchedule)
    }
    var isChangingReminderSchedule: Bool {
        guard kind == .task, task.baseRevision > 0, reminderEnabled,
              task.frequency == nil || (wasRecurring && task.scope == .onlyThis),
              let origin = reminderOrigin, let day = try? LocalDate(dayText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let minute = try? Self.minute(timeText), ScheduledTime.hasTime(minute) else { return false }
        return day != origin.day || minute != origin.minute
    }
    var reminderRescheduleProposal: Date? {
        guard isChangingReminderSchedule, let origin = reminderOrigin,
              let day = try? LocalDate(dayText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let minute = try? Self.minute(timeText) else { return nil }
        return try? origin.proposed(day: day, minute: minute, timeZone: clock.timeZone())
    }
    static func minute(_ text: String) throws -> Int {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return ScheduledTime.unspecified }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else { throw DomainError.invalidTime }
        return hour * 60 + minute
    }
    /// Only a manual change to a civil plan needs another confirmation. Ordinary
    /// content edits do not repeatedly ask about an already saved occurrence.
    func manualTimeConfirmation() throws -> LocalTimeResolution? {
        guard kind == .task, task.frequency == nil || (wasRecurring && task.scope == .onlyThis),
              let minute = task.minute, ScheduledTime.hasTime(minute) else { return nil }
        let resolution = try task.day.resolveTime(minute: minute, timeZone: clock.timeZone())
        guard resolution.kind != .exact,
              task.baseRevision == 0 || baseline?.task.day != task.day || baseline?.task.minute != minute else { return nil }
        return resolution
    }
    func recurrencePreview(today: LocalDate) throws -> (minute: Int, days: [LocalDate])? {
        guard kind == .task, let frequency = task.frequency, !wasCompleted, !wasRecurring || task.scope == .thisAndFollowing else { return nil }
        let start = wasRecurring ? task.effectiveFromDay! : try LocalDate(dayText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard start >= today else { throw DomainError.invalidRecurrence }
        let minute = try Self.minute(timeText)
        let end = endText.isEmpty ? nil : try LocalDate(endText)
        let days = try RecurrencePreview.dates(frequency: frequency, weekdays: task.weekdays, from: start, through: end)
        guard !days.isEmpty else { throw DomainError.invalidRecurrence }
        return (minute, days)
    }
    func prepare() throws {
        validationField = .date
        let day = try LocalDate(dayText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard day.isUserSelectable else { throw DomainError.invalidDate }
        if kind == .task {
            validationField = .title
            try ModelValidator.title(task.title, notes: task.notes)
            validationField = .category
            guard task.categoryID != nil else { throw DomainError.missingCategory }
            validationField = .time
            task.day = day; task.minute = try Self.minute(timeText)
            validationField = .recurrence
            task.endDay = endText.isEmpty ? nil : try LocalDate(endText)
            if task.frequency != nil, !(wasRecurring && task.scope == .onlyThis), task.reminderOffsetMinutes != nil,
               !ScheduledTime.hasTime(task.minute ?? ScheduledTime.unspecified) { throw DomainError.recurringReminderNeedsTime }
            validationField = .reminder
            if reminderEnabled, adjustReminderWithSchedule, isChangingReminderSchedule {
                guard let proposal = reminderRescheduleProposal else { throw DomainError.invalidReminder }
                task.reminderAt = proposal
            } else { task.reminderAt = reminderEnabled ? reminderDate : nil }
        } else {
            validationField = .title
            try ModelValidator.title(countdown.title, notes: countdown.notes)
            countdown.day = day; countdown.reminderAt = reminderEnabled ? reminderDate : nil
        }
        validationField = nil
    }
    func copyAsNew() {
        task.id = UUID(); task.baseRevision = 0; task.seriesRevision = nil; task.effectiveFromDay = nil; task.scope = .onlyThis
        task.frequency = nil; task.weekdays = []; task.reminderOffsetMinutes = nil
        wasRecurring = false; wasCompleted = false
        countdown.id = UUID(); countdown.baseRevision = 0
        completedAt = nil
        copySourceName = nil
        reminderOrigin = nil; adjustReminderWithSchedule = false
        isConflict = false; recordUnavailable = false; error = nil; validationField = nil
    }
    func useTargetMorningReminder() throws {
        let day = try LocalDate(dayText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard day.isUserSelectable else { throw DomainError.invalidDate }
        let instant = try day.instant(minute: 9 * 60, timeZone: clock.timeZone())
        guard instant > clock.now() else { throw DomainError.invalidReminder }
        reminderDate = instant; error = nil
    }
    func didSave() {
        copySourceName = nil; adjustReminderWithSchedule = false
        let reminder = kind == .task ? task.reminderAt : countdown.reminderAt
        reminderEnabled = reminder != nil
        if let reminder { reminderDate = reminder }
        if kind == .task, let minute = task.minute, ScheduledTime.hasTime(minute), let reminder {
            reminderOrigin = .init(day: task.day, minute: minute, reminderAt: reminder)
        } else { reminderOrigin = nil }
        baseline = signature; error = nil; isConflict = false; recordUnavailable = false; validationField = nil
    }
}
