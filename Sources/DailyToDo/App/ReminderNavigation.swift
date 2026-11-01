import TodoDomain
import TodoPersistence

extension AppModel {
    /// Opening is read-only. Re-read after draft confirmation because saving it
    /// may move, rename, complete or remove the clicked record.
    func openReminder(_ target: ReminderTarget) async {
        showMainAction?()
        guard let repository else {
            status = "本机数据尚未就绪，请先完成数据恢复。"; return
        }
        guard !isBusy, !hasPendingWrites else {
            status = "本机数据正在处理，请完成后重新打开通知。"; return
        }
        do {
            let originalEditor = mainEditor
            try await validateReminderTarget(target, repository: repository)
            guard mainEditor === originalEditor else { return }
            guard await permitLeaving(mainEditor) else { return }
            guard !isBusy, !hasPendingWrites, self.repository === repository, mainEditor === originalEditor else {
                status = "本机数据已变更，请重新打开通知。"; return
            }
            switch target {
            case .task(let id):
                let configuration = try await repository.configuration()
                guard let item = try await repository.task(id: id), item.deletedAt == nil, !item.isRuleSuppressed else { throw DomainError.notFound }
                guard !isBusy, !hasPendingWrites, self.repository === repository, mainEditor === originalEditor else { return }
                status = ""
                section = .schedule; selectedDay = item.scheduledDay
                categoryFilter = nil; completionFilter = .all; search = ""
                mainEditor = EditorSession(item: item, configuration: configuration, clock: clock)
            case .countdown(let id):
                guard let event = try await repository.countdown(id: id), event.deletedAt == nil else { throw DomainError.notFound }
                guard !isBusy, !hasPendingWrites, self.repository === repository, mainEditor === originalEditor else { return }
                status = ""
                section = .countdowns; search = ""
                mainEditor = EditorSession(event: event, clock: clock)
                if event.archivedAt != nil { status = "此倒计时已归档；可在右侧查看或修改。" }
            }
            await refresh()
        } catch {
            status = (error as? DomainError) == .notFound
                ? "这条提醒对应的事项已删除或不再可用。"
                : "暂时无法打开这条提醒：\(error.localizedDescription)"
        }
    }
    private func validateReminderTarget(_ target: ReminderTarget, repository: TodoRepository) async throws {
        switch target {
        case .task(let id):
            guard let item = try await repository.task(id: id), item.deletedAt == nil, !item.isRuleSuppressed else { throw DomainError.notFound }
        case .countdown(let id):
            guard let event = try await repository.countdown(id: id), event.deletedAt == nil else { throw DomainError.notFound }
        }
    }
}
