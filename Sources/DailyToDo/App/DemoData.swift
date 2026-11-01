import Foundation
import TodoDomain

/// Synthetic fixtures are opt-in and used only with a separate UI-test database.
enum DemoData {
    static func snapshot(today: LocalDate, stress: Bool = false) throws -> StoreSnapshot {
        var snapshot = StoreSnapshot()
        let titles = ["阅读与整理", "项目回顾", "散步半小时", "准备周会", "整理收件箱", "更新本周计划"]
        for (index, title) in titles.enumerated() {
            var task = TodoItem(title: title, scheduledDay: today, scheduledMinute: 9 * 60 + index * 90, categoryID: snapshot.categories[(index % 3) + 1].id)
            if index < 2 { task.completedAt = Date().addingTimeInterval(-3600) }
            snapshot.tasks.append(task)
        }
        for offset in [1, 2, 4, 6, 10] {
            let day = try today.adding(days: offset)
            snapshot.tasks.append(TodoItem(title: ["讨论设计方案", "预约牙齿检查", "提交阶段总结", "与朋友见面", "整理照片"][offset == 10 ? 4 : offset == 6 ? 3 : offset == 4 ? 2 : offset == 2 ? 1 : 0], scheduledDay: day, scheduledMinute: 840, categoryID: snapshot.categories[(offset % 3) + 1].id))
        }
        let root = TodoSeries()
        let rule = TodoSeriesRule(seriesID: root.id, from: today, title: "英语阅读", minute: 480, categoryID: snapshot.categories[2].id, frequency: .weekly, weekdays: [1, 3, 5])
        snapshot.series = [root]; snapshot.rules = [rule]
        for (title, offset) in [("周末短途旅行", 7), ("项目里程碑", 21), ("值得期待的日子", 1000)] {
            snapshot.countdowns.append(CountdownEvent(title: title, targetDay: try today.adding(days: offset)))
        }
        if stress {
            for index in 6..<100 {
                let title = index == 99 ? "当天最后一项 · 长标题中文 English 与 emoji 🌿 日程可完整编辑" : "日程 \(index + 1) · 准备与整理"
                snapshot.tasks.append(TodoItem(title: title, scheduledDay: today, scheduledMinute: 1140 + index, categoryID: snapshot.categories[(index % 3) + 1].id))
            }
            for index in 3..<200 {
                let title = index == 199 ? "最后一个期待的日子 · 长标题与 emoji ✨" : "期待 \(index + 1)"
                snapshot.countdowns.append(CountdownEvent(title: title, targetDay: try today.adding(days: index == 199 ? 9999 : index * 10)))
            }
        }
        return snapshot
    }
}
