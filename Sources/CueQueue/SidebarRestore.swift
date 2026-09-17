import Foundation

/// Turns what was stored about the sidebar into something safe to apply now.
///
/// Stored values come from a previous session, and the world may have moved since: the queue may have been emptied
/// in between, or a build may have changed how wide the column may be. Applying them raw would scroll the list into
/// empty space below its last row, or ask the split view for a width it is not allowed to take. Decided here, so it
/// is tested; the views only apply the answer.
public enum SidebarRestore {
    /// The width to give the sidebar, clamped to what the column allows, or nil when nothing usable was stored.
    public static func width(stored: Double?, minimum: Double, maximum: Double) -> Double? {
        guard let stored, stored.isFinite, stored > 0, minimum <= maximum else { return nil }
        return min(max(stored, minimum), maximum)
    }

    /// The scroll offset to restore, clamped so the list never shows space below its last row, or nil when nothing
    /// usable was stored. A list shorter than its view has nowhere to scroll, and gets zero.
    public static func scrollOffset(stored: Double?, contentHeight: Double, visibleHeight: Double) -> Double? {
        guard let stored, stored.isFinite, stored >= 0 else { return nil }
        let furthest = max(contentHeight - visibleHeight, 0)
        return min(stored, furthest)
    }
}
