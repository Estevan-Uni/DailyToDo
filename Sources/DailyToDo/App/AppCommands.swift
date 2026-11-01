import AppKit
import SwiftUI

/// Text controls retain their own undo manager. Business undo is used only after
/// focus has left an editable text view; stale operations remain revision-guarded.
struct AppCommands: Commands {
    @Bindable var model: AppModel
    private var textView: NSTextView? { (NSApp.keyWindow?.firstResponder as? NSTextView).flatMap { $0.isEditable ? $0 : nil } }
    var body: some Commands {
        let _ = model.textEditingRevision
        CommandGroup(replacing: .newItem) {
            Button("新建待办") { Task { model.showMainAction?(); await model.create() } }.keyboardShortcut("n").disabled(model.repository == nil || model.isBusy)
            Button("新建倒计时") { Task { model.showMainAction?(); await model.create(kind: .countdown) } }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model.repository == nil || model.isBusy)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(textView == nil ? model.undoStack.last.map { "撤销\($0.title)" } ?? "撤销" : "撤销文字") {
                if let textView { textView.undoManager?.undo() }
                else { Task { await model.undo() } }
            }.keyboardShortcut("z").disabled(model.isBusy || (textView.map { $0.undoManager?.canUndo != true } ?? model.undoStack.isEmpty))
            Button("重做文字") { textView?.undoManager?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model.isBusy || textView?.undoManager?.canRedo != true)
            Button("撤销最近业务操作") { Task { await model.undo() } }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(model.undoStack.isEmpty || model.isBusy)
        }
        CommandGroup(after: .textEditing) {
            Button(model.section == .schedule ? "搜索当前日程" : "搜索倒计时") { model.showMainAction?(); model.searchRequest += 1 }.keyboardShortcut("f")
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { model.showSettingsAction?() }.keyboardShortcut(",")
        }
    }
}

@MainActor final class TextEditingMonitor {
    private var observers: [NSObjectProtocol] = []
    init(model: AppModel) {
        let names = [NSText.didBeginEditingNotification, NSText.didEndEditingNotification, NSText.didChangeNotification,
                     NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification, NSControl.textDidChangeNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                Task { @MainActor in model?.textEditingRevision += 1 }
            })
        }
    }
}
