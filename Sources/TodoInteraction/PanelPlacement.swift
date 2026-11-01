import Foundation
import CoreGraphics

public struct PanelScreen: Sendable {
    public let id: String
    public let visibleFrame: CGRect
    public init(id: String, visibleFrame: CGRect) { self.id = id; self.visibleFrame = visibleFrame }
}

/// Local-only preference. Fractions describe the panel's travel range inside
/// a display's usable frame, so top/right anchoring survives Dock/scale changes.
public struct PanelPlacement: Codable, Equatable, Sendable {
    public let version: Int
    public let screenID: String
    public let width: Double
    public let height: Double
    public let xFraction: Double
    public let yFraction: Double
    public static let minimumSize = CGSize(width: 600, height: 340)

    public init?(frame: CGRect, on screen: PanelScreen) {
        let area = screen.visibleFrame
        guard Self.valid(frame), Self.valid(area) else { return nil }
        version = 1; screenID = screen.id; width = frame.width; height = frame.height
        xFraction = Self.fraction(frame.minX - area.minX, range: area.width - frame.width)
        yFraction = Self.fraction(frame.minY - area.minY, range: area.height - frame.height)
    }
    public func frame(on screens: [PanelScreen], fallbackID: String?) -> CGRect? {
        guard version == 1, [width, height, xFraction, yFraction].allSatisfy(\.isFinite), width > 0, height > 0,
              let screen = screens.first(where: { $0.id == screenID }) ?? screens.first(where: { $0.id == fallbackID }) ?? screens.first,
              Self.valid(screen.visibleFrame) else { return nil }
        let area = screen.visibleFrame
        let size = CGSize(width: min(max(width, Self.minimumSize.width), 1100, area.width), height: min(max(height, Self.minimumSize.height), 850, area.height))
        return CGRect(x: area.minX + max(0, area.width - size.width) * min(1, max(0, xFraction)),
                      y: area.minY + max(0, area.height - size.height) * min(1, max(0, yFraction)), width: size.width, height: size.height)
    }
    public static func initialFrame(on screen: PanelScreen) -> CGRect? {
        let area = screen.visibleFrame
        guard valid(area) else { return nil }
        let width = min(680, area.width), height = min(400, area.height)
        return CGRect(x: max(area.minX, area.maxX - width - 20), y: max(area.minY, area.maxY - height - 20), width: width, height: height)
    }
    public static func canDisplay(on screen: PanelScreen) -> Bool {
        valid(screen.visibleFrame) && screen.visibleFrame.width >= minimumSize.width && screen.visibleFrame.height >= minimumSize.height
    }
    private static func fraction(_ value: Double, range: Double) -> Double { range > 0 ? min(1, max(0, value / range)) : 0 }
    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
}
