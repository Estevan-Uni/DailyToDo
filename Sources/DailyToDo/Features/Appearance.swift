import SwiftUI
import TodoInteraction

extension Color {
    init(hex: String) { self.init(rgb: SRGBColor(hex: hex) ?? SRGBColor(hex: "#83908B")!) }
    private init(rgb: SRGBColor) { self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1) }
    static func readableAccent(hex: String, scheme: ColorScheme, foreground: Bool = false, onMaterial: Bool = false) -> Color {
        let raw = SRGBColor(hex: hex) ?? SRGBColor(hex: "#4B8E83")!
        let surface: SRGBColor = onMaterial ? (scheme == .dark ? .materialDarkSurface : .materialLightSurface) : (scheme == .dark ? .darkSurface : .white)
        let tone = raw.readable(on: surface)
        return Color(rgb: foreground ? tone.foreground : tone)
    }
    var rgbHex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return SRGBColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent).hex
    }
}

/// Native color well plus an editable, keyboard-accessible sRGB value. Partial
/// or invalid input never changes the selected color or stored preference.
struct ColorInput: View {
    let title: String
    @Binding var selection: Color
    var onValidityChange: ((Bool) -> Void)?
    @State private var hex = ""
    private var valid: Bool { SRGBColor(hex: hex) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                ColorPicker(title, selection: $selection, supportsOpacity: false)
                TextField("#RRGGBB", text: $hex).font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder).frame(width: 88).accessibilityLabel("\(title)，十六进制颜色值")
            }
            if !hex.isEmpty && !valid { Text("请输入 # 和六位颜色值").font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { hex = selection.rgbHex; onValidityChange?(true) }
        .onChange(of: valid) { _, value in onValidityChange?(value) }
        .onChange(of: selection) { _, color in if color.rgbHex != hex.uppercased() { hex = color.rgbHex } }
        .onChange(of: hex) { _, text in if let rgb = SRGBColor(hex: text), rgb.hex != selection.rgbHex { selection = Color(hex: rgb.hex) } }
    }
}

struct CategoryDot: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let hex: String
    var size: CGFloat = 6
    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size)
            .overlay { Circle().strokeBorder(.primary.opacity(contrast == .increased ? 0.7 : 0.25), lineWidth: contrast == .increased ? 1 : 0.5) }
            .accessibilityHidden(true)
    }
}

/// Resolve against SwiftUI's actual window appearance. Value colors give the
/// environment a stable equality comparison during native control relayout.
private struct AppTheme: ViewModifier {
    @Bindable var model: AppModel
    var onMaterial: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let color = Color.readableAccent(hex: model.themeColorHex, scheme: scheme, onMaterial: onMaterial)
        content.tint(color).accentColor(color)
            .environment(\.appClock, model.clock)
            .environment(\.timeZone, model.displayTimeZone)
            .environment(\.calendar, model.clock.calendar)
    }
}
extension View {
    func appTheme(_ model: AppModel, onMaterial: Bool = false) -> some View { modifier(AppTheme(model: model, onMaterial: onMaterial)) }
}
