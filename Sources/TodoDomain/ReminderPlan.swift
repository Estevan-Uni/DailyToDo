import Foundation

public struct ReminderRequest: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date
}

/// One budget shared by tasks and countdowns, independent of OS permissions.
public struct ReminderPlan: Sendable {
    public let requests: [ReminderRequest]
    public let eligibleCount: Int
    public var deferredCount: Int { eligibleCount - requests.count }
    public init(tasks: [TodoItem], events: [CountdownEvent], now: Date) {
        let tasks = tasks.compactMap { task -> ReminderRequest? in
            guard task.completedAt == nil, task.deletedAt == nil, !task.isRuleSuppressed,
                  let date = task.reminderAt, date > now else { return nil }
            return ReminderRequest(id: ReminderTarget.task(task.id).requestID, title: task.title,
                body: "待办 · \(task.scheduledDay)" + (task.hasScheduledTime ? " " + task.timeLabel : ""), date: date)
        }
        let events = events.compactMap { event -> ReminderRequest? in
            guard event.deletedAt == nil, event.archivedAt == nil, let date = event.reminderAt, date > now else { return nil }
            return ReminderRequest(id: ReminderTarget.countdown(event.id).requestID, title: event.title, body: "倒计时 · \(event.targetDay)", date: date)
        }
        let all = (tasks + events).sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        eligibleCount = all.count; requests = Array(all.prefix(48))
    }
}
