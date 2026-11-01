import AppKit
import SwiftUI
import TodoDomain
import TodoInteraction

@MainActor final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class DesktopCardController: NSObject, NSWindowDelegate {
    let model: AppModel
    private var panel: CardPanel!
    private var editorWindow: NSPanel?
    private var closingEditor = false
    private var screenObserver: NSObjectProtocol?
    private var applyingFrame = false
    var editor: EditorSession?
    var isVisible: Bool { panel.isVisible }
    var probeFrame: NSRect { panel.frame }
    func prepareProbeFrame() -> Bool {
        guard panel.isVisible else { return false }
        panel.contentView?.layoutSubtreeIfNeeded(); panel.displayIfNeeded(); return true
    }
    var geometrySummary: String {
        let contained = CardPosition.closest(to: panel.frame)?.visibleFrame.contains(panel.frame) ?? false
        return "cardSize=\(Int(panel.frame.width))x\(Int(panel.frame.height)), cardContained=\(contained)"
    }

    init(model: AppModel) {
        self.model = model; super.init()
        panel = CardPanel(contentRect: NSRect(x: 100, y: 180, width: 680, height: 400), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "DailyToDo 桌面卡片"; panel.identifier = NSUserInterfaceItemIdentifier("desktop-card")
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.minSize = NSSize(width: 600, height: 340); panel.maxSize = NSSize(width: 1100, height: 850)
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: DesktopCardView(model: model))
        if let frame = CardPosition.restore() { applyFrame(frame) }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--ui-test=") }), arguments.contains("--ui-minimum-card") {
            // An isolated launch fixture, not a normal preference or resize.
            // Preserve the top edge; applyFrame does not persist this geometry.
            var frame = panel.frame; frame.origin.y += frame.height - 340
            frame.size = NSSize(width: 600, height: 340); applyFrame(frame)
        }
        clampFrame(); updateLevel()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let frame = CardPosition.restore() { self.applyFrame(frame) }
                if UserDefaults.standard.bool(forKey: "showCard") { self.show(activate: false) }
                else { self.clampFrame() }
            }
        }
    }
    func show(activate: Bool = true) {
        clampFrame()
        UserDefaults.standard.set(true, forKey: "showCard")
        guard let screen = CardPosition.closest(to: panel.frame), PanelPlacement.canDisplay(on: CardPosition.screen(screen)) else {
            model.cardPositionIssue = "当前屏幕空间不足以显示桌面卡片，请在 App 中管理或恢复卡片位置。"
            model.status = model.cardPositionIssue!
            model.cardVisible = false; panel.orderOut(nil); return
        }
        model.cardPositionIssue = nil
        model.cardVisible = true
        if activate { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }
    func hide() { model.cardVisible = false; panel.orderOut(nil); UserDefaults.standard.set(false, forKey: "showCard") }
    func toggle() { if isVisible { hide() } else { show() } }
    func announce(_ message: String) {
        guard isVisible, let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func updateLevel() { panel.level = UserDefaults.standard.bool(forKey: "floatingCard") ? .floating : .normal }
    func resetPosition() {
        if let frame = CardPosition.reset() { applyFrame(frame); CardPosition.save(frame) }
        show()
    }
    private func applyFrame(_ frame: NSRect) {
        applyingFrame = true; panel.setFrame(frame, display: true); applyingFrame = false
        placeEditor()
    }
    func clampFrame() {
        let frame = panel.frame
        let screen = CardPosition.closest(to: frame)
        guard let visible = screen?.visibleFrame else { return }
        let width = min(max(frame.width, 600), visible.width), height = min(max(frame.height, 340), visible.height)
        let rect = NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - width), y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width, height: height)
        applyFrame(rect)
    }
    func windowDidMove(_ notification: Notification) { if notification.object as? NSWindow === panel, !applyingFrame { CardPosition.save(panel.frame) } }
    func windowDidEndLiveResize(_ notification: Notification) { clampFrame(); CardPosition.save(panel.frame) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { hide(); return false }
        guard !closingEditor else { return false }
        closingEditor = true
        Task {
            if await model.permitLeaving(editor) { discardEditor() }
            closingEditor = false
        }
        return false
    }
    func edit(_ next: EditorSession) async {
        guard await model.permitLeaving(editor) else { editorWindow?.makeKeyAndOrderFront(nil); return }
        // Saving the old draft can change the same record. Refresh only when
        // opening an existing task; never replace a new unsaved draft.
        if next.kind == .task, next.task.baseRevision > 0 {
            do {
                guard let latest = try await model.repository?.task(id: next.task.id), latest.deletedAt == nil, !latest.isRuleSuppressed else { throw DomainError.notFound }
                let fresh = EditorSession(item: latest, configuration: model.configuration, clock: model.clock); if next.showDatePicker { fresh.requestDateSelection() }
                replaceEditor(fresh)
            } catch { model.error = error.localizedDescription }
        } else if next.kind == .countdown, next.countdown.baseRevision > 0 {
            do {
                guard let latest = try await model.repository?.countdown(id: next.countdown.id), latest.deletedAt == nil, latest.archivedAt == nil else { throw DomainError.notFound }
                replaceEditor(EditorSession(event: latest, clock: model.clock))
            } catch { model.error = error.localizedDescription }
        } else { replaceEditor(next) }
    }
    func replaceEditor(_ next: EditorSession) {
        editor = next; model.cardEditing = true
        if editorWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 420, height: 480); window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false; window.delegate = self; window.title = "卡片编辑"
            editorWindow = window
        }
        editorWindow?.contentView = NSHostingView(rootView: EditorView(model: model, editor: next, onCard: true, onClose: { [weak self] in
            guard let self else { return }; Task { if await self.model.permitLeaving(self.editor) { self.discardEditor() } }
        }).id(next.id))
        if let editorWindow {
            placeEditor()
            panel.addChildWindow(editorWindow, ordered: .above)
            NSApp.activate(ignoringOtherApps: true); editorWindow.makeKeyAndOrderFront(nil)
        }
    }
    private func placeEditor() {
        guard let editorWindow, let area = (panel.screen ?? CardPosition.mainScreen)?.visibleFrame else { return }
        editorWindow.minSize = NSSize(width: min(420, area.width), height: min(480, area.height))
        let width = min(max(editorWindow.frame.width, editorWindow.minSize.width), area.width)
        let height = min(max(editorWindow.frame.height, editorWindow.minSize.height), area.height)
        let x = panel.frame.maxX + 12 + width < area.maxX ? panel.frame.maxX + 12 : panel.frame.minX - width - 12
        editorWindow.setFrame(NSRect(x: min(max(x, area.minX), area.maxX - width), y: min(max(panel.frame.maxY - height, area.minY), area.maxY - height), width: width, height: height), display: true)
    }
    func discardEditor() { if let editorWindow { panel.removeChildWindow(editorWindow); editorWindow.orderOut(nil) }; editor = nil; model.cardEditing = false }
}

struct DesktopCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var boundaryOffset: CGFloat = 0
    @State private var boundaryMessage: String?
    @State private var boundaryTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(.secondary)
                Text("DailyToDo").font(.callout.weight(.semibold))
                Spacer()
                Button { model.showMainAction?() } label: { Image(systemName: "arrow.up.right.square") }.help("打开主窗口").accessibilityIdentifier("card-open-main")
                Button { model.cardController?.hide() } label: { Image(systemName: "minus") }.help("隐藏卡片，可从菜单栏找回")
            }.buttonStyle(.plain).padding(.horizontal, 22).frame(height: 42).background(DragHandle())
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(model.cardDay == model.today ? "今天" : "\(model.cardDay.month) 月 \(model.cardDay.day) 日").font(.title3.weight(.semibold))
                        Spacer()
                        if model.cardIndex != 0 { Button("回今天") { selectDay(0) }.font(.caption).buttonStyle(.plain).help("返回系统今天的待办") }
                    }
                    dayStrip
                    HStack {
                        Button { changeDay(-1) } label: { Image(systemName: "chevron.left") }.disabled(model.cardIndex == 0).help("前一天").accessibilityIdentifier("card-previous-day")
                        Spacer()
                        Text(boundaryMessage ?? "\(model.cardDay.description) · \(model.cardItems.filter { $0.scheduledDay == model.cardDay }.count) 项").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Button { changeDay(1) } label: { Image(systemName: "chevron.right") }.disabled(model.cardIndex >= model.cardDays.count - 1).help("后一天").accessibilityIdentifier("card-next-day")
                    }.buttonStyle(.plain)
                    // Keep the bounded seven scroll views alive. Recreating one
                    // on each page change loses AppKit's native scroll offset.
                    GeometryReader { geometry in
                        ZStack {
                            ForEach(Array(model.cardDays.enumerated()), id: \.element) { index, day in
                                CardDayList(model: model, day: day)
                                    .opacity(day == model.cardDay ? 1 : 0)
                                    .offset(x: reduceMotion || index == model.cardIndex ? 0 : (index < model.cardIndex ? -geometry.size.width : geometry.size.width))
                                    .disabled(day != model.cardDay)
                                    .allowsHitTesting(day == model.cardDay)
                                    .accessibilityHidden(day != model.cardDay)
                                    .zIndex(day == model.cardDay ? 1 : 0)
                            }
                        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.cardIndex)
                            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
                            .offset(x: boundaryOffset)
                    }.clipped()
                    Button { Task { await model.create(onCard: true) } } label: { Label("添加待办", systemImage: "plus").font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("在卡片添加待办").accessibilityIdentifier("card-add-task")
                }
                .padding(.leading, 22).padding(.trailing, 18).padding(.bottom, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(GestureRegion(enabled: model.cardVisible && !model.cardEditing && !model.isBusy) { direction in changeDay(direction) })
                Rectangle().fill(.primary.opacity(0.09)).frame(width: 1).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("倒计时 · \(model.events.count)").font(.title3.weight(.semibold)); Spacer(); Button { Task { await model.create(kind: .countdown, onCard: true) } } label: { Image(systemName: "plus") }.help("在卡片添加倒计时").accessibilityIdentifier("card-add-countdown") }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if model.events.isEmpty {
                                VStack(spacing: 12) { Image(systemName: "hourglass").font(.system(size: 28, weight: .ultraLight)); Text("期待一个日子").font(.callout); Text("点击 + 添加倒计时").font(.caption) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 63)
                            }
                            ForEach(model.events) { event in
                                Button { Task { await model.edit(event, onCard: true) } } label: {
                                    CardCountdownTile(event: event, today: model.today)
                                }.buttonStyle(.plain).help("编辑倒计时：\(event.title)").id(event.id).accessibilityIdentifier("card-countdown-\(event.id)")
                                    .contextMenu {
                                        Button("编辑") { Task { await model.edit(event, onCard: true) } }
                                        Button("归档") { Task { await model.changeCountdown(event) } }
                                        Button("删除", role: .destructive) { Task { await model.changeCountdown(event, delete: true) } }
                                    }
                            }
                        }.scrollTargetLayout().padding(.trailing, 3)
                    }.scrollPosition(id: $model.cardCountdownAnchor, anchor: .top).accessibilityIdentifier("card-countdowns")
                }.padding(.leading, 18).padding(.trailing, 22).padding(.bottom, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.buttonStyle(.plain)
            HStack {
                Text(model.error ?? model.status).font(.caption).foregroundStyle(model.error == nil ? Color.secondary : .red).lineLimit(1)
                Spacer()
                if model.error != nil { Button("查看") { model.showMainAction?() } }
                else if !model.status.isEmpty, !model.undoStack.isEmpty { Button("撤销") { Task { await model.undo() } }.accessibilityIdentifier("card-undo") }
            }.buttonStyle(.plain).frame(height: 20).padding(.horizontal, 22).padding(.bottom, 8)
        }
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else {
                FrostedBackground().overlay(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.8 : 0.86))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(contrast == .increased ? Color.primary.opacity(0.65) : Color.white.opacity(0.22), lineWidth: contrast == .increased ? 2 : 1))
        .appTheme(model, onMaterial: true)
        .disabled(model.isBusy)
        .accessibilityElement(children: .contain).accessibilityLabel("DailyToDo 七天日程与倒计时桌面卡片")
        .onChange(of: model.cardIndex) { _, _ in
            boundaryTask?.cancel(); boundaryMessage = nil; boundaryOffset = 0
        }
        .onChange(of: reduceMotion) { _, value in if value { boundaryOffset = 0 } }
        .onDisappear { boundaryTask?.cancel(); boundaryTask = nil; boundaryOffset = 0; boundaryMessage = nil }
    }
    private var dayStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.cardDays.enumerated()), id: \.element) { index, day in
                Button { selectDay(index) } label: {
                    VStack(spacing: 6) {
                        Text(["一", "二", "三", "四", "五", "六", "日"][day.weekday - 1]).font(.system(size: 10))
                        Text("\(day.day)").font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                    }.frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(model.cardIndex == index ? Color.readableAccent(hex: model.themeColorHex, scheme: colorScheme, foreground: true, onMaterial: true) : Color.primary.opacity(0.7))
                        .background(model.cardIndex == index ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel("\(day.description)\(index == 0 ? "，今天" : "")")
                    .accessibilityValue("\(model.cardItems.filter { $0.scheduledDay == day }.count) 项未完成")
                    .accessibilityAddTraits(model.cardIndex == index ? .isSelected : [])
            }
        }.focusable()
            .onKeyPress(.leftArrow) { changeDay(-1); return .handled }
            .onKeyPress(.rightArrow) { changeDay(1); return .handled }
            .onKeyPress(.home) { selectDay(0); return .handled }
    }
    private func selectDay(_ index: Int) {
        guard model.cardDays.indices.contains(index), model.cardIndex != index else { return }
        model.cardIndex = index
        model.cardController?.announce("\(model.cardDay.description)，\(model.cardItems.filter { $0.scheduledDay == model.cardDay }.count) 项未完成")
    }
    private func changeDay(_ direction: Int) {
        let index = min(max(0, model.cardIndex + direction), max(0, model.cardDays.count - 1))
        guard index == model.cardIndex else { selectDay(index); return }
        boundaryTask?.cancel()
        boundaryMessage = direction < 0 ? "已到今天" : "已到七天范围的最后一天"
        model.cardController?.announce(boundaryMessage!)
        if !reduceMotion { withAnimation(.easeOut(duration: 0.08)) { boundaryOffset = direction < 0 ? 6 : -6 } }
        boundaryTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(90))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { boundaryOffset = 0 }
                try await Task.sleep(for: .milliseconds(1100))
                boundaryMessage = nil
            } catch {}
        }
    }
}

private struct CardDayList: View {
    @Bindable var model: AppModel
    let day: LocalDate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let items = model.cardItems.filter { $0.scheduledDay == day }
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    let completed = model.cardCompletedDays.contains(day)
                    VStack(spacing: 12) {
                        Image(systemName: completed ? "checkmark.circle" : "calendar").font(.system(size: 28, weight: .ultraLight))
                        Text(completed ? (day == model.today ? "今天的待办已完成" : "这一天的待办已完成") : (day == model.today ? "今天还没有安排" : "这一天还没有安排")).font(.callout)
                        Text("点击下方添加待办").font(.caption)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 32)
                }
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        TaskRow(model: model, item: item, compact: true, onSelect: { showDate in Task { await model.edit(item, onCard: true, showDatePicker: showDate) } }).padding(.vertical, 12)
                        if item.id != items.last?.id { Divider().opacity(0.5) }
                    }.id(item.id).transition(.opacity)
                }
            }.scrollTargetLayout().padding(.trailing, 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: items.map(\.id))
        }.scrollIndicators(.automatic).accessibilityIdentifier("card-tasks-\(day)")
            .scrollPosition(id: Binding(get: { model.cardTaskAnchors[day] }, set: { if let anchor = $0 { model.cardTaskAnchors[day] = anchor } }), anchor: .top)
    }
}

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView { let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active; return view }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    @MainActor final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// A single local monitor sees only the left pane of this exact window. Vertical
/// scrolling, editors and other apps retain the original event unchanged.
struct GestureRegion: NSViewRepresentable {
    var enabled = true
    var changeDay: (Int) -> Void
    func makeNSView(context: Context) -> RegionView { let view = RegionView(); view.changeDay = changeDay; view.setEnabled(enabled); return view }
    func updateNSView(_ view: RegionView, context: Context) { view.changeDay = changeDay; view.setEnabled(enabled) }
    static func dismantleNSView(_ view: RegionView, coordinator: ()) { view.removeMonitor() }
    @MainActor final class RegionView: NSView {
        var changeDay: ((Int) -> Void)?
        private var enabled = true
        var monitor: Any?
        private var paging = ScrollPaging()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            removeMonitor(); installMonitor()
        }
        func setEnabled(_ value: Bool) {
            enabled = value
            if enabled { installMonitor() } else { removeMonitor() }
        }
        private func installMonitor() {
            guard enabled, window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated { guard let self else { return false }; return self.route(event) == nil }
                return consumed ? nil : event
            }
        }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; paging.reset() }
        func route(_ event: NSEvent) -> NSEvent? {
            guard enabled, event.window === window else { paging.reset(); return event }
            let phase: TodoInteraction.ScrollPhase
            if event.momentumPhase.contains(.ended) { phase = .momentumEnded }
            else if event.momentumPhase.contains(.began) { phase = .momentumBegan }
            else if event.momentumPhase.contains(.changed) { phase = .momentumChanged }
            else if event.phase.contains(.cancelled) { phase = .cancelled }
            else if event.phase.contains(.began) { phase = .began }
            else if event.phase.contains(.ended) { phase = .ended }
            else if event.phase.contains(.changed) { phase = .changed }
            else { phase = .none }
            let result = paging.handle(.init(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, timestamp: event.timestamp,
                phase: phase, isPrecise: event.hasPreciseScrollingDeltas, insideRegion: bounds.contains(convert(event.locationInWindow, from: nil))), width: bounds.width)
            if let page = result.page { changeDay?(page) }
            return result.consumed ? nil : event
        }
    }
}
