import AppKit
import TodoPersistence

@MainActor enum SeriesConfirmation {
    static func confirm(_ review: SeriesReview) -> Bool {
        let alert = NSAlert()
        let exceptionAction: String
        switch review.change {
        case .update:
            alert.messageText = "修改本次及以后的固定待办？"
            alert.informativeText = "从原发生日 \(review.from) 应用新规则。将更新 \(review.affectedCount) 条已保存未完成实例，保留 \(review.exceptions.count) 条其他单次例外。"
            exceptionAction = "保留的单次例外"
        case .detach:
            alert.messageText = "改为不重复并停止后续规则？"
            alert.informativeText = "当前事项保留为单次待办，从原发生日 \(review.from) 停止旧规则。将隐藏其他 \(review.affectedCount) 条已保存未完成实例。"
            exceptionAction = "将隐藏的单次例外"
        case .stop:
            alert.messageText = "停止本次及以后的固定待办？"
            alert.informativeText = "从原发生日 \(review.from) 停止。将隐藏 \(review.affectedCount) 条已保存未完成实例，其中包含 \(review.exceptions.count) 条单次例外。"
            exceptionAction = "将隐藏的单次例外"
        }
        alert.informativeText += "\n\(review.completedCount) 条已完成记录保留。未生成的未来次数不计数；规则从上述日期更新或停止。"
        alert.informativeText += review.change == .stop ? "\n可撤销本次停止。" : "\n此批量修改不支持通用撤销。"
        if !review.exceptions.isEmpty {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .bezelBorder
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
            text.isEditable = false; text.isSelectable = true; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width: 8, height: 8); text.font = .systemFont(ofSize: 12); text.textColor = .labelColor
            text.string = exceptionAction + "（\(review.exceptions.count)）\n\n" + review.exceptions.map {
                "\($0.title)\n原发生日 \($0.originalDay) → 安排 \($0.day) \($0.timeLabel)"
            }.joined(separator: "\n\n")
            text.setAccessibilityLabel(exceptionAction)
            scroll.documentView = text; alert.accessoryView = scroll
        }
        alert.addButton(withTitle: review.change == .stop ? "停止后续" : "应用修改"); alert.addButton(withTitle: review.change == .stop ? "取消" : "继续编辑")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
