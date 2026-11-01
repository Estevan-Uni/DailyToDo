import SwiftUI
import TodoDomain

struct RecurrenceDraftPreview: View {
    @Bindable var model: AppModel
    @Bindable var editor: EditorSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发生预览").font(.caption.weight(.semibold))
            if let preview = try? editor.recurrencePreview(today: model.today), let frequency = editor.task.frequency {
                Text(RecurrencePreview.summary(frequency: frequency, weekdays: editor.task.weekdays, minute: preview.minute, category: editor.task.categoryID.flatMap(model.category)?.name ?? "未选类型")).font(.caption)
                ForEach(preview.days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(day.description)  \(ScheduledTime.label(preview.minute, ifUnspecified: "未设时间"))").font(.caption).monospacedDigit()
                        LocalTimeNotice(day: day, minute: preview.minute)
                    }
                }
                if let first = preview.days.first {
                    if !editor.wasRecurring, first.description != editor.dayText.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text("所选开始日不匹配星期，当前事项将安排到首次发生日 \(first.description)。").font(.caption).foregroundStyle(.secondary)
                    } else if editor.wasRecurring, editor.task.effectiveFromDay != first {
                        Text("原发生日不匹配新规则，本次将隐藏；后续从 \(first.description) 起发生。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("按本地钟表时间。以结束日期和后续版本为准。").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("填写有效开始日期和重复星期后，可预览最近三次发生。").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).accessibilityElement(children: .contain).accessibilityIdentifier("recurrence-preview")
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
