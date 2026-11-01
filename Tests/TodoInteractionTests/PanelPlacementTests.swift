import Foundation
import CoreGraphics
import Testing
@testable import TodoInteraction

@Suite struct PanelPlacementTests {
    private let main = PanelScreen(id: "main", visibleFrame: CGRect(x: 0, y: 30, width: 1440, height: 850))
    @Test func initialPositionIsTopRightAndInsideUsableArea() throws {
        let frame = try #require(PanelPlacement.initialFrame(on: main))
        #expect(frame.size == CGSize(width: 680, height: 400))
        #expect(main.visibleFrame.maxX - frame.maxX == 20)
        #expect(main.visibleFrame.maxY - frame.maxY == 20)
        #expect(main.visibleFrame.contains(frame))
    }
    @Test func savedDisplayAndRelativeEdgesSurviveResolutionAndDockChange() throws {
        let external = PanelScreen(id: "external", visibleFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1040))
        let original = CGRect(x: external.visibleFrame.maxX - 680, y: external.visibleFrame.maxY - 400, width: 680, height: 400)
        let saved = try #require(PanelPlacement(frame: original, on: external))
        let changed = PanelScreen(id: "external", visibleFrame: CGRect(x: 1440, y: -100, width: 1280, height: 720))
        let restored = try #require(saved.frame(on: [main, changed], fallbackID: "main"))
        #expect(restored.maxX == changed.visibleFrame.maxX)
        #expect(restored.maxY == changed.visibleFrame.maxY)
        #expect(changed.visibleFrame.contains(restored))
    }
    @Test func disconnectedScreenFallsBackAndClampsSize() throws {
        let external = PanelScreen(id: "gone", visibleFrame: CGRect(x: -2000, y: 0, width: 2000, height: 1200))
        let saved = try #require(PanelPlacement(frame: CGRect(x: -2000, y: 0, width: 1600, height: 1000), on: external))
        let small = PanelScreen(id: "small", visibleFrame: CGRect(x: 20, y: 40, width: 800, height: 600))
        let restored = try #require(saved.frame(on: [main, small], fallbackID: "small"))
        #expect(small.visibleFrame.contains(restored))
        #expect(restored.size == CGSize(width: 800, height: 600))
    }
    @Test func corruptAndOffscreenPreferencesCannotEscapeScreen() throws {
        #expect(PanelPlacement(frame: .zero, on: main) == nil)
        #expect(PanelPlacement(frame: .null, on: main) == nil)
        let saved = try #require(PanelPlacement(frame: CGRect(x: 10000, y: -10000, width: 680, height: 400), on: main))
        #expect(main.visibleFrame.contains(try #require(saved.frame(on: [main], fallbackID: nil))))
        #expect(saved.frame(on: [], fallbackID: nil) == nil)
    }
    @Test func preferenceRoundTripAndUndersizedDisplayAreExplicit() throws {
        let original = try #require(PanelPlacement(frame: CGRect(x: 300, y: 200, width: 720, height: 480), on: main))
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PanelPlacement.self, from: encoded)
        #expect(restored == original)
        #expect(PanelPlacement.canDisplay(on: main))
        let tiny = PanelScreen(id: "tiny", visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 300))
        #expect(!PanelPlacement.canDisplay(on: tiny))
        #expect(tiny.visibleFrame.contains(try #require(restored.frame(on: [tiny], fallbackID: nil))))
    }
}
