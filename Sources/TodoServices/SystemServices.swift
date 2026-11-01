import Foundation
import Observation
import TodoDomain

/// Serial queue reconciliation with replaceable OS clients. Generation checks
/// discard work begun before restore/suspension; new requests join the next pass.
@MainActor @Observable public final class SystemServices {
    public enum QueueHealth { case disabled, ready, denied, failed }
    public private(set) var queueHealth: QueueHealth = .disabled
    public private(set) var notificationsEnabled: Bool
    public private(set) var notificationStatus = "未开启"
    public private(set) var loginEnabled: Bool
    public var serviceError: String?
    public private(set) var pendingCount = 0
    private let notifications: any NotificationClient
    private let login: any LoginItemClient
    private let preferences: any ServicePreferences
    private let deadline: any ServiceDeadline
    private let clock: AppClock
    private var reconciling = false
    private var needsReconcile = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var suspended = false
    private var generation = 0
    private var preferenceRequest = 0
    private var latestSource: (any ReminderSource)?
    private var authorizationDenied = false

    public init(clock: AppClock = .system, notifications: (any NotificationClient)? = nil,
                login: (any LoginItemClient)? = nil, preferences: (any ServicePreferences)? = nil,
                deadline: (any ServiceDeadline)? = nil) {
        self.clock = clock; self.notifications = notifications ?? NativeNotificationClient(clock: clock)
        self.login = login ?? NativeLoginItemClient(); self.preferences = preferences ?? DefaultServicePreferences()
        self.deadline = deadline ?? OneShotServiceDeadline(clock: clock)
        notificationsEnabled = self.preferences.notificationsEnabled; loginEnabled = self.login.state == .enabled
    }
    public var savedReminderWarning: String? {
        switch queueHealth {
        case .disabled: "提醒尚未开启，可在设置中开启。"
        case .ready: nil
        case .denied: "系统未允许通知，请在设置中检查。"
        case .failed: "部分提醒未能排队，请在设置中重试。"
        }
    }
    public var queueFailureWarning: String? {
        switch queueHealth {
        case .denied, .failed: savedReminderWarning
        case .disabled, .ready: nil
        }
    }
    public func setNotifications(_ enabled: Bool, repository: (any ReminderSource)?) async {
        latestSource = repository
        preferenceRequest += 1; let request = preferenceRequest
        serviceError = nil
        if enabled {
            do {
                let allowed = try await notifications.requestAuthorization()
                guard request == preferenceRequest else { return }
                generation += 1; authorizationDenied = !allowed
                notificationsEnabled = allowed; preferences.notificationsEnabled = allowed
                if !allowed {
                    deadline.cancel(); notifications.removeAll(); pendingCount = 0
                    queueHealth = .denied; notificationStatus = "通知权限未允许，请在系统设置中开启。"; return
                }
            } catch {
                guard request == preferenceRequest else { return }
                queueHealth = .failed; notificationStatus = "通知授权请求失败，请重试。"
                serviceError = error.localizedDescription; return
            }
        } else {
            generation += 1; authorizationDenied = false
            notificationsEnabled = false; preferences.notificationsEnabled = false
            deadline.cancel(); notifications.removeAll(); pendingCount = 0
        }
        await reconcile(latestSource)
    }
    public func reconcile(_ repository: (any ReminderSource)?) async {
        latestSource = repository
        guard !suspended else { return }
        // A newer data command supersedes the in-flight snapshot, even when
        // both calls use the same repository instance.
        generation += 1
        needsReconcile = true
        if reconciling {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        reconciling = true
        defer {
            reconciling = false
            let waiting = waiters; waiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
        repeat {
            needsReconcile = false
            await updateQueue(latestSource, generation: generation)
        } while needsReconcile && !suspended
    }
    private func current(_ token: Int) -> Bool { !suspended && generation == token }
    private func updateQueue(_ repository: (any ReminderSource)?, generation token: Int) async {
        guard current(token) else { return }
        deadline.cancel()
        guard notificationsEnabled else {
            notifications.removeAll(); pendingCount = 0
            queueHealth = authorizationDenied ? .denied : .disabled
            notificationStatus = authorizationDenied ? "通知权限未允许，请在系统设置中开启。" : "未开启"; return
        }
        guard let repository else {
            queueHealth = .failed; notificationStatus = "本机数据尚未就绪，提醒未核对。"; return
        }
        do {
            let permission = await notifications.permission()
            guard current(token) else { return }
            guard notificationsEnabled else { needsReconcile = true; return }
            guard permission == .allowed else {
                notifications.removeAll(); pendingCount = 0; queueHealth = .denied
                notificationStatus = "系统未允许通知；数据仍正常保存。"; return
            }
            let records = try await repository.reminderCandidates()
            guard current(token) else { return }
            let plan = ReminderPlan(tasks: records.tasks, events: records.events, now: clock.now())
            let existing = await notifications.pendingRequests()
            guard current(token) else { return }
            guard notificationsEnabled else { needsReconcile = true; return }
            let desiredIDs = Set(plan.requests.map(\.id))
            notifications.remove(ids: existing.map(\.id).filter { !desiredIDs.contains($0) })
            var count = 0, failures = 0
            for item in plan.requests {
                guard current(token) else { return }
                guard notificationsEnabled else { needsReconcile = true; return }
                guard item.date > clock.now() else { notifications.remove(ids: [item.id]); continue }
                if existing.contains(where: { $0.matches(item) }) { count += 1; continue }
                do { try await notifications.add(item); count += 1 }
                catch {
                    guard current(token) else { notifications.remove(ids: [item.id]); return }
                    // A failed replacement must not leave an older time/title
                    // pending for the same identity.
                    notifications.remove(ids: [item.id]); failures += 1
                }
                guard current(token) else { notifications.remove(ids: [item.id]); return }
            }
            pendingCount = count; queueHealth = failures == 0 ? .ready : .failed
            notificationStatus = "已排队 \(count) 条 · 待补充 \(plan.deferredCount) 条" + (failures > 0 ? " · 失败 \(failures) 条，可重试" : "")
            if let next = plan.requests.first?.date {
                deadline.schedule(at: max(clock.now().addingTimeInterval(1), next.addingTimeInterval(1))) { [weak self] in
                    guard let self, self.current(token) else { return }
                    Task { await self.reconcile(self.latestSource) }
                }
            }
        } catch {
            guard current(token) else { return }
            queueHealth = .failed; notificationStatus = "提醒排队失败：\(error.localizedDescription)"
        }
    }
    public func suspend() { suspended = true; generation += 1; deadline.cancel() }
    public func resume() { suspended = false; generation += 1 }
    public func setLogin(_ enabled: Bool) {
        serviceError = nil
        do {
            if enabled { try login.register() } else { try login.unregister() }
            loginEnabled = login.state == .enabled
            if enabled, login.state == .requiresApproval { serviceError = "请在系统设置 → 通用 → 登录项中允许此 App。" }
            else if enabled, login.state != .enabled { serviceError = "登录项尚未注册成功，请重试或在系统设置中检查。" }
        } catch { loginEnabled = login.state == .enabled; serviceError = error.localizedDescription }
    }
}
