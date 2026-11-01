import SwiftUI
import TodoInteraction

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("floatingCard") private var floatingCard = false
    var body: some View {
        Form {
            Section("外观") { ThemeControls(model: model) }
            Section("桌面卡片") {
                Toggle("卡片保持在其他窗口上方", isOn: $floatingCard).onChange(of: floatingCard) { _, _ in model.cardController?.updateLevel() }
                HStack { Button("显示卡片") { model.cardController?.show() }; Button("隐藏卡片") { model.cardController?.hide() } }
                Button("恢复卡片位置") { model.cardController?.resetPosition() }.disabled(model.cardController == nil)
                if let issue = model.cardPositionIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                Text("默认使用普通窗口层级。卡片可从标题区拖动、从边缘调整大小。").font(.caption).foregroundStyle(.secondary)
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
