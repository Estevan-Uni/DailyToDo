import Foundation

/// The existing integer store uses -1 for an unspecified time. Keeping the
/// field and model unchanged preserves existing SQLite stores and timed items.
public enum ScheduledTime {
    public static let unspecified = -1
    public static func isValid(_ minute: Int) -> Bool { minute == unspecified || hasTime(minute) }
    public static func hasTime(_ minute: Int) -> Bool { (0..<1440).contains(minute) }
    public static func label(_ minute: Int, ifUnspecified fallback: String = "") -> String {
        hasTime(minute) ? String(format: "%02d:%02d", minute / 60, minute % 60) : fallback
    }
}
