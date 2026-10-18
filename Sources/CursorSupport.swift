import AppKit
import SwiftUI

// AppKit tracking areas own cursor transitions, including the return to an
// adjacent text field. The overlay never intercepts clicks or drags.
private final class LauncherCursorRegionView: NSView {
    private var cursorTrackingArea: NSTrackingArea?

    var enabled = true {
        didSet {
            if enabled != oldValue { refreshCursorRect() }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeCursorTrackingArea()
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        let area = NSTrackingArea(rect: .zero,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !isHiddenOrHasHiddenAncestor else { return }
        (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        // Do not forward to super: the default cursor could replace this one.
        // AppKit restores the next area's cursor when the pointer leaves.
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty {
            addCursorRect(visibleRect, cursor: enabled ? .pointingHand : .arrow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshCursorRect()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        removeCursorTrackingArea()
        discardCursorRects()
        super.viewWillMove(toWindow: newWindow)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshCursorRect()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        refreshCursorRect()
    }

    private func refreshCursorRect() {
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    private func removeCursorTrackingArea() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
            self.cursorTrackingArea = nil
        }
    }
}

private struct LauncherCursorRegion: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> LauncherCursorRegionView {
        let view = LauncherCursorRegionView()
        view.setAccessibilityElement(false)
        view.enabled = enabled
        return view
    }

    func updateNSView(_ view: LauncherCursorRegionView, context: Context) {
        view.enabled = enabled
    }
}

private struct LauncherPointerModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            LauncherCursorRegion(enabled: isEnabled && enabled)
                .accessibilityHidden(true)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                (isEnabled && enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            case .ended:
                hovering = false
                restoreNativeCursor()
            }
        }
        .onChange(of: isEnabled && enabled) { _, active in
            if hovering { (active ? NSCursor.pointingHand : NSCursor.arrow).set() }
        }
        .onDisappear {
            if hovering {
                hovering = false
                restoreNativeCursor()
            }
        }
    }

    private func restoreNativeCursor() {
        // Recompute at the actual pointer position, rather than forcing an arrow
        // over a text field that the pointer may already have entered.
        NSApp.keyWindow?.resetCursorRects()
    }
}

extension View {
    // Apply before .disabled(...) so the modifier inherits that control's state.
    func launcherPointer(enabled: Bool = true) -> some View {
        modifier(LauncherPointerModifier(enabled: enabled))
    }
}
