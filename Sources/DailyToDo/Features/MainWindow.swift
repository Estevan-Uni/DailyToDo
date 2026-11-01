import SwiftUI
import TodoDomain

private enum ManagementSheet: String, Identifiable {
    case categories, fixed, trash
    var id: String { rawValue }
}

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var management: ManagementSheet?
    @State private var showAppearance = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarSelection: AppSection? = .schedule
    @State private var navigating = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    List(selection: $sidebarSelection) {
                        Section("安排") {
                            ForEach(AppSection.allCases) { section in
                                Label(section.rawValue, systemImage: section.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                                    .tag(section)
                            }
                        }
                    }.listStyle(.sidebar)
                        .onChange(of: sidebarSelection) { _, next in
                            guard let next, next != model.section else { return }
                            guard !navigating else { sidebarSelection = model.section; return }
                            navigating = true
                            Task {
                                await model.navigate(next)
                                // Native List updates selection before async draft
                                // approval. Restore it if the user keeps editing.
                                sidebarSelection = model.section; navigating = false
                            }
                        }
                        .onChange(of: model.section) { _, next in sidebarSelection = next }
                    VStack(alignment: .leading, spacing: 16) {
                        Button { model.cardController?.toggle() } label: { Label("桌面卡片", systemImage: "rectangle.split.2x1") }.disabled(model.cardController == nil)
                        Button { model.showSettingsAction?() } label: { Label("设置", systemImage: "gearshape") }
                    }.buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 220)
            } detail: {
                HStack(spacing: 0) {
                    Group {
                        if model.isLoading { ProgressView("正在打开本机数据…") }
                        else if model.repository == nil { DataRecoveryView(model: model) }
                        else if model.section == .schedule { ScheduleCalendarView(model: model) }
                        else {
                            VStack(spacing: 0) {
                                listHeader; Divider(); recordList
                                MainStatusBar(model: model, fallback: "\(model.events.count) 个倒计时")
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let editor = model.mainEditor {
                        Divider()
                        EditorView(model: model, editor: editor, onClose: {
                            Task { if await model.permitLeaving(model.mainEditor) { model.mainEditor = nil } }
                        }).id(editor.id).frame(width: min(380, max(340, geometry.size.width * 0.33)))
                    }
                }
            }
            .onChange(of: model.mainEditor?.id) { _, _ in adjustSidebar(width: geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in adjustSidebar(width: width) }
        }
        .frame(minWidth: 860, minHeight: 560)
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView(model.busyMessage).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .toolbar {
            ToolbarItemGroup {
                if columnVisibility == .detailOnly {
                    Menu(model.section.rawValue) { ForEach(AppSection.allCases) { section in Button(section.rawValue) { Task { await model.navigate(section) } } } }
                }
                Button { Task { await model.create(kind: model.section == .countdowns ? .countdown : .task) } } label: { Label("新建", systemImage: "plus") }.help("新建事项（⌘N）").disabled(model.repository == nil).accessibilityIdentifier("new-item")
                Button { showAppearance.toggle() } label: { Label("主题颜色", systemImage: "paintpalette") }
                    .popover(isPresented: $showAppearance) { ThemeControls(model: model).padding(22).frame(width: 290) }
                Button { model.cardController?.toggle() } label: { Label("桌面卡片", systemImage: "rectangle.split.2x1") }.disabled(model.cardController == nil).accessibilityIdentifier("desktop-card-toggle")
                Menu {
                    if model.repository != nil {
                    if model.section == .schedule {
                        Button("管理待办类型…") { management = .categories }
                        Button("管理重复规则…") { management = .fixed }
                        Divider()
                    }
                    Button(model.section == .schedule ? "最近删除的待办…" : "最近删除的倒计时…") { management = .trash }
                    Divider()
                    Button("导出备份…") { Task { await model.exportJSON() } }
                    Button("从备份恢复…") { Task { await model.restoreJSON() } }
                    }
                    Button("设置…") { model.showSettingsAction?() }
                } label: { Label("更多", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(item: $management) { sheet in
            VStack(spacing: 0) {
                HStack { Text(sheet == .categories ? "待办类型" : sheet == .fixed ? "重复规则" : "最近删除").font(.headline); Spacer(); Button("完成") { management = nil } }.padding(20)
                Divider()
                switch sheet {
                case .categories: CategoryList(model: model)
                case .fixed: FixedRulesView(model: model, onEdit: { management = nil })
                case .trash: TrashView(model: model, kind: model.section == .schedule ? .task : .countdown)
                }
            }.frame(width: 470, height: 550)
        }
        .sheet(isPresented: $model.showWelcome) { WelcomeView(model: model) }
        .task { await model.boot() }
        .onChange(of: model.searchRequest) { _, _ in if model.section == .countdowns { searchFocused = true } }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func adjustSidebar(width: CGFloat) {
        if model.mainEditor != nil && width < 1180 { columnVisibility = .detailOnly }
        else if model.mainEditor == nil { columnVisibility = .all }
    }
    private var listHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) { Text("倒计时").font(.title2.weight(.bold)); Text("重要的日子，一眼可见").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索倒计时", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
            }.padding(8).frame(maxWidth: 240).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }.padding(24)
    }
    private var recordList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], alignment: .leading, spacing: 16) {
                if model.visibleEvents.isEmpty { empty("暂无倒计时", detail: "添加一个期待的日子。") }
                ForEach(model.visibleEvents) { event in countdownRow(event) }
            }.padding(24)
            if !model.archivedEvents.isEmpty {
                DisclosureGroup("已归档（\(model.archivedEvents.count)）") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 16) {
                        ForEach(model.archivedEvents.filter { model.search.isEmpty || $0.title.localizedStandardContains(model.search) }) { event in countdownRow(event) }
                    }.padding(.top, 12)
                }.padding(24)
            }
        }
    }
    private func countdownRow(_ event: CountdownEvent) -> some View {
        Button { Task { await model.edit(event) } } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) { Text(event.title).font(.headline).lineLimit(2); Text(event.targetDay.description).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Text(event.label(from: model.today)).font(.callout.weight(.medium)).foregroundStyle(event.days(from: model.today) < 0 ? .secondary : Color.accentColor)
            }.contentShape(Rectangle()).padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("countdown-event-\(event.id)")
            .contextMenu {
                Button(event.archivedAt == nil ? "归档" : "取消归档") { Task { await model.changeCountdown(event) } }
                Button("删除", role: .destructive) { Task { await model.changeCountdown(event, delete: true) } }
            }
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) { Image(systemName: model.section.symbol).font(.system(size: 28, weight: .light)); Text(title).font(.headline); Text(detail).font(.caption).multilineTextAlignment(.center) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 44)
    }
}

/// A reserved row keeps save/reminder feedback visible without resizing content.
struct MainStatusBar: View {
    @Bindable var model: AppModel
    let fallback: String
    var hint: String?
    var body: some View {
        HStack(spacing: 12) {
            Text(model.status.isEmpty ? fallback : model.status)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .help(model.status.isEmpty ? fallback : model.status)
            if !model.status.isEmpty, let action = model.undoStack.last {
                Button("撤销") { Task { await model.undo() } }.buttonStyle(.plain).font(.caption)
                    .help("撤销\(action.title)").accessibilityLabel("撤销\(action.title)")
            }
            Spacer(minLength: 0)
            if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
        }.padding(.horizontal, 20).frame(height: 32)
    }
}
