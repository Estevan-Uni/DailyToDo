import AppKit
import Observation
import SwiftUI
import TodoDomain
import TodoPersistence
import TodoServices

enum AppSection: String, CaseIterable, Identifiable {
    case schedule = "日程", countdowns = "倒计时"
    var id: String { rawValue }
    var symbol: String {
        self == .schedule ? "calendar" : "hourglass"
    }
}

enum ScheduleScale: String, CaseIterable, Identifiable {
    case week = "周", month = "月"
    var id: String { rawValue }
}
enum CompletionFilter: String, CaseIterable, Identifiable {
    case all = "全部", open = "未完成", done = "已完成"
    var id: String { rawValue }
}

@MainActor @Observable
final class AppModel {
    var repository: TodoRepository?
    var configuration = StoreSnapshot()
    var section: AppSection = .schedule
    var scheduleScale: ScheduleScale = .month
    var categoryFilter: UUID?
    var completionFilter: CompletionFilter = .all
    let clock: AppClock
    var selectedDay: LocalDate
    var today: LocalDate
    var clockNow: Date
    var displayTimeZone: TimeZone
    var cardIndex = 0
    var cardVisible = false
    var cardPositionIssue: String?
    var cardEditing = false
    var cardTaskAnchors: [LocalDate: UUID] = [:]
    var cardCountdownAnchor: UUID?
    var mainItems: [TodoItem] = []
    var cardItems: [TodoItem] = []
    var cardCompletedDays: Set<LocalDate> = []
    var events: [CountdownEvent] = []
    var archivedEvents: [CountdownEvent] = []
    var search = ""
    var mainEditor: EditorSession?
    var error: String?
    var loadFailure: String?
    var isLoading = true
    var showWelcome = false
    var status = "" { didSet { statusDismissTask?.cancel() } }
    @ObservationIgnored private var statusDismissTask: Task<Void, Never>?
    var undoStack: [UndoAction] = []
    var cardController: DesktopCardController?
    var bootStarted = false
    var backgroundLaunch = false
    var mainWindowRequested = false
    var isBusy = false
    var busyMessage = "正在处理本机数据…"
    private var pendingWrites = 0
    var hasPendingWrites: Bool { pendingWrites > 0 }
    var themeColorHex = UserDefaults.standard.string(forKey: "themeColorHex") ?? "#4B8E83" {
        didSet { UserDefaults.standard.set(themeColorHex, forKey: "themeColorHex") }
    }
    let services: SystemServices
    private var scheduler: RefreshScheduler?
    var showMainAction: (() -> Void)?
    var showSettingsAction: (() -> Void)?
    var searchRequest = 0
    var textEditingRevision = 0
    private var textMonitor: TextEditingMonitor?
    private var refreshID = 0
    private(set) var storageURL: URL
    private var startupFailure: String?
    private let confirmLeaving: @MainActor (EditorSession) -> EditorLeaveChoice

    init(clock: AppClock = .system, services: SystemServices? = nil, storageURL injectedStorageURL: URL? = nil,
         confirmLeaving: @escaping @MainActor (EditorSession) -> EditorLeaveChoice = EditorLeaveConfirmation.ask) {
        self.clock = clock; self.services = services ?? SystemServices(clock: clock)
        self.confirmLeaving = confirmLeaving
        let initialNow = clock.now(), initialDay = clock.day(at: initialNow)
        clockNow = initialNow; today = initialDay; selectedDay = initialDay; displayTimeZone = clock.timeZone()
        if let injectedStorageURL { storageURL = injectedStorageURL; return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let rawTestID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test=") })?.dropFirst(10)
        let testID = rawTestID.map { String($0.prefix(100).map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }) }
        let folder = testID.map { "TodoDesktop-UITests/\($0)" } ?? "TodoDesktop"
        let directory = support.appendingPathComponent(folder, isDirectory: true)
        storageURL = directory.appendingPathComponent("TodoDesktop.sqlite")
        do { storageURL = try StoreLocation.resolve(in: directory) }
        catch { startupFailure = error.localizedDescription }
    }
    var categories: [TodoCategory] { configuration.categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    var cardDays: [LocalDate] { (0..<7).compactMap { try? today.adding(days: $0) }.filter(\.isUserSelectable) }
    var cardDay: LocalDate { cardDays.indices.contains(cardIndex) ? cardDays[cardIndex] : today }
    var visibleMainItems: [TodoItem] {
        mainItems.filter { item in
            (search.isEmpty || item.title.localizedStandardContains(search) || item.notes.localizedStandardContains(search)) &&
            (categoryFilter == nil || item.categoryID == categoryFilter) &&
            (completionFilter == .all || (completionFilter == .done) == (item.completedAt != nil))
        }
    }
    var visibleEvents: [CountdownEvent] { search.isEmpty ? events : events.filter { $0.title.localizedStandardContains(search) || $0.notes.localizedStandardContains(search) } }
    func category(_ id: UUID) -> TodoCategory? { categories.first { $0.id == id } }
    func hasPassed(_ item: TodoItem) -> Bool { AgendaClock.hasPassed(item, now: clockNow, timeZone: displayTimeZone) }
    func repeatLabel(_ item: TodoItem) -> String {
        guard let rule = configuration.rules.first(where: { $0.id == item.ruleVersionID }) else { return "重复" }
        return rule.frequency == .daily ? "每日" : "每周"
    }
    func showTodayAgenda() async {
        showMainAction?()
        await navigate(.schedule)
        guard section == .schedule else { return }
        selectedDay = today; categoryFilter = nil; completionFilter = .all; search = ""
        await refresh()
    }
    var rangeLabel: String {
        guard section == .schedule else { return "本机保存" }
        if scheduleScale == .month { return "\(selectedDay.year) 年 \(selectedDay.month) 月" }
        guard let interval = try? scheduleInterval else { return selectedDay.description }
        return "\(interval.start) — \((try? interval.endExclusive.adding(days: -1))?.description ?? "")"
    }
    var scheduleInterval: DayInterval {
        get throws { try scheduleScale == .week ? .week(containing: selectedDay) : .month(containing: selectedDay) }
    }
    func shiftSchedule(_ direction: Int) async {
        do {
            if scheduleScale == .week { selectedDay = try selectedDay.adding(days: direction * 7) }
            else {
                let calendar = clock.calendar
                guard let date = calendar.date(byAdding: .month, value: direction, to: selectedDay.noon(timeZone: clock.timeZone())) else { throw DomainError.invalidDate }
                let candidate = clock.day(at: date); guard candidate.isUserSelectable else { throw DomainError.invalidDate }; selectedDay = candidate
            }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func boot() async {
        guard !bootStarted else { return }; bootStarted = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--ui-test=") }) {
            if arguments.contains("--ui-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            else if arguments.contains("--ui-light") { NSApp.appearance = NSAppearance(named: .aqua) }
        }
        if let startupFailure { loadFailure = startupFailure; isLoading = false; return }
        do {
            let url = storageURL, clock = self.clock
            repository = try await Task.detached { try TodoRepository(url: url, now: clock.now, timeZone: clock.timeZone) }.value
            if ProcessInfo.processInfo.arguments.contains("--ui-demo"),
               ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test=") }), let repository {
                let snapshot = try SnapshotCodec.decode(await repository.exportData())
                if snapshot.tasks.isEmpty && snapshot.series.isEmpty && snapshot.countdowns.isEmpty {
                    try await repository.restoreData(SnapshotCodec.encode(DemoData.snapshot(today: today, stress: ProcessInfo.processInfo.arguments.contains("--ui-stress"))))
                }
            }
            await maintainAndRefresh()
            startPresentation()
        } catch { loadFailure = "无法打开本机数据，原文件已保留。\n\(error.localizedDescription)\n\(storageURL.path)" }
        isLoading = false
    }
    private func startPresentation() {
        textMonitor = TextEditingMonitor(model: self)
        scheduler = RefreshScheduler(model: self)
        cardController = DesktopCardController(model: self)
        if UserDefaults.standard.object(forKey: "showCard") == nil || UserDefaults.standard.bool(forKey: "showCard") { cardController?.show(activate: false) }
        showWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    }
    func finishWelcome() { UserDefaults.standard.set(true, forKey: "hasSeenWelcome"); showWelcome = false }
    /// Invoked only by an explicit reminder control change, never by opening or
    /// initializing an editor. Existing global enablement needs no new prompt.
    func requestRemindersFromEditor() async {
        guard !services.notificationsEnabled else { return }
        await services.setNotifications(true, repository: repository)
    }
    func retryStorage() async {
        guard repository == nil, !isBusy else { return }
        do {
            storageURL = try StoreLocation.resolve(in: storageURL.deletingLastPathComponent())
            startupFailure = nil; loadFailure = nil; bootStarted = false; isLoading = true
            await boot()
        } catch { loadFailure = error.localizedDescription }
    }
    func recoverStorage(fromBackup: Bool) async {
        guard repository == nil, !isBusy else { return }
        NSApp.activate(ignoringOtherApps: true)
        isBusy = true; busyMessage = "正在校验恢复文件…"; defer { isBusy = false }
        var selectedURL: URL?
        if fromBackup {
            guard let url = await FileDialogs.openJSON() else { return }; selectedURL = url
        }
        do {
            let directory = storageURL.deletingLastPathComponent()
            let backupURL = selectedURL
            let scoped = backupURL?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { backupURL?.stopAccessingSecurityScopedResource() } }
            let input = try await Task.detached {
                let data: Data
                if let backupURL {
                    let size = try backupURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= 100 * 1024 * 1024 else { throw DomainError.invalidSnapshot("文件超过 100 MiB") }
                    data = try Data(contentsOf: backupURL)
                } else { data = try SnapshotCodec.encode(StoreSnapshot()) }
                return (data, try SnapshotCodec.decode(data))
            }.value
            let snapshot = input.1
            let alert = NSAlert(); alert.messageText = fromBackup ? "从备份恢复到独立新库？" : "创建独立的空白数据？"
            let summary = fromBackup ? "已校验：\(snapshot.tasks.count) 条待办、\(snapshot.series.count) 条重复规则、\(snapshot.countdowns.count) 个倒计时、\(snapshot.categories.count) 个类型。\n" : ""
            alert.informativeText = summary + "原数据库和文件都会保留。成功后将使用新库，您可继续找回原数据。"
            alert.addButton(withTitle: fromBackup ? "恢复到新库" : "创建新库"); alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            busyMessage = "正在恢复到独立新库…"
            let data = input.0
            let clock = self.clock
            let result = try await Task.detached { try await StoreRecovery.create(from: data, in: directory, clock: clock) }.value
            storageURL = result.url; repository = result.repository
            loadFailure = nil; startupFailure = nil; isBusy = false
            await maintainAndRefresh(); startPresentation(); status = "已切换到恢复后的新库，原文件保留在数据目录。"
            if let warning = services.queueFailureWarning { status += "；\(warning)" }
        } catch { self.error = "恢复未完成，原文件未更改：\(error.localizedDescription)" }
    }
    func maintainAndRefresh() async {
        guard let repository, !isBusy else { return }
        let currentToday = clock.today
        if currentToday != today, selectedDay == today, mainEditor == nil { selectedDay = currentToday }
        do {
            let count = try await repository.rolloverUnfinishedSingles()
            guard !isBusy else { return }
            if count > 0 { status = "已自动顺延 \(count) 项未完成待办到今天" }
            try await repository.purgeExpiredTrash()
        } catch { self.error = error.localizedDescription }
        await refresh()
    }
    func refresh() async {
        guard let repository, !isBusy else { return }
        refreshID += 1; let request = refreshID
        let currentSection = section, day = selectedDay
        let currentToday = clock.today
        do {
            let config = try await repository.configuration()
            guard !isBusy, request == refreshID else { return }
            let last = try LocalDate(year: 9999, month: 12, day: 31)
            let cardCount = min(7, currentToday.distance(to: last) + 1)
            let card = try await repository.agenda(.days(from: currentToday, count: cardCount), includeCompleted: true)
            guard !isBusy, request == refreshID else { return }
            let activeEvents = try await repository.countdowns()
            let archived = try await repository.countdowns(archived: true)
            guard !isBusy, request == refreshID else { return }
            var items: [TodoItem] = []
            if currentSection == .schedule {
                let interval = try scheduleScale == .week ? DayInterval.week(containing: day) : .month(containing: day)
                items = try await repository.agenda(interval, includeCompleted: true).items
            }
            guard !isBusy, request == refreshID, currentSection == section else { return }
            let oldCardDay = cardDay, followsToday = cardIndex == 0
            configuration = config; today = currentToday; displayTimeZone = clock.timeZone()
            cardIndex = followsToday ? 0 : min(max(0, currentToday.distance(to: oldCardDay)), max(0, cardDays.count - 1))
            cardCompletedDays = Set(card.items.filter { $0.completedAt != nil }.map(\.scheduledDay))
            cardItems = card.items.filter { $0.completedAt == nil }; events = activeEvents; archivedEvents = archived
            mainItems = items
            // Completion is read-only metadata. Refresh it without replacing
            // typed fields, the draft baseline or its conflict revision.
            let taskEditors = [mainEditor, cardController?.editor].compactMap({ $0 }).filter { $0.kind == .task }
            if !taskEditors.isEmpty {
                let latestTasks = Dictionary((card.items + items).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                for editor in taskEditors {
                    if let latest = latestTasks[editor.task.id] { editor.completedAt = latest.completedAt }
                }
            }
            scheduler?.rescheduleStatus()
            await services.reconcile(repository)
        } catch { self.error = error.localizedDescription }
    }
    func save(_ editor: EditorSession) async -> Bool {
        guard let repository, !editor.isSaving, !isBusy else { return false }
        pendingWrites += 1
        editor.isSaving = true; defer { editor.isSaving = false; pendingWrites -= 1 }
        do {
            try editor.prepare()
            if let resolution = try editor.manualTimeConfirmation() {
                guard LocalTimeConfirmation.confirm(resolution) else { return false }
                guard try resolution.day.resolveTime(minute: resolution.requestedMinute, timeZone: clock.timeZone()) == resolution else { throw DomainError.conflict }
            }
            var suppressedByRule = false
            if editor.kind == .task {
                var reviewed: SeriesReview?
                if editor.wasRecurring && editor.task.scope == .thisAndFollowing && editor.dirty {
                    guard let old = try await repository.task(id: editor.task.id), let id = old.seriesID, let from = old.occurrenceDay else { throw DomainError.notFound }
                    let change: SeriesChange = editor.task.frequency == nil ? .detach(selectedID: old.id) : .update(selectedID: old.id)
                    let review = try await repository.reviewSeries(id: id, from: from, change: change)
                    guard SeriesConfirmation.confirm(review) else { return false }
                    reviewed = review
                }
                let result = try await repository.saveTask(editor.task, reviewed: reviewed)
                suppressedByRule = result.task.isRuleSuppressed
                pushUndo(result.undo)
                editor.task = TaskDraft(task: result.task, rule: configuration.rules.first { $0.id == result.task.ruleVersionID }, series: configuration.series.first { $0.id == result.task.seriesID })
                editor.dayText = result.task.scheduledDay.description
                if mainEditor === editor { selectedDay = result.task.scheduledDay }
            } else {
                let result = try await repository.saveCountdownWithUndo(editor.countdown)
                let saved = result.event; pushUndo(result.undo)
                editor.countdown = CountdownDraft(event: saved)
            }
            await refresh()
            if suppressedByRule {
                editor.didSave()
                if mainEditor === editor { mainEditor = nil }
                status = "规则已更新；原发生日不匹配新规则，本次已隐藏。"
                return true
            }
            // Configuration may have gained a new series/rule during this save.
            if editor.kind == .task, let saved = try await repository.task(id: editor.task.id) {
                editor.task = TaskDraft(task: saved, rule: configuration.rules.first { $0.id == saved.ruleVersionID }, series: configuration.series.first { $0.id == saved.seriesID })
                editor.wasRecurring = saved.seriesID != nil; editor.wasCompleted = saved.completedAt != nil
                editor.completedAt = saved.completedAt
                editor.endText = editor.task.endDay?.description ?? ""
            }
            editor.didSave(); status = "已保存"
            if cardController?.editor === editor {
                if editor.kind == .task {
                    if cardDays.contains(editor.task.day) {
                        cardIndex = today.distance(to: editor.task.day)
                        cardTaskAnchors[editor.task.day] = editor.task.id
                    } else { status = "已移至 \(editor.task.day)，可在 App 日历查看" }
                } else { cardCountdownAnchor = editor.countdown.id }
            }
            let wantsReminder = editor.kind == .task ? editor.task.reminderAt != nil || editor.task.reminderOffsetMinutes != nil : editor.countdown.reminderAt != nil
            if wantsReminder, let warning = services.savedReminderWarning { status += "；\(warning)" }
            return true
        } catch {
            editor.error = error.localizedDescription; editor.isConflict = (error as? DomainError) == .conflict
            switch error as? DomainError {
            case .emptyTitle, .titleTooLong: editor.validationField = .title
            case .notesTooLong: editor.validationField = .notes
            case .invalidTime, .unavailableLocalTime, .recurringReminderNeedsTime: editor.validationField = .time
            case .missingCategory: editor.validationField = .category
            case .invalidRecurrence: editor.validationField = .recurrence
            case .invalidReminder: editor.validationField = .reminder
            default: break
            }
            if (error as? DomainError) == .notFound {
                editor.recordUnavailable = true; editor.error = "原记录已删除或不再可编辑，草稿已保留。"
            }
            editor.validationRequest += 1
            return false
        }
    }
    func permitLeaving(_ editor: EditorSession?) async -> Bool {
        guard let editor, editor.dirty else { return true }
        switch confirmLeaving(editor) {
        case .save: return await save(editor)
        case .discard: return true
        case .continueEditing: return false
        }
    }
    func saveAndContinue(_ editor: EditorSession) async {
        guard editor.isNew, await save(editor) else { return }
        let next = editor.nextEntry()
        if mainEditor === editor { mainEditor = next }
        else if cardController?.editor === editor { cardController?.replaceEditor(next) }
    }
    func navigate(_ next: AppSection) async {
        guard !isBusy, next != section, await permitLeaving(mainEditor) else { return }
        mainEditor = nil; section = next; search = ""; await refresh()
    }
    func edit(_ item: TodoItem, onCard: Bool = false, showDatePicker: Bool = false) async {
        guard repository != nil, !isBusy else { return }
        if onCard {
            let editor = EditorSession(item: item, configuration: configuration, clock: clock); if showDatePicker { editor.requestDateSelection() }
            await cardController?.edit(editor); return
        }
        guard await permitLeaving(mainEditor) else { return }
        do {
            guard let latest = try await repository?.task(id: item.id), latest.deletedAt == nil, !latest.isRuleSuppressed else { throw DomainError.notFound }
            let editor = EditorSession(item: latest, configuration: configuration, clock: clock); if showDatePicker { editor.requestDateSelection() }
            mainEditor = editor
        } catch { self.error = error.localizedDescription }
    }
    func edit(_ event: CountdownEvent, onCard: Bool = false) async {
        guard let repository, !isBusy else { return }
        if onCard { await cardController?.edit(EditorSession(event: event, clock: clock)); return }
        guard await permitLeaving(mainEditor) else { return }
        do {
            guard let latest = try await repository.countdown(id: event.id), latest.deletedAt == nil else { throw DomainError.notFound }
            mainEditor = EditorSession(event: latest, clock: clock)
        } catch { self.error = error.localizedDescription }
    }
    func create(kind: EditorSession.Kind = .task, onCard: Bool = false) async {
        guard repository != nil, !isBusy else { return }
        let editor = EditorSession(day: onCard ? cardDay : section == .schedule ? selectedDay : today, kind: kind, clock: clock)
        if onCard { await cardController?.edit(editor) }
        else if await permitLeaving(mainEditor) { mainEditor = editor }
    }
    func create(on day: LocalDate) async {
        guard repository != nil, !isBusy, await permitLeaving(mainEditor) else { return }
        mainEditor = EditorSession(day: day, clock: clock)
    }
    func toggle(_ item: TodoItem) async {
        let completed = item.completedAt == nil
        let probe = GUIInteractionProbe.begin(completed: completed, model: self)
        await perform { repo in
            self.pushUndo(try await repo.setCompletion(id: item.id, completed: item.completedAt == nil))
            self.showCompletionStatus(item.completedAt == nil ? "已完成" : "已取消完成")
        }
        if let probe {
            let inCardRange = cardDays.contains(item.scheduledDay)
            let cardMatches = !inCardRange || cardItems.contains(where: { $0.id == item.id }) != completed
            let mainMatches = (try? scheduleInterval.contains(item.scheduledDay)) != true || section != .schedule || mainItems.contains { $0.id == item.id && ($0.completedAt != nil) == completed }
            await GUIInteractionProbe.finish(probe, model: self, stateVerified: cardMatches && mainMatches)
        }
    }
    func quickEdit(_ item: TodoItem, change: TaskQuickChange) async {
        guard !isBusy, await permitChangingRecord(item.id, kind: .task) else { return }
        await perform { repo in
            // A draft may have been saved by the leave prompt. Read that
            // revision and patch only the requested field; never reuse its old
            // title/time/category. A concurrent write still fails the check.
            guard let latest = try await repo.task(id: item.id) else { throw DomainError.notFound }
            let result = try await repo.quickEditTask(id: latest.id, baseRevision: latest.revision, change: change)
            self.pushUndo(result.undo)
            self.closeEditors(for: item.id, kind: .task)
            switch change {
            case .moveToTomorrow: self.status = "已移到明天（\(result.task.scheduledDay)）"
            case .setImportant(let value): self.status = value ? "已标为重要" : "已取消重要标记"
            }
        }
    }
    func delete(_ item: TodoItem) async {
        guard await permitChangingRecord(item.id, kind: .task) else { return }
        await perform { repo in
            self.pushUndo(try await repo.deleteTask(id: item.id)); self.status = "已移到最近删除"
            self.closeEditors(for: item.id, kind: .task)
        }
    }
    func stopFollowing(_ item: TodoItem) async {
        guard let seriesID = item.seriesID, let origin = item.occurrenceDay,
              origin >= today, item.completedAt == nil else { return }
        await stopSeries(seriesID, from: origin)
    }
    func stopSeries(_ id: UUID, from day: LocalDate) async {
        guard !isBusy, let repository else { return }
        do {
            // A series stop may hide a record currently being edited elsewhere.
            for editor in [mainEditor, cardController?.editor].compactMap({ $0 }) where editor.kind == .task {
                if let current = try await repository.task(id: editor.task.id), current.seriesID == id,
                   current.completedAt == nil, let origin = current.occurrenceDay, origin >= day,
                   !(await permitLeaving(editor)) { return }
            }
            let review = try await repository.reviewSeries(id: id, from: day, change: .stop)
            guard SeriesConfirmation.confirm(review) else { return }
            await perform { repo in
                self.pushUndo(try await repo.stopSeries(id: id, from: day, baseRevision: review.seriesRevision, reviewed: review))
                for editor in [self.mainEditor, self.cardController?.editor].compactMap({ $0 }) where editor.kind == .task {
                    if let task = try await repo.task(id: editor.task.id), task.seriesID == id, task.isRuleSuppressed {
                        self.closeEditors(for: task.id, kind: .task)
                    }
                }
                self.status = "已停止本次及以后的安排"
            }
        } catch { self.error = error.localizedDescription }
    }
    func copySeries(_ id: UUID) async -> Bool {
        guard !isBusy, await permitLeaving(mainEditor) else { return false }
        guard let rule = configuration.rules.filter({ $0.seriesID == id && !$0.isSupersededForExpansion }).max(by: { $0.effectiveFromDay < $1.effectiveFromDay }) else { return false }
        mainEditor = EditorSession(copying: rule, today: today, clock: clock)
        return true
    }
    /// Removing a record from either surface must not silently discard a draft
    /// being edited in the other window.
    private func permitChangingRecord(_ id: UUID, kind: EditorSession.Kind) async -> Bool {
        for editor in [mainEditor, cardController?.editor].compactMap({ $0 }) {
            let recordID = editor.kind == .task ? editor.task.id : editor.countdown.id
            if editor.kind == kind, recordID == id, !(await permitLeaving(editor)) { return false }
        }
        return true
    }
    private func closeEditors(for id: UUID, kind: EditorSession.Kind) {
        if let editor = mainEditor, editor.kind == kind,
           (kind == .task ? editor.task.id : editor.countdown.id) == id { mainEditor = nil }
        if let editor = cardController?.editor, editor.kind == kind,
           (kind == .task ? editor.task.id : editor.countdown.id) == id { cardController?.discardEditor() }
    }
    func changeCountdown(_ event: CountdownEvent, delete: Bool = false) async {
        guard await permitChangingRecord(event.id, kind: .countdown) else { return }
        await perform { repo in
            self.pushUndo(try await repo.setCountdownState(id: event.id, archived: delete ? nil : event.archivedAt == nil, deleted: delete ? true : nil))
            self.closeEditors(for: event.id, kind: .countdown)
            self.status = delete ? "已移到最近删除" : event.archivedAt == nil ? "已归档，可在 App 查看" : "已取消归档"
        }
    }
    func pushUndo(_ action: UndoAction?) { if let action { undoStack.append(action); if undoStack.count > 20 { undoStack.removeFirst() } } }
    private func showCompletionStatus(_ message: String) {
        status = message
        statusDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.status == message else { return }
            self.status = ""
        }
    }
    func undo() async {
        guard let action = undoStack.last else { return }
        await perform { repo in
            try await repo.undo(action); self.undoStack.removeLast()
            self.undoStack = self.undoStack.map { $0.rebased(after: action) }
            self.status = "已撤销\(action.title)"
        }
    }
    func perform(_ operation: @MainActor (TodoRepository) async throws -> Void) async {
        guard !isBusy else { return }
        do { try await write(operation); await refresh() } catch { self.error = error.localizedDescription }
    }
    /// Every foreground repository mutation participates in the restore gate,
    /// including management sheets opened in a different window.
    func write<Value>(_ operation: @MainActor (TodoRepository) async throws -> Value) async throws -> Value {
        guard let repository else { throw DomainError.notFound }
        guard !isBusy else { throw DomainError.invalidSnapshot("本机数据正在处理，请完成后再修改") }
        pendingWrites += 1; defer { pendingWrites -= 1 }
        return try await operation(repository)
    }
    func reload(_ editor: EditorSession, onCard: Bool = false) async {
        guard let repository, !isBusy else { return }
        do {
            await refresh()
            let fresh: EditorSession
            if editor.kind == .task, let task = try await repository.task(id: editor.task.id), task.deletedAt == nil, !task.isRuleSuppressed { fresh = EditorSession(item: task, configuration: configuration, clock: clock) }
            else if editor.kind == .countdown, let event = try await repository.countdown(id: editor.countdown.id), event.deletedAt == nil, !onCard || event.archivedAt == nil { fresh = EditorSession(event: event, clock: clock) }
            else { throw DomainError.notFound }
            if onCard { cardController?.replaceEditor(fresh) } else { mainEditor = fresh }
        } catch {
            editor.error = error.localizedDescription
            if (error as? DomainError) == .notFound {
                editor.recordUnavailable = true; editor.isConflict = false; editor.error = "原记录已删除或不再可编辑，草稿已保留。"
            }
        }
    }
    func exportJSON() async {
        guard let repository, beginDataOperation("选择备份保存位置…") else { return }
        var exported = false
        do {
            if let url = await FileDialogs.saveJSON(suggestedName: "待办备份-\(today).json") {
                busyMessage = "正在导出备份…"
                let data = try await repository.exportData()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try await Task.detached { try data.write(to: url, options: .atomic) }.value
                exported = true
            }
        }
        catch { self.error = error.localizedDescription }
        await finishDataOperation()
        if exported { status = "备份已导出" }
    }
    func restoreJSON() async {
        guard let repository, !isBusy, await permitLeaving(mainEditor), await permitLeaving(cardController?.editor) else { return }
        guard beginDataOperation("选择要恢复的备份…") else { return }
        var restored = false
        do {
            if let url = await FileDialogs.openJSON() {
                busyMessage = "正在校验恢复文件…"
                let input = try await readBackup(url)
                let data = input.0, snapshot = input.1
                let alert = NSAlert(); alert.messageText = "用备份替换当前全部数据？"
                alert.informativeText = "备份包含 \(snapshot.tasks.count) 条待办、\(snapshot.series.count) 条重复规则、\(snapshot.countdowns.count) 个倒计时和 \(snapshot.categories.count) 个类型。将先自动备份当前数据，再一次性替换。此操作不支持撤销。"
                alert.addButton(withTitle: "替换数据"); alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn {
                    busyMessage = "正在备份原数据并恢复…"
                    let backup = storageURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
                    let name = "before-restore-\(Int(clock.now().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
                    let original = try await repository.exportData()
                    try await Task.detached {
                        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                        try original.write(to: backup.appendingPathComponent(name), options: .atomic)
                    }.value
                    try await repository.restoreData(data)
                    mainEditor = nil; cardController?.discardEditor(); undoStack = []; restored = true
                }
            }
        } catch { self.error = "恢复未完成：\(error.localizedDescription)" }
        await finishDataOperation()
        if restored {
            status = "数据已恢复，原数据已自动备份"
            if let warning = services.queueFailureWarning { status += "；\(warning)" }
        }
    }
    private func beginDataOperation(_ message: String) -> Bool {
        guard !isBusy else { return false }
        guard pendingWrites == 0 else { error = "仍有事项正在保存，请完成后再处理备份。"; return false }
        isBusy = true; busyMessage = message; refreshID += 1; services.suspend()
        return true
    }
    private func finishDataOperation() async {
        isBusy = false; services.resume(); await maintainAndRefresh()
    }
    private func readBackup(_ url: URL) async throws -> (Data, StoreSnapshot) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 100 * 1024 * 1024 else { throw DomainError.invalidSnapshot("文件超过 100 MiB") }
            let data = try Data(contentsOf: url)
            return (data, try SnapshotCodec.decode(data))
        }.value
    }
}
