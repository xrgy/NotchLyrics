import AppKit
import SwiftUI

@MainActor
public final class NotchPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<NotchOverlayView>
    private let viewModel: AppModel
    private let overlayState: NotchOverlayState
    private var pendingCollapseTask: Task<Void, Never>?
    private var expansionTask: Task<Void, Never>?
    private var targetExpanded = false
    private let expandAnimationDuration = 0.16
    private let collapseAnimationDuration = 0.28

    public init(viewModel: AppModel) {
        self.viewModel = viewModel
        self.overlayState = NotchOverlayState(expandedWidth: NotchOverlayMetrics.width)
        self.hostingView = NSHostingView(
            rootView: NotchOverlayView(model: viewModel, overlayState: overlayState)
        )
        self.panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: NotchOverlayMetrics.width,
                height: NotchOverlayMetrics.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        hostingView.rootView = makeRootView()
    }

    public func show() {
        updatePanelFrame(expanded: targetExpanded)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func refresh() {
        overlayState.expandedWidth = expandedWidth(for: currentScreen())
        overlayState.setContainerExpanded(targetExpanded)
        updatePanelFrame(expanded: targetExpanded)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makeRootView() -> NotchOverlayView {
        return NotchOverlayView(
            model: viewModel,
            overlayState: overlayState
        ) { [weak self] expanded in
            self?.setHovering(expanded)
        }
    }

    private func setHovering(_ hovering: Bool) {
        if hovering {
            pendingCollapseTask?.cancel()
            pendingCollapseTask = nil
            setExpanded(true)
            return
        }

        pendingCollapseTask?.cancel()
        pendingCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            while self.isMouseInsidePanel(margin: 8), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            self.setExpanded(false)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard targetExpanded != expanded else { return }
        targetExpanded = expanded
        overlayState.expandedWidth = expandedWidth(for: currentScreen())
        let duration = expanded ? expandAnimationDuration : collapseAnimationDuration

        expansionTask?.cancel()
        expansionTask = Task { @MainActor [weak self] in
            await self?.animateExpansion(expanded: expanded, duration: duration)
        }
    }

    private func animateExpansion(expanded: Bool, duration: TimeInterval) async {
        let targetProgress: CGFloat = expanded ? 1 : 0

        if expanded {
            overlayState.setContainerExpanded(true)
            overlayState.showsExpandedContent = true
            updatePanelFrame(expanded: true)
        }

        let startProgress = overlayState.expansionProgress
        let distance = abs(targetProgress - startProgress)
        let effectiveDuration = max(0.08, duration * TimeInterval(distance))
        let startTime = Date.timeIntervalSinceReferenceDate

        while !Task.isCancelled {
            let elapsed = Date.timeIntervalSinceReferenceDate - startTime
            let linearProgress = min(1, elapsed / effectiveDuration)
            let easedProgress = smoothStep(CGFloat(linearProgress))
            overlayState.expansionProgress = startProgress + (targetProgress - startProgress) * easedProgress

            if linearProgress >= 1 {
                break
            }

            try? await Task.sleep(for: .milliseconds(16))
        }

        guard !Task.isCancelled else { return }
        overlayState.expansionProgress = targetProgress

        if !expanded {
            overlayState.showsExpandedContent = false
            overlayState.setContainerExpanded(false)
            updatePanelFrame(expanded: false)
        }
    }

    private func updatePanelFrame(expanded: Bool) {
        guard let screen = currentScreen() else { return }
        let frame = screen.frame
        let width = snap(expanded ? overlayState.expandedWidth : NotchOverlayMetrics.width, for: screen)
        let height = snap(expanded ? overlayState.expandedHeight : NotchOverlayMetrics.height, for: screen)
        let x = snap(frame.midX - width / 2, for: screen)
        let y = snap(frame.maxY - height + 8, for: screen)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    private func smoothStep(_ progress: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, progress))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private func expandedWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 520 }
        return max(NotchOverlayMetrics.width, floor(screen.frame.width / 3))
    }

    private func snap(_ value: CGFloat, for screen: NSScreen) -> CGFloat {
        let scale = max(screen.backingScaleFactor, 1)
        return (value * scale).rounded() / scale
    }

    private func isMouseInsidePanel(margin: CGFloat) -> Bool {
        panel.frame.insetBy(dx: -margin, dy: -margin).contains(NSEvent.mouseLocation)
    }
}
