import AppKit
import CoreGraphics

/// Captures wheel / trackpad scrolls over the selection and redispatches them to
/// the source application. `postToPid` delivers directly into that process, so
/// we must not gate events behind ignoresMouseEvents toggles — that drops most
/// wheel notches and trackpad samples and feels extremely choppy.
@MainActor
final class ScrollInputRelay {
    private var panel: NSPanel?
    private var targetProcessIdentifier: pid_t?
    private var restoreCaptureTask: Task<Void, Never>?

    func install(over globalRect: CGRect, targetProcessIdentifier: pid_t?) {
        remove()
        self.targetProcessIdentifier = targetProcessIdentifier

        let panel = ScrollRelayPanel(
            contentRect: globalRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.contentView = ScrollRelayView { [weak self] event in
            self?.forward(event)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func remove() {
        restoreCaptureTask?.cancel()
        restoreCaptureTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        targetProcessIdentifier = nil
    }

    private func forward(_ event: NSEvent) {
        guard event.type == .scrollWheel else { return }

        let payload = event.cgEvent?.copy() ?? makeScrollEvent(from: event)
        guard let payload else { return }

        // Let the rest of this wheel/trackpad burst reach the source window
        // natively. Toggling hit-testing for every sample drops events and makes
        // scrolling stutter; keeping a short pass-through interval preserves
        // the system's normal wheel acceleration and trackpad momentum.
        panel?.ignoresMouseEvents = true
        scheduleCaptureRestore()

        if let targetProcessIdentifier,
           targetProcessIdentifier != ProcessInfo.processInfo.processIdentifier {
            payload.postToPid(targetProcessIdentifier)
            return
        }

        payload.post(tap: .cghidEventTap)
    }

    private func scheduleCaptureRestore() {
        restoreCaptureTask?.cancel()
        restoreCaptureTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.panel?.ignoresMouseEvents = false
            self?.restoreCaptureTask = nil
        }
    }

    private func makeScrollEvent(from event: NSEvent) -> CGEvent? {
        let units: CGScrollEventUnit = event.hasPreciseScrollingDeltas ? .pixel : .line
        let vertical = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let horizontal = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let location = event.cgEvent?.location
            ?? CGPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 2,
            wheel1: Int32(vertical.rounded()),
            wheel2: Int32(horizontal.rounded()),
            wheel3: 0
        ) else {
            return nil
        }
        scrollEvent.location = location
        return scrollEvent
    }
}

private final class ScrollRelayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScrollRelayView: NSView {
    private let onScroll: (NSEvent) -> Void

    init(onScroll: @escaping (NSEvent) -> Void) {
        self.onScroll = onScroll
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func scrollWheel(with event: NSEvent) {
        onScroll(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}
