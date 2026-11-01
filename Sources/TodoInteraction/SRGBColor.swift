import Foundation

/// Stored colors remain unchanged. Rendering may use a nearby contrasting tone.
public struct SRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red)); self.green = min(1, max(0, green)); self.blue = min(1, max(0, blue))
    }
    public init?(hex: String) {
        guard hex.utf8.count == 7, hex.first == "#", hex.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(value >> 16) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    public static let white = SRGBColor(red: 1, green: 1, blue: 1)
    public static let black = SRGBColor(red: 0, green: 0, blue: 0)
    public static let darkSurface = SRGBColor(hex: "#3A3A3A")!
    public static let materialLightSurface = SRGBColor(hex: "#D8D8D8")!
    public static let materialDarkSurface = SRGBColor(hex: "#555555")!
    public var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: Self) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    public var foreground: Self { contrast(with: .black) >= contrast(with: .white) ? .black : .white }
    public func readable(on surface: Self) -> Self {
        guard contrast(with: surface) < 4.5 else { return self }
        let target = surface.foreground
        var lower = 0.0, upper = 1.0
        func blend(_ amount: Double) -> Self {
            Self(red: red + (target.red - red) * amount, green: green + (target.green - green) * amount, blue: blue + (target.blue - blue) * amount)
        }
        for _ in 0..<28 {
            let middle = (lower + upper) / 2
            if blend(middle).contrast(with: surface) >= 4.5 { upper = middle } else { lower = middle }
        }
        return blend(upper)
    }
}
