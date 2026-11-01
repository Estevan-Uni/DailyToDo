import Foundation
import Testing
import TodoDomain
import TodoPersistence
@testable import TodoServices

@Suite @MainActor struct SystemServicesTests {
    private var instant: Date { ISO8601DateFormatter().date(from: "2026-11-01T08:00:00Z")! }
    private func event(_ index: Int, minutes: Int? = nil) throws -> CountdownEvent {
        var event = CountdownEvent(title: "事件\(index)", targetDay: try LocalDate("2026-11-02"))
        event.reminderAt = instant.addingTimeInterval(Double((minutes ?? index + 1) * 60)); return event
    }
    private func subject(enabled: Bool = true) -> (SystemServices, FakeNotifications, FakeLogin, FakePreferences, FakeDeadline, ServiceTestClock) {
        let notifications = FakeNotifications(), login = FakeLogin(), preferences = FakePreferences(enabled: enabled)
        let deadline = FakeDeadline(), clock = ServiceTestClock(instant)
        let service = SystemServices(clock: clock.value, notifications: notifications, login: login, preferences: preferences, deadline: deadline)
        return (service, notifications, login, preferences, deadline, clock)
    }
    @Test func disabledStartupNeverRequestsPermissionOrReadsTheDatabase() async throws {
        let (service, client, login, _, deadline, _) = subject(enabled: false)
        let source = FakeReminderSource([try event(0)])
        client.pending["old"] = .init(id: "old", title: "旧", body: "", date: instant)
        await service.reconcile(source)
        #expect(client.authorizationCalls == 0 && client.permissionCalls == 0 && client.pending.isEmpty)
        #expect(await source.calls == 0)
        #expect(service.queueHealth == .disabled && service.pendingCount == 0 && deadline.date == nil)
        #expect(login.registerCalls == 0 && login.unregisterCalls == 0)
    }
    @Test func explicitAuthorizationDenialClearsPendingAndKeepsData() async throws {
        let (service, client, _, preferences, deadline, _) = subject(enabled: false)
        let source = FakeReminderSource([try event(0)])
        client.authorizationValue = false
        client.pending["old"] = .init(id: "old", title: "旧", body: "", date: instant)
        await service.setNotifications(true, repository: source)
        #expect(!service.notificationsEnabled && !preferences.notificationsEnabled)
        #expect(service.queueHealth == .denied && service.savedReminderWarning != nil && service.queueFailureWarning != nil)
        #expect(client.authorizationCalls == 1 && client.pending.isEmpty && deadline.date == nil)
        #expect(await source.events.count == 1)
        #expect(await source.calls == 0)
        await service.reconcile(source)
        #expect(service.queueHealth == .denied)
    }
    @Test func authorizationErrorDoesNotPretendThePreferenceWasEnabled() async {
        let (service, client, _, preferences, _, _) = subject(enabled: false)
        client.authorizationFailure = true
        await service.setNotifications(true, repository: FakeReminderSource())
        #expect(!service.notificationsEnabled && !preferences.notificationsEnabled)
        #expect(service.queueHealth == .failed && service.serviceError != nil)
        #expect(service.notificationStatus.contains("授权请求失败"))
        #expect(client.addCalls.isEmpty)
    }
    @Test func turningOffWhileAuthorizationWaitsWinsOverItsLateApproval() async {
        let (service, client, _, preferences, _, _) = subject(enabled: false)
        let source = FakeReminderSource(), gate = ServiceGate(); client.authorizationGate = gate
        let enabling = Task { await service.setNotifications(true, repository: source) }
        await gate.waitUntilEntered()
        await service.setNotifications(false, repository: source)
        gate.open(); await enabling.value
        #expect(!service.notificationsEnabled && !preferences.notificationsEnabled)
        #expect(service.queueHealth == .disabled && client.addCalls.isEmpty)
    }
    @Test func revokedOrUndeterminedPermissionNeverPromptsDuringReconciliation() async throws {
        for permission in [NotificationPermission.denied, .notDetermined] {
            let (service, client, _, preferences, deadline, _) = subject()
            client.permissionValue = permission
            client.pending["old"] = .init(id: "old", title: "旧", body: "", date: instant)
            await service.reconcile(FakeReminderSource([try event(0)]))
            #expect(service.notificationsEnabled && preferences.notificationsEnabled)
            #expect(service.queueHealth == .denied && service.pendingCount == 0 && client.pending.isEmpty)
            #expect(client.authorizationCalls == 0 && deadline.date == nil)
        }
    }
    @Test func matchingRequestsRemainAndChangedOrObsoleteRequestsAreReconciled() async throws {
        let (service, client, _, _, deadline, _) = subject()
        let events = try [event(0), event(1)]
        let plan = ReminderPlan(tasks: [], events: events, now: instant)
        let first = plan.requests[0], second = plan.requests[1]
        client.pending[first.id] = .init(id: first.id, title: first.title, body: first.body, date: first.date.addingTimeInterval(0.25))
        client.pending[second.id] = .init(id: second.id, title: "旧标题", body: second.body, date: second.date)
        client.pending["obsolete"] = .init(id: "obsolete", title: "已完成", body: "", date: first.date)
        await service.reconcile(FakeReminderSource(events))
        #expect(client.addCalls == [second.id] && client.removed.contains("obsolete"))
        #expect(service.queueHealth == .ready && service.pendingCount == 2 && service.savedReminderWarning == nil)
        #expect(deadline.date == first.date.addingTimeInterval(1))
    }
    @Test func failedReplacementRemovesStaleNotificationAndRetryRepairsTheQueue() async throws {
        let (service, client, _, _, deadline, _) = subject()
        let events = try [event(0), event(1)], source = FakeReminderSource(events)
        let failed = ReminderPlan(tasks: [], events: events, now: instant).requests[0]
        client.pending[failed.id] = .init(id: failed.id, title: "旧计划", body: "", date: failed.date)
        client.failedIDs = [failed.id]
        await service.reconcile(source)
        #expect(service.queueHealth == .failed && service.pendingCount == 1 && service.savedReminderWarning != nil)
        #expect(client.pending[failed.id] == nil && deadline.date != nil)
        #expect(await source.events.count == 2)
        client.failedIDs.removeAll(); await service.reconcile(source)
        #expect(service.queueHealth == .ready && service.pendingCount == 2 && client.pending[failed.id]?.title == failed.title)
    }
    @Test func sourceFailureIsAnAncillaryErrorAndCanRecover() async throws {
        let (service, client, _, _, _, _) = subject()
        let source = FakeReminderSource([try event(0)]); await source.configure(failure: true)
        await service.reconcile(source)
        #expect(service.queueHealth == .failed && client.addCalls.isEmpty)
        #expect(await source.events.count == 1)
        await source.configure(); await service.reconcile(source)
        #expect(service.queueHealth == .ready && service.pendingCount == 1)
    }
    @Test func finiteQueueRefillsFromTheInjectedDeadlineWithoutReplayingExpiredRequests() async throws {
        let (service, client, _, _, deadline, clock) = subject()
        let events = try (0..<50).map { try event($0) }, source = FakeReminderSource(events)
        await service.reconcile(source)
        #expect(service.pendingCount == 48 && client.pending.count == 48)
        #expect(service.notificationStatus.contains("待补充 2 条"))
        let oldFirst = "countdown-\(events[0].id)"
        clock.now = try #require(deadline.date)
        let gate = ServiceGate(); await source.configure(gate: gate)
        deadline.fire(); await gate.waitUntilEntered(); gate.open()
        await service.reconcile(source)
        #expect(service.pendingCount == 48 && client.pending.count == 48 && client.pending[oldFirst] == nil)
        #expect(service.notificationStatus.contains("待补充 1 条"))
        #expect(client.pending["countdown-\(events[48].id)"] != nil)
    }
    @Test func closingRemindersDuringAnInflightAddClearsTheLateRequest() async throws {
        let (service, client, _, preferences, deadline, _) = subject()
        let source = FakeReminderSource([try event(0)]), gate = ServiceGate(); client.addGate = gate
        let loading = Task { await service.reconcile(source) }
        await gate.waitUntilEntered()
        let started = ServiceSignal()
        let disabling = Task { started.mark(); await service.setNotifications(false, repository: source) }
        await started.wait()
        #expect(!preferences.notificationsEnabled && client.pending.isEmpty)
        gate.open(); await loading.value; await disabling.value
        #expect(!preferences.notificationsEnabled && !service.notificationsEnabled)
        #expect(service.queueHealth == .disabled && client.pending.isEmpty && deadline.date == nil)
    }
    @Test func restoreInvalidatesAnInflightAddAndUsesTheNewRepositoryForItsNextPass() async throws {
        let (service, client, _, _, _, _) = subject()
        let old = try event(0), new = try event(1), oldSource = FakeReminderSource([old]), newSource = FakeReminderSource([new])
        let gate = ServiceGate(); client.addGate = gate
        let loading = Task { await service.reconcile(oldSource) }; await gate.waitUntilEntered()
        service.suspend(); service.resume()
        let started = ServiceSignal()
        let restored = Task { started.mark(); await service.reconcile(newSource) }
        await started.wait(); gate.open(); await loading.value; await restored.value
        #expect(service.queueHealth == .ready && service.pendingCount == 1)
        #expect(Set(client.pending.keys) == ["countdown-\(new.id)"])
        #expect(await oldSource.calls == 1)
    }
    @Test func suspendedReconciliationAndAnOldDeadlineCannotRestartOldWork() async throws {
        let (service, client, _, _, deadline, _) = subject()
        let source = FakeReminderSource([try event(0)]); await service.reconcile(source)
        let oldCallback = try #require(deadline.action), calls = await source.calls
        service.suspend(); oldCallback(); await service.reconcile(source)
        service.resume(); oldCallback(); await Task.yield()
        #expect(await source.calls == calls)
        #expect(deadline.date == nil && client.pending.count == 1)
        await service.reconcile(source)
        #expect(await source.calls == calls + 1)
    }
    @Test func joinersWaitForTheUpdatedSourceInsteadOfReturningAStaleReadyState() async throws {
        let (service, client, _, _, _, _) = subject()
        let oldSource = FakeReminderSource([try event(0)]), newSource = FakeReminderSource([try event(1)])
        let gate = ServiceGate(); await oldSource.configure(gate: gate)
        let first = Task { await service.reconcile(oldSource) }; await gate.waitUntilEntered()
        let started = ServiceSignal(); var joinedFinished = false
        let joined = Task { started.mark(); await service.reconcile(newSource); joinedFinished = true }
        await started.wait(); #expect(!joinedFinished)
        gate.open(); await first.value; await joined.value
        let latest = try #require(await newSource.events.first)
        #expect(Set(client.pending.keys) == ["countdown-\(latest.id)"])
        #expect(client.addCalls == ["countdown-\(latest.id)"])
        #expect(await oldSource.calls == 1)
        #expect(await newSource.calls == 1)
    }
    @Test func loginApprovalAndFailuresReflectTheActualServiceState() {
        let (service, _, login, _, _, _) = subject(enabled: false)
        #expect(!service.loginEnabled && login.registerCalls == 0)
        login.stateAfterRegister = .requiresApproval; service.setLogin(true)
        #expect(!service.loginEnabled && service.serviceError != nil)
        login.stateAfterRegister = .enabled; service.setLogin(true)
        #expect(service.loginEnabled && service.serviceError == nil)
        login.unregisterFailure = true; service.setLogin(false)
        #expect(service.loginEnabled && service.serviceError != nil)
        login.unregisterFailure = false; service.setLogin(false)
        #expect(!service.loginEnabled && service.serviceError == nil)
        login.registerFailure = true; service.setLogin(true)
        #expect(!service.loginEnabled && service.serviceError != nil)
        login.registerFailure = false; login.stateAfterRegister = .unavailable; service.setLogin(true)
        #expect(!service.loginEnabled && service.serviceError != nil)
    }
    @Test func lateAuthorizationUsesTheLatestDataSource() async throws {
        let (service, client, _, _, _, _) = subject(enabled: false)
        let oldSource = FakeReminderSource([try event(0)]), newEvent = try event(1), newSource = FakeReminderSource([newEvent])
        let gate = ServiceGate(); client.authorizationGate = gate
        let enabling = Task { await service.setNotifications(true, repository: oldSource) }; await gate.waitUntilEntered()
        await service.reconcile(newSource)
        gate.open(); await enabling.value
        #expect(Set(client.pending.keys) == ["countdown-\(newEvent.id)"])
        #expect(await oldSource.calls == 0)
    }
    @Test func enabledPreferenceWithoutDataReportsUnavailableInsteadOfClaimingReady() async {
        let (service, client, _, _, deadline, _) = subject()
        await service.reconcile(nil)
        #expect(service.queueHealth == .failed && service.savedReminderWarning != nil)
        #expect(service.notificationStatus.contains("数据尚未就绪"))
        #expect(client.addCalls.isEmpty && client.authorizationCalls == 0 && deadline.date == nil)
    }
    @Test func reminderReconciliationWithRealSQLitePreservesDataAndRecomputesRuleTimeAfterTravel() async throws {
        let (service, client, _, _, _, clock) = subject()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TodoServiceIntegration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        clock.now = try #require(ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        let repo = try TodoRepository(url: directory.appendingPathComponent("tasks.sqlite"), now: clock.value.now, timeZone: clock.value.timeZone)
        var draft = TaskDraft(day: try LocalDate("2026-11-01")); draft.title = "每日阅读"; draft.minute = 540
        draft.categoryID = TodoCategory.defaults[0].id; draft.frequency = .daily; draft.reminderOffsetMinutes = 0
        let saved = try await repo.saveTask(draft).task, key = "task-\(saved.id)"
        client.failedIDs = [key]
        await service.reconcile(repo)
        #expect(service.queueHealth == .failed && client.pending[key] == nil)
        #expect(try await repo.task(id: saved.id) == saved)
        client.failedIDs.removeAll(); clock.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        await service.reconcile(repo)
        #expect(service.queueHealth == .ready)
        #expect(client.pending[key]?.date == (try LocalDate("2026-11-01").instant(minute: 540, timeZone: clock.timeZone)))
        #expect(try await repo.task(id: saved.id) == saved)
        try await repo.close()
    }
    @Test func notificationPreferencePersistsWithoutAutomaticallyRequestingAuthorizationOnReopen() async throws {
        let suite = "TodoServicePreferenceTests-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FakeNotifications(), login = FakeLogin(), deadline = FakeDeadline(), clock = ServiceTestClock(instant)
        let preferences = DefaultServicePreferences(defaults: defaults), source = FakeReminderSource([try event(0)])
        let first = SystemServices(clock: clock.value, notifications: client, login: login, preferences: preferences, deadline: deadline)
        #expect(!first.notificationsEnabled && client.authorizationCalls == 0)
        await first.setNotifications(true, repository: source)
        #expect(defaults.bool(forKey: "notificationsEnabled") && client.authorizationCalls == 1)
        let reopened = SystemServices(clock: clock.value, notifications: client, login: login, preferences: DefaultServicePreferences(defaults: defaults), deadline: FakeDeadline())
        await reopened.reconcile(source)
        #expect(reopened.notificationsEnabled && reopened.queueHealth == .ready && client.authorizationCalls == 1)
        await reopened.setNotifications(false, repository: source)
        #expect(!defaults.bool(forKey: "notificationsEnabled") && client.pending.isEmpty)
    }
}
