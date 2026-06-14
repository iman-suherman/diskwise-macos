import AppKit
import SwiftUI

@MainActor
final class MenuBarPopoverSession: NSObject, NSPopoverDelegate {
    private static weak var activeSession: MenuBarPopoverSession?

    static func closeActivePopover() {
        activeSession?.close()
    }

    private var popover: NSPopover?
    private weak var anchorView: NSView?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var mainWindowObserver: NSObjectProtocol?

    var isShown: Bool { popover?.isShown ?? false }

    func close() {
        guard popover != nil else { return }
        endObservation()
        popover?.close()
        tearDown()
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

        Self.activeSession?.close()

        let popover = NSPopover()
        popover.contentSize = contentSize
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: content())
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        self.popover = popover
        self.anchorView = anchorView
        Self.activeSession = self
        beginObservation()
        onShow?()
    }

    func popoverDidClose(_ notification: Notification) {
        tearDown()
    }

    private func beginObservation() {
        endObservation()

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

        mainWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isShown else { return }
            guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
            if window === self.popover?.contentViewController?.view.window { return }
            self.close()
        }
    }

    private func endObservation() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let mainWindowObserver {
            NotificationCenter.default.removeObserver(mainWindowObserver)
            self.mainWindowObserver = nil
        }
    }

    private func tearDown() {
        if Self.activeSession === self {
            Self.activeSession = nil
        }
        endObservation()
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

@MainActor
enum MenuBarMainWindowOpener {
    static func open(dismissingPopover dismiss: (() -> Void)? = nil) {
        dismiss?()
        MenuBarPopoverSession.closeActivePopover()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
