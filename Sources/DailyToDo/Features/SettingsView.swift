import SwiftUI
import TodoInteraction

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("floatingCard") private var floatingCard = false
    var body: some View {
        Form {
            Section("外观") { ThemeControls(model: model) }
            Section("桌面卡片") {
                CardAppearanceControls(model: model)
                Toggle("卡片保持在其他窗口上方", isOn: $floatingCard).onChange(of: floatingCard) { _, _ in model.cardController?.updateLevel() }
                HStack { Button("显示卡片") { model.cardController?.show() }; Button("隐藏卡片") { model.cardController?.hide() } }
                Button("恢复卡片位置") { model.cardController?.resetPosition() }.disabled(model.cardController == nil)
                if let issue = model.cardPositionIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                Text("默认固定在桌面，点击桌面或切换 App 时保留，其他窗口可以覆盖。开启置顶后显示在其他窗口上方。卡片可拖动和调整大小；退出 App 后关闭。").font(.caption).foregroundStyle(.secondary)
            }
            Section("系统") {
                Toggle("允许事项提醒", isOn: Binding(get: { model.services.notificationsEnabled }, set: { value in Task { await model.services.setNotifications(value, repository: model.repository) } }))
                Text(model.services.notificationStatus).font(.caption).foregroundStyle(.secondary)
                Text("最多预排 48 条；重复提醒覆盖未来 30 天。App 运行时会补充队列，长期退出无法继续补充。").font(.caption).foregroundStyle(.secondary)
                Button("重新核对提醒") { Task { await model.services.reconcile(model.repository) } }.disabled(!model.services.notificationsEnabled)
                Button("打开系统通知设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }
                Toggle("登录时启动", isOn: Binding(get: { model.services.loginEnabled }, set: { model.services.setLogin($0) }))
            }
            Section("本机数据") {
                Text("非周期待办当天未完成，会自动顺延到次日；关闭 App 多天后启动时补移到今天。周期待办保留各次原日期。").font(.caption).foregroundStyle(.secondary)
                HStack { Button("导出备份…") { Task { await model.exportJSON() } }; Button("从备份恢复…") { Task { await model.restoreJSON() } } }.disabled(model.repository == nil || model.isBusy)
                Text("恢复会替换全部数据；替换前自动保存原数据备份。最近删除保留 30 天。").font(.caption).foregroundStyle(.secondary)
                Text(model.storageURL.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section { Text("DailyToDo 0.1 · macOS 14+\n本机保存，无需账户。⌘N 新建，⌘↩ 保存。").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).padding(12).frame(width: 520, height: 650)
            .alert("系统服务", isPresented: Binding(get: { model.services.serviceError != nil }, set: { if !$0 { model.services.serviceError = nil } })) { Button("好") { model.services.serviceError = nil } } message: { Text(model.services.serviceError ?? "") }
    }
}

/// The same controls are available in Settings and directly on the desktop card.
/// Only the backdrop changes opacity; content never inherits a window alpha.
struct CardAppearanceControls: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("背景不透明度")
                Spacer()
                Text(model.cardBackgroundOpacity.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("通透").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.cardBackgroundOpacity, in: 0...1, step: 0.01) { Text("背景不透明度") }
                    .labelsHidden().accessibilityLabel("背景不透明度")
                    .accessibilityIdentifier("card-background-opacity")
                    .disabled(reduceTransparency)
                Text("实色").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("使用主题色染色", isOn: $model.cardThemeTint)
                .accessibilityIdentifier("card-theme-tint").disabled(reduceTransparency)
            if reduceTransparency {
                Text("系统已开启“减少透明度”，卡片使用实色背景；关闭该系统选项后恢复所选效果。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if contrast == .increased {
                Text("系统已开启“增强对比度”，背景至少保留 65% 遮罩，优先保证可读性。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("只调节背景，文字保持清晰。通透端仍保留系统磨砂；染色跟随主题颜色。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("恢复默认磨砂") { model.cardBackgroundOpacity = 0.18; model.cardThemeTint = true }
                .accessibilityIdentifier("card-appearance-reset")
        }
    }
}

struct ThemeControls: View {
    @Bindable var model: AppModel
    private let colors = ["#4B8E83", "#5D7DA6", "#8974A2", "#B57E85", "#B38B57", "#747C85"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("主题颜色").font(.headline)
            HStack(spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button { model.themeColorHex = color } label: {
                        Circle().fill(Color(hex: color)).frame(width: 25, height: 25)
                            .overlay { if model.themeColorHex.uppercased() == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: SRGBColor(hex: color)!.foreground.hex)) } }
                    }.buttonStyle(.plain).accessibilityLabel("主题色 \(color)")
                }
            }
            ColorInput(title: "自定义颜色", selection: Binding(get: { Color(hex: model.themeColorHex) }, set: { model.themeColorHex = $0.rgbHex }))
            Text("应用于日历、按钮与桌面卡片。显示色随深浅外观调整，所选颜色保存在本机。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
