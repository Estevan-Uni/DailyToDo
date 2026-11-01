import AppKit

/// Passive timing around real UI commands in the isolated performance process.
/// The checkpoint covers publication and native layout, not compositor/input lag.
@MainActor enum GUIInteractionProbe {
    struct Token {
        let started: TimeInterval
        let completed: Bool
        let originWindow: String
        let mainFrame: NSRect?
        let cardFrame: NSRect?
        let countdownAnchor: UUID?
    }
    private struct Sample: Codable {
        var recordedAt = Date()
        let processID: Int32
        let appBuild: String
        let operation: String
        let originWindow: String
        let modelPublishedMS: Double
        let layoutCheckpointMS: Double
        let mainVisible: Bool
        let cardVisible: Bool
        let stateVerified: Bool
        let mainFrameUnchanged: Bool
        let cardFrameUnchanged: Bool
        let countdownAnchorUnchanged: Bool
    }
    private static var samples: [Sample] = []
    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.identifier?.rawValue == "main" && $0.isVisible } }
    static func begin(completed: Bool, model: AppModel) -> Token? {
        guard GUIProbe.enabled else { return nil }
        return .init(started: ProcessInfo.processInfo.systemUptime, completed: completed,
                     originWindow: NSApp.keyWindow?.identifier?.rawValue ?? "unknown",
                     mainFrame: mainWindow?.frame, cardFrame: model.cardController?.probeFrame,
                     countdownAnchor: model.cardCountdownAnchor)
    }
    static func finish(_ token: Token, model: AppModel, stateVerified: Bool) async {
        let published = (ProcessInfo.processInfo.systemUptime - token.started) * 1000
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        if let mainWindow { mainWindow.contentView?.layoutSubtreeIfNeeded(); mainWindow.displayIfNeeded() }
        _ = model.cardController?.prepareProbeFrame()
        let checkpoint = (ProcessInfo.processInfo.systemUptime - token.started) * 1000
        samples.append(.init(processID: ProcessInfo.processInfo.processIdentifier,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            operation: token.completed ? "complete" : "reopen", originWindow: token.originWindow, modelPublishedMS: published, layoutCheckpointMS: checkpoint,
            mainVisible: mainWindow != nil, cardVisible: model.cardVisible, stateVerified: stateVerified,
            mainFrameUnchanged: token.mainFrame == mainWindow?.frame, cardFrameUnchanged: token.cardFrame == model.cardController?.probeFrame,
            countdownAnchorUnchanged: token.countdownAnchor == model.cardCountdownAnchor))
        samples = Array(samples.suffix(100))
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(samples).write(to: model.storageURL.deletingLastPathComponent().appendingPathComponent("gui-interactions.json"), options: .atomic)
        } catch { print("GUI interaction probe report could not be written.") }
    }
}
