import SwiftUI
import TodoDomain

struct EditorView: View {
    @Bindable var model: AppModel
    @Bindable var editor: EditorSession
    var onCard = false
    var onClose: (() -> Void)?
    @FocusState private var titleFocused: Bool
    @FocusState private var timeFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editor.title).font(.headline)
                Spacer()
                if editor.dirty { Text("未保存").font(.caption).foregroundStyle(.secondary) }
                if let onClose { Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭编辑").accessibilityIdentifier("editor-close") }
            }.padding(20)
            Divider()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if editor.kind == .task { taskFields } else { countdownFields }
                    if editor.kind == .countdown || editor.task.frequency == nil || (editor.wasRecurring && editor.task.scope == .onlyThis) {
                    Divider()
                    Toggle("设置提醒", isOn: Binding(get: { editor.reminderEnabled }, set: { enabled in
                        editor.reminderEnabled = enabled
                        if enabled { Task { await model.requestRemindersFromEditor() } }
                    })).id(EditorSession.Field.reminder)
                    if editor.reminderEnabled {
                        if editor.isChangingReminderSchedule {
                            Toggle("同时调整提醒", isOn: $editor.adjustReminderWithSchedule)
                            if editor.adjustReminderWithSchedule {
                                if let proposal = editor.reminderRescheduleProposal {
                                    LabeledContent("新提醒时间", value: editor.clock.formatted(proposal, date: .numeric))
                                    if proposal <= model.clockNow { Text("新提醒时间已过去，请调整计划时间或取消联动后另选提醒。").font(.caption).foregroundStyle(.red) }
                                } else { Text("无法计算合法的新提醒，请调整计划时间或取消联动。").font(.caption).foregroundStyle(.red) }
                            }
                            Text("默认保留提醒。勾选后按原提醒与原计划时刻的时间间隔平移；跨夏令时按实际时刻计算。").font(.caption).foregroundStyle(.secondary)
                        }
                        if !editor.adjustReminderWithSchedule || !editor.isChangingReminderSchedule {
                            DatePicker("提醒时间", selection: $editor.reminderDate, displayedComponents: [.date, .hourAndMinute])
                        }
                        if editor.kind == .countdown {
                            Button("目标日 09:00") {
                                do { try editor.useTargetMorningReminder() }
                                catch { editor.error = error.localizedDescription }
                            }.font(.caption).help("使用目标日期在当前本地时区的上午九点")
                        }
                        reminderHelp
                    }
                    }
                    if editor.isConflict || editor.recordUnavailable {
                        HStack {
                            if !editor.recordUnavailable { Button("重新载入") { Task { await model.reload(editor, onCard: onCard) } } }
                            Button("另存为新事项") { editor.copyAsNew() }
                        }.id(EditorSession.Field.recovery)
                        Text(editor.recordUnavailable ? "原记录已删除或不再可编辑；草稿仍保留，可另存为新事项。" : "重新载入会丢弃当前草稿；可先复制文本，或另存为新事项。").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .onChange(of: editor.validationRequest) { _, _ in
                let field = editor.validationField ?? .recovery
                proxy.scrollTo(field, anchor: .center)
                titleFocused = field == .title; timeFocused = field == .time
            }
            }
            Divider()
            if let error = editor.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 10)
            }
            HStack {
                if editor.isNew {
                    Button("保存并继续") { Task { await model.saveAndContinue(editor) } }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(editor.isSaving || model.repository == nil)
                        .help("保存并新建下一项，保留日期、时间和类型（⇧⌘↩）")
                        .accessibilityIdentifier("editor-save-continue")
                }
                Spacer()
                Button("保存") { Task { if await model.save(editor), onCard { onClose?() } } }
                    .keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(editor.isSaving || model.repository == nil)
                    .accessibilityIdentifier("editor-save")
            }.padding(16)
        }
        .background(.background)
        .accessibilityElement(children: .contain).accessibilityIdentifier(onCard ? "card-editor" : "main-editor")
        .disabled(model.isBusy || editor.isSaving)
        .appTheme(model)
        .task(id: editor.id) { titleFocused = editor.focusTitleOnOpen }
    }
    private var taskFields: some View {
        Group {
            TextField("事项（必填）", text: $editor.task.title, axis: .vertical)
                .font(.title2.weight(.semibold)).textFieldStyle(.plain).lineLimit(1...4).focused($titleFocused)
                .accessibilityLabel("待办事项，必填")
                .accessibilityIdentifier("editor-title")
                .id(EditorSession.Field.title)
            if let completedAt = editor.completedAt {
                Text("完成于 \(editor.clock.formatted(completedAt))").font(.caption).foregroundStyle(.secondary)
            }
            if let source = editor.copySourceName { Text("复制自“\(source)”。请选择新开始日期；保存后建立新系列，旧记录不变。").font(.caption).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 12) {
                if editor.wasRecurring, editor.task.scope == .thisAndFollowing, editor.task.frequency != nil, let start = editor.task.effectiveFromDay {
                    LabeledContent("规则生效日期", value: start.description).id(EditorSession.Field.date)
                } else {
                    CivilDateField(label: editor.copySourceName == nil ? "日期 *" : "新开始日期 *", text: $editor.dayText, identifier: "editor-date", showInitially: editor.showDatePicker, onInitialPresentation: { editor.showDatePicker = false })
                        .id(EditorSession.Field.date)
                }
                LabeledContent("时间（选填）") {
                    TextField("HH:mm", text: $editor.timeText).frame(width: 100).textFieldStyle(.roundedBorder).focused($timeFocused).accessibilityLabel("待办时间，24小时制，选填；留空表示未设时间").accessibilityIdentifier("editor-time")
                }.id(EditorSession.Field.time)
                if (editor.task.frequency == nil || (editor.wasRecurring && editor.task.scope == .onlyThis)), let day = try? LocalDate(editor.dayText.trimmingCharacters(in: .whitespacesAndNewlines)), let minute = try? EditorSession.minute(editor.timeText) {
                    LocalTimeNotice(day: day, minute: minute)
                }
                CategorySelection(model: model, selection: $editor.task.categoryID).id(EditorSession.Field.category)
                Toggle("重要", isOn: $editor.task.isImportant)
            }
            if editor.wasRecurring {
                Picker("修改范围", selection: $editor.task.scope) {
                    Text("仅本次").tag(EditScope.onlyThis)
                    if !editor.wasCompleted, (editor.task.effectiveFromDay ?? editor.task.day) >= model.today { Text("本次及以后").tag(EditScope.thisAndFollowing) }
                }.pickerStyle(.menu)
                Text("原发生日：\(editor.task.effectiveFromDay?.description ?? editor.dayText)。已完成历史与单次例外独立保留。").font(.caption).foregroundStyle(.secondary)
            }
            if !editor.wasCompleted && (!editor.wasRecurring || editor.task.scope == .thisAndFollowing) {
                Picker("重复", selection: $editor.task.frequency) {
                    Text("不重复").tag(Optional<RepeatFrequency>.none)
                    Text("每日").tag(Optional(RepeatFrequency.daily))
                    Text("每周").tag(Optional(RepeatFrequency.weekly))
                }.id(EditorSession.Field.recurrence).accessibilityIdentifier("editor-repeat")
                if editor.task.frequency == .weekly {
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if editor.task.weekdays.contains(day) { editor.task.weekdays.remove(day) } else { editor.task.weekdays.insert(day) }
                            } label: {
                                Text(["一", "二", "三", "四", "五", "六", "日"][day - 1]).font(.callout)
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .foregroundStyle(editor.task.weekdays.contains(day) ? Color.accentColor : .primary)
                                    .background(editor.task.weekdays.contains(day) ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("星期\(["一", "二", "三", "四", "五", "六", "日"][day - 1])")
                                .accessibilityValue(editor.task.weekdays.contains(day) ? "已选择" : "未选择")
                        }
                    }
                }
                if editor.task.frequency != nil {
                    CivilDateField(label: "结束日期", text: $editor.endText, optional: true)
                    Picker("重复提醒", selection: Binding(get: { editor.task.reminderOffsetMinutes }, set: { value in
                        editor.task.reminderOffsetMinutes = value
                        if value != nil { Task { await model.requestRemindersFromEditor() } }
                    })) {
                        Text("不提醒").tag(Optional<Int>.none)
                        Text("准时").tag(Optional(0)); Text("提前 5 分钟").tag(Optional(5)); Text("提前 15 分钟").tag(Optional(15)); Text("提前 1 小时").tag(Optional(60)); Text("提前 1 天").tag(Optional(1440))
                    }
                    if editor.timeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("未设时间仍可重复。使用重复提醒时，请填写时间；也可选择不提醒。").font(.caption).foregroundStyle(.secondary)
                    }
                    if editor.task.reminderOffsetMinutes != nil { reminderHelp }
                    Text("按本地日期与时间重复；每次发生单独完成。不重复将停止本次及以后的规则，并把当前事项保留为独立待办。").font(.caption).foregroundStyle(.secondary)
                    RecurrenceDraftPreview(model: model, editor: editor)
                }
            }
            notes($editor.task.notes)
        }
    }
    private var reminderHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let warning = model.services.savedReminderWarning {
                Text(warning).foregroundStyle(.secondary)
                Button("打开系统通知设置") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }.buttonStyle(.link)
            }
            Text("保存后安排提醒；已过去的提醒不会补发。").foregroundStyle(.secondary)
        }.font(.caption)
    }
    private var countdownFields: some View {
        Group {
            TextField("事件（必填）", text: $editor.countdown.title, axis: .vertical)
                .font(.title2.weight(.semibold)).textFieldStyle(.plain).lineLimit(1...4).focused($titleFocused).accessibilityLabel("倒计时事件，必填").accessibilityIdentifier("editor-title").id(EditorSession.Field.title)
            CivilDateField(label: "目标日期 *", text: $editor.dayText, identifier: "editor-date").id(EditorSession.Field.date)
            Text("按自然日计算。当天显示“就是今天”，过期后仍保留。").font(.caption).foregroundStyle(.secondary)
            notes($editor.countdown.notes)
        }
    }
    private func notes(_ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").foregroundStyle(.secondary)
            TextEditor(text: binding).font(.body).frame(height: 112).scrollContentBackground(.hidden).padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("备注")
        }.id(EditorSession.Field.notes)
    }
}

struct CivilDateField: View {
    @Environment(\.appClock) private var clock
    let label: String
    @Binding var text: String
    var identifier: String? = nil
    var optional = false
    var showInitially = false
    var onInitialPresentation: (() -> Void)?
    @State private var showCalendar = false
    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 10)
            HStack {
                TextField(optional ? "不限" : "YYYY-MM-DD", text: $text).frame(width: 124).textFieldStyle(.roundedBorder).accessibilityLabel(label).accessibilityIdentifier(identifier ?? "civil-date-\(label)")
                Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }.help("选择日期")
                    .popover(isPresented: $showCalendar) {
                        VStack {
                            NativeCalendar(date: Binding(get: { (try? LocalDate(text))?.noon(timeZone: clock.timeZone()) ?? clock.now() }, set: { text = clock.day(at: $0).description }), clock: clock).frame(width: 270, height: 190)
                            HStack {
                                Button("今天") { text = clock.today.description; showCalendar = false }
                                Button("完成") { showCalendar = false }
                            }.padding(.bottom, 12)
                        }
                    }
                if optional && !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("清除结束日期") }
            }
        }.accessibilityElement(children: .contain)
            .onAppear { if showInitially { showCalendar = true; onInitialPresentation?() } }
    }
}

struct NativeCalendar: NSViewRepresentable {
    @Binding var date: Date
    var clock: AppClock
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let view = NSDatePicker(); view.datePickerStyle = .clockAndCalendar; view.datePickerElements = .yearMonthDay
        view.calendar = clock.calendar; view.timeZone = clock.timeZone()
        view.minDate = try? LocalDate(year: 1900, month: 1, day: 1).noon(timeZone: clock.timeZone()); view.maxDate = try? LocalDate(year: 9999, month: 12, day: 31).noon(timeZone: clock.timeZone())
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:)); return view
    }
    func updateNSView(_ view: NSDatePicker, context: Context) {
        context.coordinator.parent = self; view.calendar = clock.calendar; view.timeZone = clock.timeZone(); view.dateValue = date
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeCalendar
        init(_ parent: NativeCalendar) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}

struct CategoryEditor: View {
    @Bindable var model: AppModel
    var original: TodoCategory?
    var onSaved: ((TodoCategory) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: Color = Color(hex: "#64967C")
    @State private var colorValid = true
    @State private var error: String?
    @State private var saving = false
    @State private var paletteRevision = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(original == nil ? "新建类型" : "编辑类型").font(.title2.weight(.semibold))
            TextField("名称（1–12 字）", text: $name).disabled(original?.isSystemDefault == true)
            CategoryColorPresets { color = $0; paletteRevision += 1 }
            ColorInput(title: "类型颜色", selection: $color, onValidityChange: { colorValid = $0 }).id(paletteRevision)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") {
                Task {
                    saving = true; defer { saving = false }
                    do {
                        var item = original ?? TodoCategory(name: name, colorHex: color.rgbHex, sortOrder: model.categories.count)
                        item.name = name; item.colorHex = color.rgbHex
                        let saved = try await model.write { try await $0.saveCategory(item, baseRevision: original?.revision ?? 0) }
                        await model.refresh(); onSaved?(saved); dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.buttonStyle(.borderedProminent).disabled(saving || !colorValid) }
        }.padding(28).frame(width: 350).disabled(saving || model.isBusy)
        .onAppear { if let original { name = original.name; color = Color(hex: original.colorHex) } }
    }
}
