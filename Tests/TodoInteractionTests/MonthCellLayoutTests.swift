import Testing
@testable import TodoInteraction

@Suite struct MonthCellLayoutTests {
    @Test func sixRowMonthKeepsAnEventAboveOverflow() {
        let layout = MonthCellLayout(height: 88, itemCount: 5)
        #expect(layout.visibleCount == 1)
        #expect(layout.hiddenCount == 4)
    }
    @Test func roomyCellUsesSpaceAndKeepsEveryItemReachable() {
        let layout = MonthCellLayout(height: 150, itemCount: 7)
        #expect(layout.visibleCount == 3)
        #expect(layout.hiddenCount == 4)
        #expect(layout.visibleCount + layout.hiddenCount == 7)
    }
    @Test func fittingItemsNeedNoOverflow() {
        let layout = MonthCellLayout(height: 93, itemCount: 2)
        #expect(layout.visibleCount == 2)
        #expect(layout.hiddenCount == 0)
    }
    @Test func shortAndEmptyCellsRemainBounded() {
        #expect(MonthCellLayout(height: 40, itemCount: 10).hiddenCount == 10)
        #expect(MonthCellLayout(height: 88, itemCount: 0).visibleCount == 0)
    }
}
