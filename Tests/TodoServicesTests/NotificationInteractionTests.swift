import Foundation
import Testing
import UserNotifications
import TodoDomain
@testable import TodoServices

@Suite @MainActor struct NotificationInteractionTests {
    @Test func explicitForegroundOptionsOnlyApplyToRecognizedReminders() {
        let options = NativeNotificationInteraction.presentationOptions(requestID: ReminderTarget.task(UUID()).requestID)
        #expect(options == [.banner, .list, .sound])
        #expect(NativeNotificationInteraction.presentationOptions(requestID: "other-app-format").isEmpty)
    }
    @Test func dismissAndUnknownActionsDoNotNavigate() {
        let target = ReminderTarget.countdown(UUID())
        #expect(NativeNotificationInteraction.openTarget(requestID: target.requestID, actionID: UNNotificationDefaultActionIdentifier) == target)
        #expect(NativeNotificationInteraction.openTarget(requestID: target.requestID, actionID: UNNotificationDismissActionIdentifier) == nil)
        #expect(NativeNotificationInteraction.openTarget(requestID: target.requestID, actionID: "custom-unknown") == nil)
        #expect(NativeNotificationInteraction.openTarget(requestID: "bad-id", actionID: UNNotificationDefaultActionIdentifier) == nil)
    }
    @Test func coldStartRetainsClicksUntilDataAndWindowAreReady() async {
        let queue = NotificationOpenQueue(), target = ReminderTarget.task(UUID())
        var opened: [ReminderTarget] = []
        queue.enqueue(target)
        await queue.finishPendingOpens()
        #expect(opened.isEmpty)
        queue.connect { opened.append($0) }
        await queue.finishPendingOpens()
        #expect(opened == [target])
        queue.enqueue(.countdown(UUID()))
        await queue.finishPendingOpens()
        #expect(opened.count == 2)
    }
    @Test func aSecondClickWaitsWhileTheFirstHandlesItsDraft() async {
        let queue = NotificationOpenQueue(), gate = ServiceGate()
        let first = ReminderTarget.task(UUID()), second = ReminderTarget.countdown(UUID())
        var began: [ReminderTarget] = [], finished: [ReminderTarget] = []
        queue.connect { target in
            began.append(target)
            if target == first { await gate.pause() }
            finished.append(target)
        }
        queue.enqueue(first)
        await gate.waitUntilEntered()
        queue.enqueue(second)
        #expect(began == [first] && finished.isEmpty)
        gate.open()
        await queue.finishPendingOpens()
        #expect(began == [first, second] && finished == [first, second])
    }
}
