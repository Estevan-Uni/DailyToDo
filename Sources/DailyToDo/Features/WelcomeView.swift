import SwiftUI

/// One local welcome sheet. It never requests notification or login permission.
struct WelcomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("日程与倒计时", systemImage: "calendar").font(.title2.weight(.semibold))
            Text("点击日历日期下的空白新建，点击事项编辑。完成后在 App 原位划线，卡片只显示未完成事项。")
            Text("卡片固定在桌面，点击桌面不会收起；关闭主窗口后仍保留，退出 App 后关闭。未完成的单次待办会自动顺延。")
                .foregroundStyle(.secondary)
            Toggle("显示桌面卡片", isOn: Binding(get: { model.cardVisible }, set: { value in
                if value { model.cardController?.show(activate: false) } else { model.cardController?.hide() }
            }))
            HStack {
                Text("数据保存在这台 Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("开始使用") { model.finishWelcome() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).accessibilityIdentifier("welcome-start")
            }
        }.padding(28).frame(width: 420)
            .onDisappear { model.finishWelcome() }
    }
}
