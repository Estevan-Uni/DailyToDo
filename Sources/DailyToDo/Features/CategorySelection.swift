import SwiftUI
import TodoDomain

/// A small, fully labelled chooser shared by the main and card editors. Keeping
/// management on this host preserves the editor and never opens the main window.
struct CategorySelection: View {
    @Bindable var model: AppModel
    @Binding var selection: UUID?
    @State private var expanded = false
    @State private var destination: Destination?
    @State private var pending: Destination?
    @State private var highlightedID: UUID?
    @FocusState private var listFocused: Bool

    private enum Destination: String, Identifiable { case create, manage; var id: String { rawValue } }
    private var category: TodoCategory? { selection.flatMap(model.category) }

    var body: some View {
        LabeledContent("类型 *") {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    if let category { CategoryDot(hex: category.colorHex, size: 9) }
                    Text(category?.name ?? "请选择").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 3)
            }
            .accessibilityLabel("选择待办类型，必填")
            .accessibilityValue(category?.name ?? "未选择")
            .accessibilityIdentifier("editor-category")
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    List(selection: $highlightedID) {
                        ForEach(model.categories) { item in
                            VStack(spacing: 0) {
                                Button { choose(item.id) } label: {
                                    HStack(spacing: 10) {
                                        CategoryDot(hex: item.colorHex, size: 10)
                                        Text(item.name).lineLimit(1)
                                        Spacer()
                                        if selection == item.id { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                                    }.padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(item.name)
                                    .accessibilityValue(selection == item.id ? "已选择" : "未选择")
                                    .accessibilityIdentifier("category-option-\(item.id)")
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityAction { choose(item.id) }
                            .onTapGesture { choose(item.id) }
                            .tag(item.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
                        }
                    }.listStyle(.plain)
                        .frame(height: min(CGFloat(model.categories.count) * 34 + 12, 250))
                        .focused($listFocused)
                        .accessibilityLabel("选择待办类型")
                        .accessibilityIdentifier("category-options")
                        .onKeyPress(.return) { chooseHighlighted() }
                        .onKeyPress(.space) { chooseHighlighted() }
                        .task {
                            highlightedID = selection.flatMap { id in model.categories.contains { $0.id == id } ? id : nil } ?? model.categories.first?.id
                            listFocused = true
                        }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Button("新建类型…") { pending = .create; expanded = false }
                        Button("管理类型…") { pending = .manage; expanded = false }
                    }.buttonStyle(.plain).padding(12)
                }.frame(width: 240)
                    .onExitCommand { expanded = false }
            }
        }
        .onChange(of: expanded) { _, value in
            if !value, let pending { destination = pending; self.pending = nil }
        }
        .sheet(item: $destination) { target in
            switch target {
            case .create: CategoryEditor(model: model) { selection = $0.id }
            case .manage:
                VStack(spacing: 0) {
                    HStack { Text("待办类型").font(.headline); Spacer(); Button("完成") { destination = nil } }.padding(20)
                    Divider()
                    CategoryList(model: model, onReplaced: { old, replacement in if selection == old { selection = replacement } })
                }.frame(width: 420, height: 440).appTheme(model)
            }
        }
    }
    private func choose(_ id: UUID) {
        guard model.categories.contains(where: { $0.id == id }) else { return }
        selection = id; expanded = false
    }
    private func chooseHighlighted() -> KeyPress.Result {
        // A native List may move focus into its selected row. The handler is
        // already scoped to this list; its root FocusState need not stay true.
        guard let highlightedID, model.categories.contains(where: { $0.id == highlightedID }) else { return .ignored }
        choose(highlightedID)
        return .handled
    }

}

struct CategoryColorPresets: View {
    var select: (Color) -> Void
    private let colors = [("松绿", "#64967C"), ("雾蓝", "#6B91B0"), ("浅紫", "#9681B8"),
                          ("暖橙", "#CB9563"), ("玫瑰", "#C78290"), ("石灰", "#899596")]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(colors, id: \.0) { name, hex in
                Button { select(Color(hex: hex)) } label: { CategoryDot(hex: hex, size: 24).padding(2) }
                    .buttonStyle(.plain).help(name).accessibilityLabel("预设颜色：\(name)")
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("类型预设色板")
    }
}
