/// Platform-neutral gesture state; AppKit is responsible only for translating
/// NSEvent and limiting input to the exact card window.
public enum ScrollPhase: Sendable { case none, began, changed, ended, cancelled, momentumBegan, momentumChanged, momentumEnded }

public struct ScrollSample: Sendable {
    public var dx: Double
    public var dy: Double
    public var timestamp: Double
    public var phase: ScrollPhase
    public var isPrecise: Bool
    public var insideRegion: Bool
    public init(dx: Double, dy: Double, timestamp: Double, phase: ScrollPhase, isPrecise: Bool = true, insideRegion: Bool = true) {
        self.dx = dx; self.dy = dy; self.timestamp = timestamp; self.phase = phase
        self.isPrecise = isPrecise; self.insideRegion = insideRegion
    }
}

public struct ScrollDecision: Equatable, Sendable {
    public var consumed: Bool
    public var page: Int?
    public static let pass = Self(consumed: false)
}

public struct ScrollPaging: Sendable {
    private enum Axis { case undecided, horizontal, vertical }
    private var active = false
    private var ownsSequence = false
    private var axis = Axis.undecided
    private var x = 0.0, y = 0.0, lastTimestamp = 0.0
    private var fired = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func handle(_ sample: ScrollSample, width: Double) -> ScrollDecision {
        guard sample.isPrecise else { reset(); return .pass }
        if sample.phase == .cancelled { reset(); return .pass }
        let momentum = [.momentumBegan, .momentumChanged, .momentumEnded].contains(sample.phase)
        // Re-enabling a hidden/editor-covered region must not pick up old inertia.
        if !active && momentum { return .pass }
        if sample.phase == .began || (!active && !momentum) || (sample.phase == .none && sample.timestamp - lastTimestamp > 0.15) {
            reset(); active = true; ownsSequence = sample.insideRegion
        }
        lastTimestamp = sample.timestamp
        if sample.phase == .momentumEnded { defer { reset() }; return ScrollDecision(consumed: ownsSequence && axis == .horizontal) }
        guard ownsSequence else { return .pass }
        x += sample.dx; y += sample.dy
        if axis == .undecided && max(abs(x), abs(y)) >= 10 {
            if abs(x) > abs(y) * 1.4 { axis = .horizontal }
            else if abs(y) > abs(x) * 1.4 { axis = .vertical }
        }
        guard axis == .horizontal else { return .pass }
        var page: Int?
        if !fired && abs(x) >= max(45, width * 0.2) { fired = true; page = x < 0 ? 1 : -1 }
        return ScrollDecision(consumed: true, page: page)
    }
}
