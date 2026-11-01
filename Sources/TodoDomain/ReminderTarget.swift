import Foundation

/// The notification identifier is a stable record identity, never a title,
/// URL, or stored date. A task may have rolled forward since it was delivered.
public enum ReminderTarget: Equatable, Sendable {
    case task(UUID)
    case countdown(UUID)

    public init?(requestID: String) {
        let prefix: String
        if requestID.hasPrefix("task-") { prefix = "task-" }
        else if requestID.hasPrefix("countdown-") { prefix = "countdown-" }
        else { return nil }
        let rawID = String(requestID.dropFirst(prefix.count))
        guard rawID.count == 36, let id = UUID(uuidString: rawID) else { return nil }
        self = prefix == "task-" ? .task(id) : .countdown(id)
    }
    public var requestID: String {
        switch self {
        case .task(let id): "task-\(id)"
        case .countdown(let id): "countdown-\(id)"
        }
    }
}
