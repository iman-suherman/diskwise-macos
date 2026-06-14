import AppKit
import SwiftUI

@MainActor
final class MenuBarPopoverSession: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private weak var anchorView: NSView?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    var isShown: Bool { popover?.isShown ?? false }

    func close() {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            tearDown()
        }
    }

    func toggle<V: View>(
        anchoredTo anchorView: NSView,
        contentSize: NSSize,
        @ViewBuilder content: () -> V,
        onShow: (() -> Void)? = nil
    ) {
        if isShown {
            close()
            return
        }

        let popover = NSPopover()
        popover.contentSize = contentSize
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content())
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        self.popover = popover
        self.anchorView = anchorView
        beginOutsideClickMonitoring()
        onShow?()
    }

    func popoverDidClose(_ notification: Notification) {
        tearDown()
    }

    private func beginOutsideClickMonitoring() {
        endOutsideClickMonitoring()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isShown else { return event }
            if self.shouldClose(for: event) {
                self.close()
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func endOutsideClickMonitoring() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func tearDown() {
        endOutsideClickMonitoring()
        popover = nil
        anchorView = nil
    }

    private func shouldClose(for event: NSEvent) -> Bool {
        guard popover != nil else { return false }

        if let popoverWindow = popover?.contentViewController?.view.window,
           event.window === popoverWindow {
            return false
        }

        if let anchorView,
           let anchorWindow = anchorView.window,
           event.window === anchorWindow {
            let point = anchorView.convert(event.locationInWindow, from: nil)
            if anchorView.bounds.contains(point) {
                return false
            }
        }

        return true
    }
}
