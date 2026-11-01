import SwiftUI
import TodoDomain

/// Management stays inside the schedule section instead of adding navigation.
struct CategoryList: View {
    @Bindable var model: AppModel
    var onReplaced: ((UUID, UUID) -> Void)?
    @State private var selected: TodoCategory?
    @State private var showCreate = false
    @State private var deleting: TodoCategory?
    @State private var replacement: UUID?
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.categories) { category in
                        HStack {
                            CategoryDot(hex: category.colorHex, size: 10)
                            Text(category.name); Spacer()
                            Button { selected = category } label: { Image(systemName: "pencil").frame(width: 28, height: 28) }.buttonStyle(.plain).help("编辑类型").accessibilityLabel("编辑类型：\(category.name)")
                            if !category.isSystemDefault { Button { deleting = category; replacement = model.categories.first(where: { $0.isSystemDefault })?.id } label: { Image(systemName: "trash").frame(width: 28, height: 28) }.buttonStyle(.plain).help("删除并迁移类型").accessibilityLabel("删除并迁移类型：\(category.name)") }
                        }.padding(.vertical, 8).accessibilityElement(children: .contain)
                        Divider().opacity(0.4)
                    }
                }.padding(.horizontal, 20)
            }
            Button("添加类型") { showCreate = true }.padding(16)
        }
        .sheet(isPresented: $showCreate) { CategoryEditor(model: model) }
        .sheet(item: $selected) { category in CategoryEditor(model: model, original: category) }
        .sheet(item: $deleting) { category in
            VStack(alignment: .leading, spacing: 20) {
                Text("删除“\(category.name)”").font(.title2)
                Text("选择替代类型。已有待办、已完成事项及全部重复规则会一起迁移，操作不支持撤销。").foregroundStyle(.secondary)
                Picker("迁移到", selection: $replacement) { ForEach(model.categories.filter { $0.id != category.id }) { Text($0.name).tag(Optional($0.id)) } }
                HStack { Button("取消") { deleting = nil }; Spacer(); Button("迁移并删除", role: .destructive) {
                    Task {
                        guard let replacement else { return }
                        do { try await model.write { try await $0.replaceCategory(id: category.id, with: replacement, baseRevision: category.revision) }; await model.refresh(); onReplaced?(category.id, replacement); deleting = nil }
                        catch { model.error = error.localizedDescription }
                    }
                } }
            }.padding(28).frame(width: 380)
        }
    }
}

struct FixedRulesView: View {
    @Bindable var model: AppModel
    var onEdit: (() -> Void)?
    @State private var upcoming: [UUID: [OccurrencePreview]] = [:]
    @State private var previewError: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.configuration.series.isEmpty { Text("在待办编辑器中设置每日或每周重复。").foregroundStyle(.secondary).padding() }
                if let previewError { Text(previewError).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.configuration.series.sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString }) { root in
                    if let rule = model.configuration.rules.filter({ $0.seriesID == root.id && !$0.isSupersededForExpansion }).max(by: { $0.effectiveFromDay < $1.effectiveFromDay }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(rule.title).font(.headline)
                            Text(RecurrencePreview.summary(frequency: rule.frequency, weekdays: rule.weekdays, minute: rule.minute, category: model.category(rule.categoryID)?.name ?? "未知类型")).font(.caption).foregroundStyle(.secondary)
                            Text(root.stoppedFromDay.map { "自 \($0.description) 起停止" } ?? rule.endDay.map { "至 \($0.description)（含当天）" } ?? "持续重复").font(.caption).foregroundStyle(.secondary)
                            if let values = upcoming[root.id] {
                                if values.isEmpty { Text("没有未完成的后续发生").font(.caption).foregroundStyle(.secondary) }
                                else {
                                    Text("接下来").font(.caption.weight(.semibold))
                                    ForEach(values) { value in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(value.day.description) \(value.timeLabel) · \(value.title)\(value.isOverride ? "（单次例外）" : "")").font(.caption).monospacedDigit().lineLimit(2).help(value.title)
                                            LocalTimeNotice(day: value.day, minute: value.minute)
                                        }
                                    }
                                }
                            } else { Text("正在读取发生预览…").font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                if upcoming[root.id]?.isEmpty == false { Button("编辑下一次") { Task { await editNext(root) } } }
                                if root.stoppedFromDay == nil || root.stoppedFromDay! > model.today {
                                    Button("从今天停止", role: .destructive) { Task { await model.stopSeries(root.id, from: model.today) } }
                                }
                                Button("复制为新规则") { Task { if await model.copySeries(root.id) { onEdit?() } } }
                            }.font(.caption)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.padding(14)
        }.task(id: model.configuration.exportedAt) { await loadPreviews() }
    }
    private func loadPreviews() async {
        guard let repository = model.repository, !model.isBusy else { return }
        let version = model.configuration.exportedAt
        do {
            var values: [UUID: [OccurrencePreview]] = [:]
            for root in model.configuration.series {
                guard !Task.isCancelled, !model.isBusy else { return }
                values[root.id] = try await repository.upcomingSeries(id: root.id, from: model.today)
            }
            guard !Task.isCancelled, !model.isBusy, version == model.configuration.exportedAt else { return }
            upcoming = values; previewError = nil
        } catch { previewError = "暂时无法读取发生预览：\(error.localizedDescription)" }
    }
    private func editNext(_ root: TodoSeries) async {
        guard let repository = model.repository, !model.isBusy else { return }
        do {
            guard let next = try await repository.upcomingSeries(id: root.id, from: model.today, limit: 1).first else { throw DomainError.notFound }
            let items = try await model.write { try await $0.agenda(.days(from: next.day, count: 1)).items }
            guard let item = items.first(where: { $0.id == next.id }) else { throw DomainError.notFound }
            await model.edit(item); if model.mainEditor?.task.id == item.id { onEdit?() }
        } catch { model.error = error.localizedDescription }
    }
}
