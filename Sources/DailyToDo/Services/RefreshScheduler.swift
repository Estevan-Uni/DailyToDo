import AppKit
import TodoDomain
import TodoServices

/// One timer at the next visible status boundary or midnight, never a minute poll.
@MainActor final class RefreshScheduler {
    private let deadline: any ServiceDeadline
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private weak var model: AppModel?
    init(model: AppModel, deadline: (any ServiceDeadline)? = nil) {
        self.model = model; self.deadline = deadline ?? OneShotServiceDeadline(clock: model.clock)
        for name in [NSApplication.didBecomeActiveNotification, NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.update() } })
        }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.update() } })
        rescheduleStatus()
    }
    func rescheduleStatus() {
        deadline.cancel()
        guard let model else { return }
        let now = model.clock.now(); model.clockNow = now; model.displayTimeZone = model.clock.timeZone()
        let next = AgendaClock.nextChange(items: model.mainItems + model.cardItems, now: now, timeZone: model.displayTimeZone)
        deadline.schedule(at: next.addingTimeInterval(0.05)) { [weak self] in
            Task { @MainActor in await self?.statusBoundary() }
        }
    }
    private func statusBoundary() async {
        guard let model else { return }
        if !model.isBusy, model.clock.today != model.today { await model.maintainAndRefresh() }
        rescheduleStatus()
    }
    private func update() async { await model?.maintainAndRefresh(); rescheduleStatus() }
}
