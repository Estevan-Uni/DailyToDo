import Foundation
import TodoDomain
import TodoPersistence

public enum NotificationPermission: Sendable { case allowed, denied, notDetermined }
public enum LoginItemState: Sendable { case enabled, requiresApproval, notRegistered, unavailable }

public struct PendingReminder: Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date?
    public init(id: String, title: String, body: String, date: Date?) {
        self.id = id; self.title = title; self.body = body; self.date = date
    }
    func matches(_ request: ReminderRequest) -> Bool {
        id == request.id && title == request.title && body == request.body && date.map { abs($0.timeIntervalSince(request.date)) < 1 } == true
    }
}

@MainActor public protocol NotificationClient: AnyObject {
    func requestAuthorization() async throws -> Bool
    func permission() async -> NotificationPermission
    func pendingRequests() async -> [PendingReminder]
    func remove(ids: [String])
    func removeAll()
    func add(_ request: ReminderRequest) async throws
}

@MainActor public protocol LoginItemClient: AnyObject {
    var state: LoginItemState { get }
    func register() throws
    func unregister() throws
}

@MainActor public protocol ServicePreferences: AnyObject {
    var notificationsEnabled: Bool { get set }
}

@MainActor public protocol ServiceDeadline: AnyObject {
    func schedule(at date: Date, action: @escaping @MainActor () -> Void)
    func cancel()
}

public protocol ReminderSource: Sendable {
    func reminderCandidates() async throws -> (tasks: [TodoItem], events: [CountdownEvent])
}
extension TodoRepository: ReminderSource {}
