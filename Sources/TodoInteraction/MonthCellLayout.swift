/// Fixed metrics shared by the month cell and its overflow calculation (points).
/// Reserve the overflow link separately so a six-row month can still show an
/// event instead of spending its only event slot on the link.
public struct MonthCellLayout: Sendable {
    public static let inset = 6.0
    public static let dateHeight = 25.0
    public static let eventHeight = 25.0
    public static let spacing = 3.0
    public static let overflowHeight = 16.0
    public let visibleCount: Int
    public let hiddenCount: Int

    public init(height: Double, itemCount: Int) {
        let count = max(0, itemCount)
        let available = max(0, height - Self.inset * 2 - Self.dateHeight)
        let step = Self.eventHeight + Self.spacing
        let allSlots = Int(available / step)
        if count <= allSlots { visibleCount = count }
        else {
            visibleCount = min(count, max(0, Int((available - Self.overflowHeight - Self.spacing) / step)))
        }
        hiddenCount = count - visibleCount
    }
}
