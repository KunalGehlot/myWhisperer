import AppKit
import OpenFlowCore
import SwiftUI

/// Floating pill near the bottom of the screen showing dictation state.
/// It never becomes key or activates the app, so focus stays where the user
/// is typing.
@MainActor
final class HUDController {
    private let panel: NSPanel
    private let model: AppModel
    private var hideWork: DispatchWorkItem?
    static let size = NSSize(width: 420, height: 90)

    init(model: AppModel, onAction: @escaping (ErrorAction) -> Void) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none

        let host = NSHostingView(rootView: HUDView(model: model, onAction: onAction))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    func update(for phase: DictationPhase) {
        hideWork?.cancel()
        if case .idle = phase {
            // Let the SwiftUI exit transition play before hiding the window.
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            return
        }
        if case .error(_, let action) = phase {
            panel.ignoresMouseEvents = action == nil
        } else {
            panel.ignoresMouseEvents = true
        }
        if !panel.isVisible {
            position()
            panel.orderFrontRegardless()
        }
    }

    private func position() {
        let screen = Self.activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 8)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
    }

    /// The screen showing the frontmost app's main window, falling back to
    /// the screen under the mouse.
    private static func activeScreen() -> NSScreen? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windows where (info[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (info[kCGWindowLayer as String] as? Int) == 0 {
                if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                   let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] {
                    // CG coordinates are top-left based on the primary screen.
                    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                    let center = NSPoint(x: x + w / 2, y: primaryHeight - (y + h / 2))
                    if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
                }
                break
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }
}
