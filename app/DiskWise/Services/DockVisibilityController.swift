import AppKit

enum DockVisibilityController {
    @MainActor
    static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}
