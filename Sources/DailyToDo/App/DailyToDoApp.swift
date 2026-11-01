import SwiftUI
import TodoDomain
import CoreServices
import TodoServices

@main
enum DailyToDoEntry {
    @MainActor
    static func main() {
        GUIProbe.begin()
        if #available(macOS 15, *) { DailyToDoApp.main() }
        else { LegacyDailyToDoApp.main() }
    }
}

@available(macOS 15, *)
struct DailyToDoApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        lifecycle.model = model
    }
    var body: some Scene {
        MainScene(model: model).defaultLaunchBehavior(.suppressed).restorationBehavior(.disabled)
        SupportingScenes(model: model, lifecycle: lifecycle)
    }
}

/// macOS 14 retains the same UI and the AppKit guard for background startup.
/// Split entry types avoid making the macOS 15 scene modifier a 14 runtime call.
private struct LegacyDailyToDoApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        lifecycle.model = model
    }
    var body: some Scene {
        MainScene(model: model)
        SupportingScenes(model: model, lifecycle: lifecycle)
    }
}

private struct SupportingScenes: Scene {
    var model: AppModel
    var lifecycle: AppLifecycle
    var body: some Scene {
        Settings { SettingsView(model: model).appTheme(model) }
        MenuBarExtra {
            MenuBarView(model: model).appTheme(model)
        } label: { LaunchBridge(model: model, lifecycle: lifecycle) }.menuBarExtraStyle(.window)
    }
}

private struct MainScene: Scene {
    var model: AppModel
    var body: some Scene {
        Window("DailyToDo", id: "main") {
            MainWindow(model: model).appTheme(model)
                .background(MainWindowGuard(model: model))
        }.defaultSize(width: 1120, height: 720)
            .commands { AppCommands(model: model) }
    }
}

/// The menu-bar label exists even when no window has been opened. Wire commands
/// here so login startup can load data and show the card without a main window.
private struct LaunchBridge: View {
    @Bindable var model: AppModel
    var lifecycle: AppLifecycle
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Image(systemName: "checklist").accessibilityLabel("DailyToDo")
            .onAppear {
                model.showMainAction = {
                    model.mainWindowRequested = true
                    // A canHide=false desktop card can be used while the App
                    // itself is hidden. Unhide before asking SwiftUI to open.
                    NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                model.showSettingsAction = { NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true); openSettings() }
                lifecycle.presentInitialWindowIfReady()
            }
    }
}

struct MenuBarView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("今天").font(.headline); Spacer(); Text(model.today.description).font(.caption).foregroundStyle(.secondary) }
            let items = model.cardItems.filter { $0.scheduledDay == model.today }
            if items.isEmpty { Text("今天暂无待办").foregroundStyle(.secondary).padding(.vertical, 8) }
            ForEach(Array(items.prefix(5))) { item in TaskRow(model: model, item: item, compact: true, onSelect: { showDate in model.showMainAction?(); Task { await model.edit(item, showDatePicker: showDate) } }) }
            if items.count > 5 { Button("查看全部 \(items.count) 项") { Task { await model.showTodayAgenda() } }.font(.caption).buttonStyle(.plain) }
            Divider()
            HStack { Button("新建待办") { model.showMainAction?(); Task { await model.create() } }; Button("新建倒计时") { model.showMainAction?(); Task { await model.create(kind: .countdown) } } }
            Button("显示 / 隐藏桌面卡片") { model.cardController?.toggle() }
            if let issue = model.cardPositionIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            HStack { Button("打开 App") { model.showMainAction?() }; Button("设置") { model.showSettingsAction?() }; Spacer(); Button("退出") { NSApp.terminate(nil) } }
        }.padding(20).frame(width: 340).task { await model.boot() }
    }
}

@MainActor final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private let notificationOpens = NotificationOpenQueue()
    private var notificationInteraction: NativeNotificationInteraction?
    private var quitting = false
    private var launchReady = false
    private var initialPresentationHandled = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        let interaction = NativeNotificationInteraction(queue: notificationOpens)
        notificationInteraction = interaction
        interaction.install()
        // Isolated native rehearsal of a cold-start click; never schedules or
        // delivers an OS notification, and ordinary launches ignore this flag.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--ui-test=") }),
           let value = arguments.first(where: { $0.hasPrefix("--ui-open-reminder=") }),
           let target = ReminderTarget(requestID: String(value.dropFirst("--ui-open-reminder=".count))) {
            notificationOpens.enqueue(target)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchReason = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        let isLogin = event?.eventID == AEEventID(kAEOpenApplication) &&
            (launchReason == keyAELaunchedAsLogInItem || launchReason == keyAELaunchedAsServiceItem)
        let arguments = ProcessInfo.processInfo.arguments
        let simulatedLogin = arguments.contains("--ui-login") && arguments.contains(where: { $0.hasPrefix("--ui-test=") })
        model.backgroundLaunch = isLogin || simulatedLogin
        // macOS 14 has no SceneLaunchBehavior; its initial window is hidden by
        // the window guard. macOS 15+ never automatically creates that window.
        if model.backgroundLaunch {
            NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.orderOut(nil) }
        }
        Task {
            await model.boot()
            launchReady = true
            presentInitialWindowIfReady()
        }
    }
    func presentInitialWindowIfReady() {
        guard launchReady, !initialPresentationHandled, let model, let showMain = model.showMainAction else { return }
        initialPresentationHandled = true
        if !model.backgroundLaunch { showMain() }
        notificationOpens.connect { [weak model] target in await model?.openReminder(target) }
        GUIProbe.observePresentation(model)
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test=") }) {
            // Startup evidence is emitted before UI tooling can send a reopen
            // event. Counts contain no schedule data or user file paths.
            let visibleMain = NSApp.windows.filter { $0.identifier?.rawValue == "main" && $0.isVisible }.count
            let line = "UI startup: background=\(model.backgroundLaunch), visibleMain=\(visibleMain), card=\(model.cardVisible), \(model.cardController?.geometrySummary ?? "cardUnavailable"), appearance=\(NSApp.effectiveAppearance.name.rawValue)\n"
            try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model?.showMainAction?(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !model.isBusy, !model.hasPendingWrites else { model.error = "本机数据正在处理，请完成或取消后再退出。"; return .terminateCancel }
        if quitting { return .terminateCancel }; quitting = true
        Task {
            let main = await model.permitLeaving(model.mainEditor)
            let card = main ? await model.permitLeaving(model.cardController?.editor) : false
            quitting = false; sender.reply(toApplicationShouldTerminate: main && card)
        }
        return .terminateLater
    }
}

struct MainWindowGuard: NSViewRepresentable {
    var model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.coordinator = context.coordinator; return view }
    func updateNSView(_ view: Probe, context: Context) {}
    @MainActor final class Probe: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                window.identifier = NSUserInterfaceItemIdentifier("main"); window.delegate = coordinator
                coordinator?.hideUnrequestedLoginWindow(window)
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let model: AppModel
        var checking = false
        init(model: AppModel) { self.model = model }
        func hideUnrequestedLoginWindow(_ window: NSWindow) {
            if model.backgroundLaunch && !model.mainWindowRequested { window.orderOut(nil) }
        }
        func windowDidBecomeMain(_ notification: Notification) {
            if let window = notification.object as? NSWindow { hideUnrequestedLoginWindow(window) }
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard !model.isBusy, !model.hasPendingWrites else { model.status = "请完成或取消本机数据操作后再关闭窗口。"; return false }
            guard !checking else { return false }; checking = true
            Task {
                if await model.permitLeaving(model.mainEditor) {
                    model.mainEditor = nil
                    sender.orderOut(nil)
                }
                checking = false
            }
            return false
        }
    }
}
