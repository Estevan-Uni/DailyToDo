import Foundation
import UserNotifications
import TodoDomain

/// Retains cold-start clicks until the model and its window action are ready.
/// Serialize opens so a second click cannot replace a draft being confirmed.
@MainActor public final class NotificationOpenQueue {
    private var pending: [ReminderTarget] = []
    private var handler: (@MainActor (ReminderTarget) async -> Void)?
    private var worker: Task<Void, Never>?
    public init() {}
    public func connect(_ handler: @escaping @MainActor (ReminderTarget) async -> Void) {
        self.handler = handler
        startIfReady()
    }
    public func enqueue(_ target: ReminderTarget) {
        pending.append(target)
        startIfReady()
    }
    private func startIfReady() {
        guard handler != nil, worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !pending.isEmpty, let handler {
                let target = pending.removeFirst()
                await handler(target)
            }
            worker = nil
        }
    }
    // Internal observation for deterministic tests; no OS notification needed.
    func finishPendingOpens() async { await worker?.value }
}

/// Kept strongly by AppLifecycle; UNUserNotificationCenter.delegate is weak.
/// Call install before applicationDidFinishLaunching, without asking permission.
public final class NativeNotificationInteraction: NSObject, UNUserNotificationCenterDelegate {
    private let queue: NotificationOpenQueue
    @MainActor public init(queue: NotificationOpenQueue) { self.queue = queue; super.init() }
    @MainActor public func install() { UNUserNotificationCenter.current().delegate = self }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                      withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.presentationOptions(requestID: notification.request.identifier))
    }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                      withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let target = Self.openTarget(requestID: response.notification.request.identifier, actionID: response.actionIdentifier)
        if let target {
            Task { @MainActor [queue] in
                queue.enqueue(target)
                // Acknowledge after handoff, without waiting for data or a
                // user's draft confirmation. The queue retains the intent.
                completionHandler()
            }
        } else { completionHandler() }
    }
    static func presentationOptions(requestID: String) -> UNNotificationPresentationOptions {
        ReminderTarget(requestID: requestID) == nil ? [] : [.banner, .list, .sound]
    }
    static func openTarget(requestID: String, actionID: String) -> ReminderTarget? {
        guard actionID == UNNotificationDefaultActionIdentifier else { return nil }
        return ReminderTarget(requestID: requestID)
    }
}
