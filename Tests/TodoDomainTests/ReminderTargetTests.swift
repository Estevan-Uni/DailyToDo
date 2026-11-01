import Foundation
import Testing
@testable import TodoDomain

@Suite struct ReminderTargetTests {
    @Test func existingPlanIdentifiersRoundTripToBothRecordKinds() throws {
        let now = Date(timeIntervalSince1970: 1_793_520_000), day = try LocalDate("2026-11-02")
        var item = TodoItem(title: "待办", scheduledDay: day, scheduledMinute: 600, categoryID: UUID())
        var event = CountdownEvent(title: "倒计时", targetDay: day)
        item.reminderAt = now.addingTimeInterval(60); event.reminderAt = now.addingTimeInterval(120)
        let plan = ReminderPlan(tasks: [item], events: [event], now: now)
        #expect(plan.requests.map { ReminderTarget(requestID: $0.id) } == [.task(item.id), .countdown(event.id)])
        #expect(ReminderTarget.task(item.id).requestID == "task-\(item.id)")
        #expect(ReminderTarget.countdown(event.id).requestID == "countdown-\(event.id)")
        #expect(ReminderTarget(requestID: "task-\(item.id.uuidString.lowercased())") == .task(item.id))
    }
    @Test func malformedOrUnrecognizedIdentitiesNeverBecomeOpenTargets() {
        let id = UUID().uuidString
        for invalid in ["", id, "task-", "TASK-\(id)", "event-\(id)", "task-\(id) ", " task-\(id)",
                        "task-\(id)/extra", "countdown-\(id)?date=2026-11-01", "task-\(id.replacingOccurrences(of: "-", with: ""))"] {
            #expect(ReminderTarget(requestID: invalid) == nil)
        }
    }
}
