import AppKit
import Darwin

/// Opt-in measurements of the real process, never enabled in a normal launch.
/// Layout readiness is a native-window/main-run-loop checkpoint, not a claim
/// about compositor latency or LaunchServices' pre-process startup work.
@MainActor enum GUIProbe {
    private static var started: TimeInterval = 0
    private static var observing = false
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-performance") && args.contains(where: { $0.hasPrefix("--ui-test=") })
    }
    static func begin() { if enabled { started = ProcessInfo.processInfo.systemUptime } }

    private struct Report: Codable {
        var recordedAt = Date()
        var processID = ProcessInfo.processInfo.processIdentifier
        var operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        var processors = ProcessInfo.processInfo.processorCount
        #if arch(arm64)
        var architecture = "arm64"
        #else
        var architecture = "x86_64"
        #endif
        var timeZone = TimeZone.current.identifier
        var appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        #if DEBUG
        var configuration = "debug"
        #else
        var configuration = "release"
        #endif
        var mode: String
        var layoutReadyMS: Double?
        var nativeWindowReady = false
        var mainWindows: Int
        var cardVisible: Bool
        var rules: Int
        var countdowns: Int
        var cardItems: Int
        var welcomeVisible: Bool
        var idleSeconds: Double?
        var idleCPUPercent: Double?
        var inputEventsDuringSample: Int?
        var idleSampleValid = false
    }
    private static var mainCount: Int { NSApp.windows.filter { $0.identifier?.rawValue == "main" && $0.isVisible }.count }
    private static func cpuTime() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    static func observePresentation(_ model: AppModel) {
        guard enabled, !observing else { return }; observing = true
        Task { @MainActor in
            var report = Report(mode: model.backgroundLaunch ? "card" : "main-and-card", mainWindows: mainCount,
                cardVisible: model.cardVisible, rules: model.configuration.series.count, countdowns: model.events.count, cardItems: model.cardItems.count, welcomeVisible: model.showWelcome)
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            repeat {
                let main = NSApp.windows.first { $0.identifier?.rawValue == "main" && $0.isVisible }
                let ready: Bool
                if model.backgroundLaunch { ready = model.cardController?.prepareProbeFrame() == true }
                else if let main, !model.isLoading {
                    main.contentView?.layoutSubtreeIfNeeded(); main.displayIfNeeded(); ready = true
                } else { ready = false }
                if ready {
                    // Allow queued SwiftUI/native events one further main-loop turn.
                    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
                    report.nativeWindowReady = true; report.layoutReadyMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
                    break
                }
                try? await Task.sleep(for: .milliseconds(16))
            } while ProcessInfo.processInfo.systemUptime < deadline
            report.mainWindows = mainCount; report.cardVisible = model.cardVisible
            write(report, model: model)
            try? await Task.sleep(for: .seconds(3))
            let counter = InputCounter()
            counter.start()
            let windows = mainCount, card = model.cardVisible
            let cpu = cpuTime(), uptime = ProcessInfo.processInfo.systemUptime
            try? await Task.sleep(for: .seconds(5))
            report.idleSeconds = ProcessInfo.processInfo.systemUptime - uptime
            report.idleCPUPercent = max(0, (cpuTime() - cpu) / report.idleSeconds! * 100)
            report.inputEventsDuringSample = counter.events
            counter.stop()
            report.idleSampleValid = report.nativeWindowReady && counter.events == 0 && windows == mainCount && card == model.cardVisible && !model.isBusy && !model.hasPendingWrites && !model.showWelcome
            write(report, model: model)
            print("GUI probe finished: valid=\(report.idleSampleValid), mode=\(report.mode)")
        }
    }
    private static func write(_ report: Report, model: AppModel) {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: model.storageURL.deletingLastPathComponent().appendingPathComponent("gui-probe.json"), options: .atomic)
        } catch { print("GUI probe report could not be written.") }
    }
    @MainActor private final class InputCounter {
        var events = 0
        private var monitor: Any?
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
                self?.events += 1; return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
