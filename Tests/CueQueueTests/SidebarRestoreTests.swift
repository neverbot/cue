@testable import CueQueue
import Testing

@Suite struct SidebarRestoreTests {
    @Test func restoresAWidthTheColumnAllows() {
        #expect(SidebarRestore.width(stored: 312, minimum: 200, maximum: 420) == 312)
    }

    @Test func clampsAWidthToTheColumnsLimits() {
        // A build may narrow what the column may take; an old width must not be refused, only fitted.
        #expect(SidebarRestore.width(stored: 90, minimum: 200, maximum: 420) == 200)
        #expect(SidebarRestore.width(stored: 900, minimum: 200, maximum: 420) == 420)
    }

    @Test func ignoresAWidthThatIsNotAWidth() {
        #expect(SidebarRestore.width(stored: nil, minimum: 200, maximum: 420) == nil)
        #expect(SidebarRestore.width(stored: 0, minimum: 200, maximum: 420) == nil)
        #expect(SidebarRestore.width(stored: -40, minimum: 200, maximum: 420) == nil)
        #expect(SidebarRestore.width(stored: .infinity, minimum: 200, maximum: 420) == nil)
        #expect(SidebarRestore.width(stored: .nan, minimum: 200, maximum: 420) == nil)
    }

    @Test func restoresAScrollOffsetInsideTheList() {
        #expect(SidebarRestore.scrollOffset(stored: 540, contentHeight: 3_000, visibleHeight: 600) == 540)
    }

    @Test func neverScrollsPastTheLastRow() {
        // The queue was emptied since the offset was saved: stop at the bottom, not in empty space below it.
        #expect(SidebarRestore.scrollOffset(stored: 5_000, contentHeight: 3_000, visibleHeight: 600) == 2_400)
    }

    @Test func aListThatFitsHasNowhereToScroll() {
        #expect(SidebarRestore.scrollOffset(stored: 300, contentHeight: 400, visibleHeight: 600) == 0)
    }

    @Test func ignoresAnOffsetThatIsNotAnOffset() {
        #expect(SidebarRestore.scrollOffset(stored: nil, contentHeight: 3_000, visibleHeight: 600) == nil)
        #expect(SidebarRestore.scrollOffset(stored: -10, contentHeight: 3_000, visibleHeight: 600) == nil)
        #expect(SidebarRestore.scrollOffset(stored: .nan, contentHeight: 3_000, visibleHeight: 600) == nil)
    }
}
