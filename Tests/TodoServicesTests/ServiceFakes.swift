import Foundation
import TodoDomain
@testable import TodoServices

enum ServiceTestError: Error { case injected }

@MainActor final class ServiceSignal {
    private var marked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func mark() { marked = true; let waiting = waiters; waiters.removeAll(); for waiter in waiting { waiter.resume() } }
    func wait() async { if !marked { await withCheckedContinuation { waiters.append($0) } } }
}

@MainActor final class ServiceGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation; entered = true
            let waiting = entryWaiters; entryWaiters.removeAll(); for waiter in waiting { waiter.resume() }
        }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func open() { let continuation = release; release = nil; continuation?.resume() }
}

final class ServiceTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    private var zone = TimeZone(secondsFromGMT: 0)!
    init(_ instant: Date) { self.instant = instant }
    var now: Date { get { lock.withLock { instant } } set { lock.withLock { instant = newValue } } }
    var timeZone: TimeZone { get { lock.withLock { zone } } set { lock.withLock { zone = newValue } } }
    var value: AppClock { .init(now: { self.now }, timeZone: { self.timeZone }) }
}

@MainActor final class FakeNotifications: NotificationClient {
    var permissionValue: NotificationPermission = .allowed
    var authorizationValue = true
    var authorizationFailure = false
    var authorizationCalls = 0
    var permissionCalls = 0
    var pending: [String: PendingReminder] = [:]
    var addCalls: [String] = []
    var removed: [String] = []
    var removeAllCalls = 0
    var failedIDs: Set<String> = []
    var authorizationGate: ServiceGate?
    var permissionGate: ServiceGate?
    var addGate: ServiceGate?
    var afterAdd: (() -> Void)?
    func requestAuthorization() async throws -> Bool {
        authorizationCalls += 1
        if let gate = authorizationGate { authorizationGate = nil; await gate.pause() }
        if authorizationFailure { throw ServiceTestError.injected }
        return authorizationValue
    }
    func permission() async -> NotificationPermission {
        permissionCalls += 1
        if let gate = permissionGate { permissionGate = nil; await gate.pause() }
        return permissionValue
    }
    func pendingRequests() async -> [PendingReminder] { Array(pending.values) }
    func remove(ids: [String]) { removed += ids; for id in ids { pending.removeValue(forKey: id) } }
    func removeAll() { removeAllCalls += 1; pending.removeAll() }
    func add(_ request: ReminderRequest) async throws {
        addCalls.append(request.id)
        if let gate = addGate { addGate = nil; await gate.pause() }
        if failedIDs.contains(request.id) { throw ServiceTestError.injected }
        pending[request.id] = .init(id: request.id, title: request.title, body: request.body, date: request.date)
        afterAdd?()
    }
}

@MainActor final class FakeLogin: LoginItemClient {
    var state: LoginItemState = .notRegistered
    var stateAfterRegister: LoginItemState = .enabled
    var registerFailure = false
    var unregisterFailure = false
    var registerCalls = 0
    var unregisterCalls = 0
    func register() throws {
        registerCalls += 1; if registerFailure { throw ServiceTestError.injected }; state = stateAfterRegister
    }
    func unregister() throws {
        unregisterCalls += 1; if unregisterFailure { throw ServiceTestError.injected }; state = .notRegistered
    }
}

@MainActor final class FakePreferences: ServicePreferences {
    var notificationsEnabled: Bool
    init(enabled: Bool) { notificationsEnabled = enabled }
}
@MainActor final class FakeDeadline: ServiceDeadline {
    var date: Date?
    var action: (@MainActor () -> Void)?
    var cancellations = 0
    func schedule(at date: Date, action: @escaping @MainActor () -> Void) { self.date = date; self.action = action }
    func cancel() { cancellations += 1; date = nil; action = nil }
    func fire() { let saved = action; date = nil; action = nil; saved?() }
}

actor FakeReminderSource: ReminderSource {
    var events: [CountdownEvent]
    var calls = 0
    var failure = false
    var gate: ServiceGate?
    init(_ events: [CountdownEvent] = []) { self.events = events }
    func configure(failure: Bool = false, gate: ServiceGate? = nil) { self.failure = failure; self.gate = gate }
    func reminderCandidates() async throws -> (tasks: [TodoItem], events: [CountdownEvent]) {
        calls += 1; let snapshot = events
        if let gate { self.gate = nil; await gate.pause() }
        if failure { throw ServiceTestError.injected }
        return ([], snapshot)
    }
}
