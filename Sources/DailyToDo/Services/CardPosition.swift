import AppKit
import ColorSync
import TodoInteraction

/// Screen identifiers and window geometry stay in local preferences, outside
/// business JSON backups. No screen contents or wallpaper are accessed.
@MainActor enum CardPosition {
    private static let key = "cardPlacementV1"
    static func screen(_ native: NSScreen) -> PanelScreen {
        let number = native.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let identifier = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0.uint32Value)?.takeRetainedValue() }
            .map { CFUUIDCreateString(nil, $0) as String } ?? "display-\(number?.stringValue ?? "unknown")"
        return PanelScreen(id: identifier, visibleFrame: native.visibleFrame)
    }
    static var mainScreen: NSScreen? { NSScreen.screens.first }
    static func closest(to frame: NSRect) -> NSScreen? {
        let matches = NSScreen.screens.map { ($0, $0.visibleFrame.intersection(frame)) }
        guard let best = matches.max(by: { area($0.1) < area($1.1) }), area(best.1) > 0 else { return mainScreen }
        return best.0
    }
    static func restore() -> NSRect? {
        let screens = NSScreen.screens.map(screen), fallback = mainScreen.map { screen($0).id }
        if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(PanelPlacement.self, from: data),
           let frame = value.frame(on: screens, fallbackID: fallback) { return frame }
        // Migrate the previous absolute rectangle once, clamped to a present
        // display before encoding normalized coordinates.
        if let legacy = UserDefaults.standard.string(forKey: "cardFrame") {
            let old = NSRectFromString(legacy)
            if let native = closest(to: old), let value = PanelPlacement(frame: old, on: screen(native)),
               let frame = value.frame(on: screens, fallbackID: fallback) { save(frame); return frame }
        }
        return mainScreen.flatMap { PanelPlacement.initialFrame(on: screen($0)) }
    }
    static func save(_ frame: NSRect) {
        guard let native = closest(to: frame), let value = PanelPlacement(frame: frame, on: screen(native)),
              let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: "cardFrame")
    }
    static func reset() -> NSRect? {
        UserDefaults.standard.removeObject(forKey: key); UserDefaults.standard.removeObject(forKey: "cardFrame")
        return mainScreen.flatMap { PanelPlacement.initialFrame(on: screen($0)) }
    }
    private static func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : max(0, rect.width) * max(0, rect.height) }
}
