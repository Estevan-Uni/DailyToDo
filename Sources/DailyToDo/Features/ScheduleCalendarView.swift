import SwiftUI
import TodoDomain
import TodoInteraction

/// The primary schedule is a calendar. The same bounded data feeds both layouts;
/// opening an editor adds a right sidebar without replacing the calendar.
struct ScheduleCalendarView: View {
    @Bindable var model: AppModel
    @State private var showJump = false
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var jumpText = ""
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    var body: some View {
        // Filter once and keep the repository's ordering within each date.
        // Individual cells must not scan the entire month on every update.
        let itemsByDay = Dictionary(grouping: model.visibleMainItems, by: \.scheduledDay)
        VStack(spacing: 0) {
            header
            if showSearch || !model.search.isEmpty { searchField.padding(.horizontal, 24).padding(.bottom, 14) }
            Divider().opacity(0.45)
            if model.isLoading { Spacer(); ProgressView("正在打开日程…"); Spacer() }
            else if model.scheduleScale == .month { monthCalendar(itemsByDay) }
            else { weekCalendar(itemsByDay) }
            MainStatusBar(model: model,
                fallback: "\(model.mainItems.count) 项安排 · \(model.mainItems.filter { $0.completedAt != nil }.count) 项已完成",
                hint: "空白处新建 · 事项点击编辑")
        }.background(.background)
        .onChange(of: model.searchRequest) { _, _ in showSearch = true; searchFocused = true }
        .task(id: showSearch) { if showSearch { searchFocused = true } }
        .popover(isPresented: $showJump) {
            VStack(spacing: 16) {
                Text("前往日期").font(.headline)
                CivilDateField(label: "日期", text: $jumpText)
                Button("前往") {
                    do {
                        let day = try LocalDate(jumpText); guard day.isUserSelectable else { throw DomainError.invalidDate }
                        model.selectedDay = day; showJump = false; Task { await model.refresh() }
                    } catch { model.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }.padding(24).frame(width: 330)
        }
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { periodNavigation; Spacer(minLength: 12); calendarTools }
            VStack(alignment: .leading, spacing: 14) { periodNavigation; HStack { calendarTools; Spacer() } }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
    }
    private var periodNavigation: some View {
        HStack(spacing: 14) {
            Text(model.scheduleScale == .month ? "\(model.selectedDay.year) 年 \(model.selectedDay.month) 月" : model.rangeLabel).font(.system(size: model.scheduleScale == .month ? 23 : 18, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Button { Task { await model.shiftSchedule(-1) } } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28) }.help(model.scheduleScale == .week ? "上一周" : "上个月")
                Button("今天") { model.selectedDay = model.today; Task { await model.refresh() } }.font(.callout)
                Button { Task { await model.shiftSchedule(1) } } label: { Image(systemName: "chevron.right").frame(width: 24, height: 28) }.help(model.scheduleScale == .week ? "下一周" : "下个月")
            }.buttonStyle(.plain)
            Button { jumpText = model.selectedDay.description; showJump = true } label: { Image(systemName: "calendar") }.buttonStyle(.plain).help("跳转年月日")
        }
    }
    private var scalePicker: some View {
        Picker("日历展示", selection: $model.scheduleScale) { ForEach(ScheduleScale.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 130)
            .onChange(of: model.scheduleScale) { _, _ in Task { await model.refresh() } }
    }
    private var calendarTools: some View {
        HStack(spacing: 16) {
            scalePicker
            Menu {
                Picker("类型", selection: $model.categoryFilter) {
                    Text("全部类型").tag(Optional<UUID>.none)
                    ForEach(model.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("完成状态", selection: $model.completionFilter) { ForEach(CompletionFilter.allCases) { Text($0.rawValue).tag($0) } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(model.categoryFilter != nil || model.completionFilter != .all ? Color.accentColor : .secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("筛选类型与完成状态")
            Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.plain).foregroundStyle(.secondary).help("搜索当前周或月")
        }
    }
    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.scheduleScale == .week ? "搜索本周" : "搜索本月", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
            if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
        }.font(.callout).padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
    private var monthCells: [LocalDate?] {
        guard let interval = try? DayInterval.month(containing: model.selectedDay) else { return [] }
        let days = interval.dates, leading = interval.start.weekday - 1
        let count = ((leading + days.count + 6) / 7) * 7
        return (0..<count).map { index in let offset = index - leading; return days.indices.contains(offset) ? days[offset] : nil }
    }
    private func monthCalendar(_ itemsByDay: [LocalDate: [TodoItem]]) -> some View {
        GeometryReader { geometry in
            let cells = monthCells, rows = max(1, cells.count / 7)
            let cellWidth = geometry.size.width / 7
            VStack(spacing: 0) {
                HStack(spacing: 0) { ForEach(0..<7) { index in Text(weekdays[index]).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: cellWidth, height: 32) } }
                Divider()
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            Group {
                                if let day = cells[row * 7 + column] {
                                    CalendarDayCell(model: model, day: day, items: itemsByDay[day] ?? [])
                                } else { Color.primary.opacity(0.012) }
                            }.frame(width: cellWidth).frame(maxHeight: .infinity).clipped()
                                .overlay(alignment: .trailing) { if column < 6 { Rectangle().fill(.primary.opacity(0.06)).frame(width: 0.5) } }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if row < rows - 1 { Divider().opacity(0.45) }
                }
            }
        }.padding(.horizontal, 16).padding(.bottom, 4)
    }
    private func weekCalendar(_ itemsByDay: [LocalDate: [TodoItem]]) -> some View {
        let days = (try? DayInterval.week(containing: model.selectedDay))?.dates ?? []
        return GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    WeekDayColumn(model: model, day: day, weekday: weekdays[day.weekday - 1], items: itemsByDay[day] ?? [])
                        .frame(width: geometry.size.width / CGFloat(max(1, days.count))).clipped()
                        .overlay(alignment: .trailing) { if day != days.last { Rectangle().fill(.primary.opacity(0.06)).frame(width: 0.5) } }
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 4)
    }
}

private struct WeekDayColumn: View {
    @Bindable var model: AppModel
    let day: LocalDate
    let weekday: String
    let items: [TodoItem]
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Text(weekday).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(day.month)/\(day.day)").font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundStyle(day == model.today ? Color.accentColor : .primary)
            }.frame(maxWidth: .infinity).padding(.vertical, 18).allowsHitTesting(false)
            Divider().opacity(0.45)
            GeometryReader { geometry in
                ScrollView {
                    ZStack(alignment: .top) {
                        Button { Task { await model.create(on: day) } } label: { Color.clear.frame(maxWidth: .infinity).frame(minHeight: geometry.size.height).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel("\(day.description) 空白处，新增待办").accessibilityIdentifier("calendar-day-\(day)-add")
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in CalendarTask(model: model, item: item, multiline: true) }
                        }.padding(7)
                    }.frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
        }.frame(maxHeight: .infinity).background(day == model.today ? Color.accentColor.opacity(0.02) : .clear)
    }
}

private struct CalendarDayCell: View {
    @Bindable var model: AppModel
    let day: LocalDate
    let items: [TodoItem]
    @State private var showAll = false
    @State private var hovering = false
    var body: some View {
        GeometryReader { geometry in
        let layout = MonthCellLayout(height: geometry.size.height, itemCount: items.count)
        ZStack(alignment: .topLeading) {
            Button { Task { await model.create(on: day) } } label: {
                Rectangle().fill(hovering ? Color.accentColor.opacity(0.035) : day == model.today ? Color.accentColor.opacity(0.02) : .clear).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(day.description) 空白处，新增待办").accessibilityIdentifier("calendar-day-\(day)-add")
            VStack(alignment: .leading, spacing: MonthCellLayout.spacing) {
                Text("\(day.day)").font(.system(size: 12, weight: day == model.today ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(day == model.today ? Color.accentColor : .primary)
                    .frame(width: 25, height: 25).background(day == model.today ? Color.accentColor.opacity(0.12) : .clear, in: Circle()).allowsHitTesting(false)
                ForEach(Array(items.prefix(layout.visibleCount))) { item in CalendarTask(model: model, item: item).frame(height: MonthCellLayout.eventHeight) }
                if layout.hiddenCount > 0 {
                    Button("还有 \(layout.hiddenCount) 项") { showAll = true }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary).frame(height: MonthCellLayout.overflowHeight)
                        .popover(isPresented: $showAll) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(day.description).font(.headline)
                                ScrollView { LazyVStack(spacing: 14) { ForEach(items) { item in TaskRow(model: model, item: item, onSelect: { showDate in showAll = false; Task { await model.edit(item, showDatePicker: showDate) } }) } } }.frame(maxHeight: 360)
                                Button("添加待办") { showAll = false; Task { await model.create(on: day) } }
                            }.padding(22).frame(width: 330)
                        }
                }
                Spacer(minLength: 0)
            }.padding(MonthCellLayout.inset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.onHover { hovering = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel("\(day.description)，\(items.count) 项安排")
        }
    }
}

private struct CalendarTask: View {
    @Bindable var model: AppModel
    let item: TodoItem
    var multiline = false
    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Button { if TaskCompletionInput.acceptsCurrentEvent { Task { await model.toggle(item) } } } label: { Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(item.completedAt == nil ? Color.secondary : Color.accentColor).frame(width: 15, height: 19) }.buttonStyle(.plain).accessibilityLabel("\(item.completedAt == nil ? "完成" : "取消完成")：\(item.title)")
            Button { Task { await model.edit(item) } } label: {
                HStack(alignment: .top, spacing: 4) {
                    categoryDot.padding(.top, multiline ? 5 : 4)
                    title.lineLimit(multiline ? 4 : 1)
                }
            }.buttonStyle(.plain).accessibilityLabel("\(item.title)，\(model.category(item.categoryID)?.name ?? "")，\(item.completedAt == nil ? "未完成" : "已完成")\(item.isImportant ? "，重要" : "")\(completionDescription)，编辑").accessibilityIdentifier("calendar-event-\(item.id)")
            if item.isImportant { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.orange).padding(.top, 4).accessibilityHidden(true) }
        }
            .padding(multiline ? 7 : 3).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(item.completedAt == nil ? 0.035 : 0.015), in: RoundedRectangle(cornerRadius: multiline ? 8 : 4))
            .contextMenu { TaskContextMenu(model: model, item: item, onEdit: { showDate in Task { await model.edit(item, showDatePicker: showDate) } }) }
            .help("\(item.title)\(completionDescription)")
    }
    private var categoryDot: some View { CategoryDot(hex: model.category(item.categoryID)?.colorHex ?? "#83908B", size: 5) }
    private var completionDescription: String { item.completedAt.map { "，完成于 \(model.clock.formatted($0))" } ?? "" }
    private var title: some View { Text(item.title).font(.system(size: multiline ? 12 : 11, weight: .medium)).strikethrough(item.completedAt != nil).foregroundStyle(item.completedAt == nil ? .primary : .secondary).frame(maxWidth: .infinity, alignment: .leading) }
}
