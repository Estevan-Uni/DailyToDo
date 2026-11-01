import Foundation
import Testing
import TodoDomain
import TodoPersistence
import TodoServices
@testable import DailyToDo

@Suite @MainActor struct ReminderNavigationTests {
    private func fixture(choice: EditorLeaveChoice = .continueEditing,
                         notifications: NavigationNotifications? = nil,
                         _ body: (AppModel, TodoRepository) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReminderNavigationTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), instant = Date(timeIntervalSince1970: 1_793_606_400)
        let clock = AppClock(now: { instant }, timeZone: { TimeZone(secondsFromGMT: 0)! })
        let repo = try TodoRepository(url: url, now: clock.now, timeZone: clock.timeZone)
        let services = SystemServices(clock: clock, notifications: notifications ?? NavigationNotifications(), login: NavigationLogin(),
                                      preferences: NavigationPreferences(), deadline: NavigationDeadline())
        let model = AppModel(clock: clock, services: services, storageURL: url, confirmLeaving: { _ in choice })
        model.repository = repo; model.isLoading = false
        do { try await body(model, repo); try await repo.close() }
        catch { try? await repo.close(); throw error }
    }
    private func draft(day: LocalDate, title: String = "打开的待办") -> TaskDraft {
        var draft = TaskDraft(day: day); draft.title = title; draft.minute = 600; draft.categoryID = TodoCategory.defaults[0].id
        return draft
    }
    @Test func oldNotificationUsesCurrentRolledDayAndClearsFiltersWithoutWriting() async throws {
        try await fixture { model, repo in
            let result = try await repo.saveTask(draft(day: model.today.adding(days: -3)))
            _ = try await repo.rolloverUnfinishedSingles()
            let before = try await repo.exportData()
            model.section = .countdowns; model.search = "不匹配"; model.completionFilter = .done
            model.categoryFilter = TodoCategory.defaults[2].id
            var shown = 0; model.showMainAction = { shown += 1 }
            await model.openReminder(.task(result.task.id))
            #expect(shown == 1 && model.section == .schedule && model.selectedDay == model.today)
            #expect(model.search.isEmpty && model.completionFilter == .all && model.categoryFilter == nil)
            #expect(model.mainEditor?.task.id == result.task.id && model.mainEditor?.task.day == model.today)
            #expect(try await repo.exportData() == before)
        }
    }
    @Test func completedTaskOpensItsHistoryWithoutRestoringItToCard() async throws {
        try await fixture { model, repo in
            let item = try await repo.saveTask(draft(day: model.today)).task
            _ = try await repo.setCompletion(id: item.id, completed: true)
            let before = try await repo.exportData()
            await model.openReminder(.task(item.id))
            #expect(model.mainEditor?.completedAt != nil)
            #expect(model.mainItems.contains { $0.id == item.id && $0.completedAt != nil })
            #expect(!model.cardItems.contains { $0.id == item.id })
            #expect(try await repo.exportData() == before)
        }
    }
    @Test func missingAndDeletedTargetsKeepCurrentDraftWithoutPromptingOrResurrection() async throws {
        try await fixture(choice: .discard) { model, repo in
            let item = try await repo.saveTask(draft(day: model.today)).task
            _ = try await repo.deleteTask(id: item.id)
            let draft = EditorSession(day: model.today, clock: model.clock); draft.task.title = "保留草稿"
            model.mainEditor = draft
            for target in [ReminderTarget.task(item.id), .task(UUID()), .countdown(UUID())] {
                await model.openReminder(target)
                #expect(model.mainEditor === draft && draft.task.title == "保留草稿")
                #expect(model.status.contains("已删除或不再可用"))
            }
            #expect(try await repo.task(id: item.id)?.deletedAt != nil)
            let valid = try await repo.saveTask(self.draft(day: model.today, title: "仍可打开")).task
            await model.openReminder(.task(valid.id))
            #expect(model.mainEditor?.task.id == valid.id && model.status.isEmpty)
        }
    }
    @Test func archivedCountdownUsesLatestTitleAndRemainsArchived() async throws {
        try await fixture { model, repo in
            var value = CountdownDraft(day: model.today); value.title = "最初标题"
            let created = try await repo.saveCountdown(value)
            var edited = CountdownDraft(event: created); edited.title = "当前标题"
            let saved = try await repo.saveCountdown(edited)
            _ = try await repo.setCountdownState(id: saved.id, archived: true)
            let before = try await repo.exportData()
            model.search = "旧搜索"
            await model.openReminder(.countdown(saved.id))
            #expect(model.section == .countdowns && model.search.isEmpty)
            #expect(model.mainEditor?.countdown.title == "当前标题" && model.status.contains("已归档"))
            #expect(model.events.isEmpty && model.archivedEvents.map(\.id) == [saved.id])
            #expect(try await repo.exportData() == before)
        }
    }
    @Test func continuingEditingOrFailingSaveDoesNotReplaceTheDraft() async throws {
        for choice in [EditorLeaveChoice.continueEditing, .save] {
            try await fixture(choice: choice) { model, repo in
                let item = try await repo.saveTask(draft(day: model.today)).task
                let editor = EditorSession(day: model.today, clock: model.clock); editor.task.title = "未填时间"
                model.mainEditor = editor; model.search = "保留筛选"
                let before = try await repo.exportData()
                await model.openReminder(.task(item.id))
                #expect(model.mainEditor === editor && model.search == "保留筛选")
                #expect(try await repo.exportData() == before)
                if choice == .save { #expect(editor.error != nil) }
            }
        }
    }
    @Test func savingClickedRecordBeforeOpeningReReadsItsNewRevision() async throws {
        try await fixture(choice: .save) { model, repo in
            let item = try await repo.saveTask(draft(day: model.today)).task
            model.configuration = try await repo.configuration()
            let editor = EditorSession(item: item, configuration: model.configuration, clock: model.clock)
            editor.task.title = "离开前已保存标题"; model.mainEditor = editor
            await model.openReminder(.task(item.id))
            let saved = try #require(await repo.task(id: item.id))
            #expect(saved.title == "离开前已保存标题" && saved.revision == item.revision + 1)
            #expect(model.mainEditor !== editor && model.mainEditor?.task.title == saved.title)
            #expect(model.mainEditor?.task.baseRevision == saved.revision && model.mainEditor?.dirty == false)
        }
    }
    @Test func onlyExplicitEditorReminderIntentRequestsPermissionAndDenialKeepsTheDraft() async throws {
        for allowed in [true, false] {
            let client = NavigationNotifications(); client.authorizationResult = allowed
            try await fixture(notifications: client) { model, repo in
                let editor = EditorSession(day: model.today, clock: model.clock)
                editor.task.title = "允许或拒绝后均保留"; model.mainEditor = editor
                let before = try await repo.exportData()
                #expect(client.authorizationCalls == 0)
                await model.requestRemindersFromEditor()
                #expect(client.authorizationCalls == 1 && model.services.notificationsEnabled == allowed)
                #expect(model.mainEditor === editor && editor.task.title == "允许或拒绝后均保留")
                #expect(try await repo.exportData() == before)
                if allowed {
                    await model.requestRemindersFromEditor()
                    #expect(client.authorizationCalls == 1)
                } else { #expect(model.services.queueHealth == .denied && model.services.savedReminderWarning != nil) }
            }
        }
    }
}

// This suite exercises the actual AppModel and temporary SQLite. OS clients
// never request authorization, register login items, or schedule notifications.
@MainActor private final class NavigationNotifications: NotificationClient {
    var authorizationResult: Bool?
    var authorizationCalls = 0
    func requestAuthorization() async throws -> Bool {
        authorizationCalls += 1
        guard let authorizationResult else { Issue.record("Unexpected authorization"); return false }
        return authorizationResult
    }
    func permission() async -> NotificationPermission {
        guard authorizationResult != nil else { Issue.record("Unexpected permission read"); return .denied }
        return authorizationResult == true ? .allowed : .denied
    }
    func pendingRequests() async -> [PendingReminder] { [] }
    func remove(ids: [String]) {}
    func removeAll() {}
    func add(_ request: ReminderRequest) async throws { Issue.record("Unexpected OS notification") }
}
@MainActor private final class NavigationLogin: LoginItemClient {
    var state: LoginItemState { .notRegistered }
    func register() throws { Issue.record("Unexpected login registration") }
    func unregister() throws { Issue.record("Unexpected login unregister") }
}
@MainActor private final class NavigationPreferences: ServicePreferences { var notificationsEnabled = false }
@MainActor private final class NavigationDeadline: ServiceDeadline {
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) { Issue.record("Unexpected notification timer") }
    func cancel() {}
}
