import AppKit
import UniformTypeIdentifiers

/// File-panel callbacks release the main actor while AppKit validates selection
/// and obtains the sandbox extension. Do not nest runModal in an async command.
@MainActor enum FileDialogs {
    private static var activePanel: NSSavePanel?
    static func openJSON() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return await present(panel)
    }
    static func saveJSON(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return await present(panel)
    }
    private static func present(_ panel: NSSavePanel) async -> URL? {
        if let activePanel { activePanel.makeKeyAndOrderFront(nil); return nil }
        activePanel = panel; defer { activePanel = nil }
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            let finished: (NSApplication.ModalResponse) -> Void = { response in
                panel.orderOut(nil)
                continuation.resume(returning: response)
            }
            if let parent = NSApp.keyWindow ?? NSApp.mainWindow, parent.isVisible {
                panel.beginSheetModal(for: parent, completionHandler: finished)
            } else { panel.begin(completionHandler: finished) }
        }
        return response == .OK ? panel.url : nil
    }
}
