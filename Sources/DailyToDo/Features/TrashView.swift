import SwiftUI
import TodoDomain
import TodoPersistence

/// Recovery lives inside its source section, rather than adding another sidebar.
struct TrashView: View {
    @Bindable var model: AppModel
    let kind: EditorSession.Kind
    @State private var tasks: [TodoItem] = []
    @State private var events: [CountdownEvent] = []
    @State private var cursor: RecordCursor?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("删除后保留 30 天，可恢复到原来的日程或倒计时。").font(.caption).foregroundStyle(.secondary).padding(20)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal, 20) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if tasks.isEmpty && events.isEmpty && !loading { Text("没有最近删除的内容").foregroundStyle(.secondary).padding(.vertical, 30) }
                    ForEach(tasks) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            Text("\(item.scheduledDay.description) \(item.timeLabel)").font(.caption).foregroundStyle(.secondary)
                            if let origin = item.occurrenceDay { Text("重复实例 · 原发生日 \(origin.description)").font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("恢复") { run { repo in try await repo.restoreTask(id: item.id) } }
                                Button("永久删除", role: .destructive) { confirmPermanent { run { repo in try await repo.permanentlyDeleteTask(id: item.id) } } }
                            }.font(.caption)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title).font(.headline); Text(event.targetDay.description).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("恢复") { run { repo in try await repo.setCountdownState(id: event.id, deleted: false) } }
                                Button("永久删除", role: .destructive) { confirmPermanent { run { repo in try await repo.permanentlyDeleteCountdown(id: event.id) } } }
                            }.font(.caption)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if cursor != nil { Button("载入更多") { Task { await load(append: true) } }.disabled(loading) }
                }.padding(20)
            }
        }.task { await load() }
    }
    private func load(append: Bool = false) async {
        guard let repo = model.repository else { return }; loading = true; defer { loading = false }
        do {
            if kind == .task { let page = try await repo.deletedTasks(after: append ? cursor : nil); tasks = append ? tasks + page.items : page.items; cursor = page.nextCursor }
            else { events = try await repo.deletedCountdowns() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func run(_ operation: @escaping @MainActor (TodoRepository) async throws -> Void) {
        Task {
            do { try await model.write(operation); await load(); await model.maintainAndRefresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor private func confirmPermanent(_ action: () -> Void) {
    let alert = NSAlert(); alert.messageText = "永久删除这条记录？"; alert.informativeText = "无法恢复。重复事项的删除标记仍会保留，避免再次生成。"
    alert.addButton(withTitle: "永久删除"); alert.addButton(withTitle: "取消")
    if alert.runModal() == .alertFirstButtonReturn { action() }
}
