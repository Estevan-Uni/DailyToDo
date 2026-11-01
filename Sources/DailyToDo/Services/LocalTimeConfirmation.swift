import AppKit
import TodoDomain

@MainActor enum LocalTimeConfirmation {
    static func confirm(_ value: LocalTimeResolution) -> Bool {
        let alert = NSAlert()
        alert.messageText = "确认本地时间解析"
        alert.informativeText = "\(value.day) · \(value.timeZoneIdentifier)\n\(LocalTimePresentation.detail(value))\n保存的计划时分仍为 \(value.requestedTimeLabel)。此操作本身不创建提醒。"
        alert.addButton(withTitle: "按此时刻保存"); alert.addButton(withTitle: "继续编辑")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
