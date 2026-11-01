import SwiftUI
import TodoDomain

@MainActor enum TaskCompletionInput {
    static var acceptsCurrentEvent: Bool {
        guard let event = NSApp.currentEvent else { return true }
        switch event.type {
        case .leftMouseDown, .leftMouseUp: return event.clickCount <= 1
        case .keyDown: return !event.isARepeat
        default: return true
        }
    }
}

/// Shared task controls for the card, menu bar and day overflow list.
struct TaskRow: View {
    @Bindable var model: AppModel
    let item: TodoItem
    var showDay = false
    var compact = false
    let onSelect: (_ showDatePicker: Bool) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { if TaskCompletionInput.acceptsCurrentEvent { Task { await model.toggle(item) } } } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.system(size: 20, weight: .light)).foregroundStyle(item.completedAt == nil ? Color.secondary : Color.accentColor).frame(width: 24, height: 26)
            }.buttonStyle(.plain).disabled(item.deletedAt != nil).help(item.completedAt == nil ? "完成此项" : "取消完成").accessibilityLabel("\(item.completedAt == nil ? "完成" : "取消完成")：\(item.title)")
            Button { onSelect(false) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) { Text(item.title).font(compact ? .callout.weight(.medium) : .body.weight(.medium)).strikethrough(item.completedAt != nil).foregroundStyle(item.completedAt == nil ? .primary : .secondary).lineLimit(2); if item.isImportant { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange) }; Spacer(minLength: 0) }
                    HStack(spacing: 6) {
                        if showDay { Text(item.scheduledDay.description).monospacedDigit() }
                        if item.hasScheduledTime { Text(item.timeLabel).monospacedDigit() }
                        CategoryDot(hex: model.category(item.categoryID)?.colorHex ?? "#83908B")
                        Text(model.category(item.categoryID)?.name ?? "未知类型").lineLimit(1).help(model.category(item.categoryID)?.name ?? "未知类型")
                        if item.seriesID != nil { Label(model.repeatLabel(item), systemImage: "repeat").font(.caption2).fixedSize().accessibilityLabel("\(model.repeatLabel(item))固定待办") }
                    }.font(.caption).foregroundStyle(.secondary)
                    if model.hasPassed(item) { Text("已过时间").font(.caption2).foregroundStyle(.secondary) }
                    LocalTimeNotice(day: item.scheduledDay, minute: item.scheduledMinute)
                    if !compact, let completed = item.completedAt { Text("完成于 \(model.clock.formatted(completed))").font(.caption2).foregroundStyle(.tertiary) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.contextMenu { TaskContextMenu(model: model, item: item, onEdit: onSelect) }
    }
}

/// Identical record actions are available in every calendar cell and task row.
struct TaskContextMenu: View {
    @Bindable var model: AppModel
    let item: TodoItem
    let onEdit: (_ showDatePicker: Bool) -> Void
    var body: some View {
        if item.deletedAt == nil {
            Button("编辑") { onEdit(false) }
            Button("选择日期…") { onEdit(true) }
            if item.completedAt == nil {
                Button("移到明天") { Task { await model.quickEdit(item, change: .moveToTomorrow) } }
            }
            Button(item.isImportant ? "取消重要标记" : "标为重要") { Task { await model.quickEdit(item, change: .setImportant(!item.isImportant)) } }
            Divider()
            Button(item.seriesID == nil ? "删除" : "删除本次", role: .destructive) { Task { await model.delete(item) } }
            if item.seriesID != nil, item.completedAt == nil, let origin = item.occurrenceDay, origin >= model.today {
                Divider()
                Button("停止本次及以后…", role: .destructive) { Task { await model.stopFollowing(item) } }
            }
        }
    }
}
