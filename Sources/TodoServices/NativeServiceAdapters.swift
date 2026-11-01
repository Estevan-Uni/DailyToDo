import Foundation
import ServiceManagement
import UserNotifications
import TodoDomain

/// Native frameworks stay at this boundary; the queue never exposes their
/// reference objects to persistence or tests.
@MainActor public final class NativeNotificationClient: NotificationClient {
    private let center: UNUserNotificationCenter
    private let clock: AppClock
    public init(clock: AppClock = .system) { self.clock = clock; center = .current() }
    public func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    public func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .allowed
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    public func pendingRequests() async -> [PendingReminder] {
        await center.pendingNotificationRequests().map { request in
            let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            return .init(id: request.identifier, title: request.content.title, body: request.content.body, date: date)
        }
    }
    public func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    public func removeAll() { center.removeAllPendingNotificationRequests() }
    public func add(_ request: ReminderRequest) async throws {
        let delay = request.date.timeIntervalSince(clock.now())
        guard delay > 0 else { throw DomainError.invalidReminder }
        let content = UNMutableNotificationContent(); content.title = request.title; content.body = request.body; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
    }
}

@MainActor public final class NativeLoginItemClient: LoginItemClient {
    public init() {}
    public var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        default: .unavailable
        }
    }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor public final class DefaultServicePreferences: ServicePreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }
}

@MainActor public final class OneShotServiceDeadline: ServiceDeadline {
    private let clock: AppClock
    private var timer: Timer?
    private var generation = 0
    public init(clock: AppClock = .system) { self.clock = clock }
    public func schedule(at date: Date, action: @escaping @MainActor () -> Void) {
        cancel()
        let token = generation
        timer = Timer.scheduledTimer(withTimeInterval: max(0.05, date.timeIntervalSince(clock.now())), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.timer = nil; action()
            }
        }
    }
    public func cancel() { generation += 1; timer?.invalidate(); timer = nil }
}
