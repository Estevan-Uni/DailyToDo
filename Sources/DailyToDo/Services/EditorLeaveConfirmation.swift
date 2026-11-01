import AppKit

enum EditorLeaveChoice { case save, continueEditing, discard }

@MainActor enum EditorLeaveConfirmation {
    static func ask(_ editor: EditorSession) -> EditorLeaveChoice {
        let alert = NSAlert(); alert.messageText = "保存对“\(editor.title)”的修改？"
        alert.informativeText = "离开后，未保存的输入将被丢弃。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "不保存")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .continueEditing
        }
    }
}
