import Testing
import TodoInteraction

@Suite struct ScrollPagingTests {
    private func s(_ x: Double, _ y: Double = 0, _ time: Double = 1, _ phase: ScrollPhase = .changed, inside: Bool = true, precise: Bool = true) -> ScrollSample {
        .init(dx: x, dy: y, timestamp: time, phase: phase, isPrecise: precise, insideRegion: inside)
    }
    @Test func onePageAcrossGestureAndMomentum() {
        var router = ScrollPaging()
        #expect(router.handle(s(-30, 0, 1, .began), width: 300).page == nil)
        #expect(router.handle(s(-40, 0, 1.02), width: 300).page == 1)
        #expect(router.handle(s(-100, 0, 1.04, .ended), width: 300).page == nil)
        #expect(router.handle(s(-100, 0, 1.05, .momentumBegan), width: 300).page == nil)
        #expect(router.handle(s(-200, 0, 1.1, .momentumChanged), width: 300).page == nil)
        #expect(router.handle(s(0, 0, 1.2, .momentumEnded), width: 300).consumed)
        #expect(router.handle(s(80, 0, 2, .began), width: 300).page == -1)
    }
    @Test func gestureBeginningOutsideNeverPagesAfterCrossingDivider() {
        var router = ScrollPaging()
        #expect(router.handle(s(-40, 0, 1, .began, inside: false), width: 300) == .pass)
        #expect(router.handle(s(-100, 0, 1.02, inside: true), width: 300) == .pass)
    }
    @Test func gestureBeginningInsideRetainsOwnershipAcrossDivider() {
        var router = ScrollPaging()
        _ = router.handle(s(-20, 0, 1, .began), width: 300)
        #expect(router.handle(s(-50, 0, 1.02, inside: false), width: 300).page == 1)
    }
    @Test func verticalLockDoesNotChangeWhenListHitsBoundary() {
        var router = ScrollPaging()
        #expect(router.handle(s(3, -20, 1, .began), width: 300) == .pass)
        #expect(router.handle(s(-200, 0, 1.02), width: 300) == .pass)
    }
    @Test func ambiguousDiagonalDoesNotPage() {
        var router = ScrollPaging()
        _ = router.handle(s(-8, -8, 1, .began), width: 300)
        #expect(router.handle(s(-70, -65, 1.02), width: 300) == .pass)
    }
    @Test func precisePhaseLessInputGroupsByPause() {
        var router = ScrollPaging()
        #expect(router.handle(s(-70, 0, 1, .none), width: 300).page == 1)
        #expect(router.handle(s(-100, 0, 1.1, .none), width: 300).page == nil)
        #expect(router.handle(s(-70, 0, 1.4, .none), width: 300).page == 1)
    }
    @Test func resetDoesNotAdoptInertiaAndCancelledGestureCanRestart() {
        var router = ScrollPaging()
        _ = router.handle(s(-20, 0, 1, .began), width: 300)
        router.reset()
        #expect(router.handle(s(-100, 0, 1.01, .momentumChanged), width: 300) == .pass)
        #expect(router.handle(s(-40, 0, 2, .began), width: 300).page == nil)
        #expect(router.handle(s(0, 0, 2.01, .cancelled), width: 300) == .pass)
        #expect(router.handle(s(-80, 0, 3, .began), width: 300).page == 1)
    }
    @Test func ordinaryMouseWheelNeverPages() {
        var router = ScrollPaging()
        #expect(router.handle(s(-120, 0, 1, .none, precise: false), width: 300) == .pass)
    }
}
