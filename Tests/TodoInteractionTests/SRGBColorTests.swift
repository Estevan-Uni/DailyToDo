import Testing
@testable import TodoInteraction

@Suite struct SRGBColorTests {
    @Test func knownContrastAndEncoding() {
        #expect(SRGBColor.white.contrast(with: .black) == 21)
        #expect(SRGBColor(hex: "#aB02fF")?.hex == "#AB02FF")
        #expect(SRGBColor(red: 1.2, green: -0.1, blue: 0.5).hex == "#FF0080")
        for invalid in ["", "FFFFFF", "#fff", "#FFFFFF00", "##00000", "#G00000", "#１２３"] { #expect(SRGBColor(hex: invalid) == nil) }
    }
    @Test func extremesAndPresetsStayReadableInBothAppearances() throws {
        for hex in ["#FFFFFF", "#000000", "#FFFF00", "#0000FF", "#FF00FF", "#4B8E83", "#5D7DA6", "#8974A2", "#B57E85", "#B38B57", "#747C85"] {
            let raw = try #require(SRGBColor(hex: hex))
            for surface in [SRGBColor.white, .darkSurface, .materialLightSurface, .materialDarkSurface] {
                let tone = raw.readable(on: surface)
                #expect(tone.contrast(with: surface) >= 4.5)
                #expect(tone.foreground.contrast(with: tone) >= 4.5)
            }
            #expect(raw.hex == hex)
        }
    }
    @Test func alreadyReadableColorsArePreserved() {
        #expect(SRGBColor.black.readable(on: .white) == .black)
        #expect(SRGBColor.white.readable(on: .darkSurface) == .white)
    }
}
