import AppKit

/// Common interface for the two display-mode controllers.
/// Both PetWindowController and NotchWindowController implement this so
/// WindowManager can hold either behind the same handle when it swaps modes.
@MainActor
protocol CoveModeWindowController: AnyObject {
    var viewModel: CoveViewModel { get }
    var panel: CovePanel? { get }
    func showWindow()
    func close()
    /// Called by WindowManager just before swapping to the other mode.
    /// Implementers should detach observers, save anchor, etc.
    func handleDisplayModeWillChange()
}
