import AppKit
import CoreGraphics
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Push to Talk") {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.title = "🎙️"
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Build popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainMenuView())
        self.popover = popover

        // Load config and update state
        AppStateManager.shared.refreshPermissionState()
        
        if AppStateManager.shared.isEnabled {
            enableEventTap()
        }

        // Start timer to check permission state when window is active or periodically
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            AppStateManager.shared.refreshPermissionState()
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if let popover = popover {
            if popover.isShown {
                closePopover(sender)
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        closePopover(nil)
    }

    private func closePopover(_ sender: AnyObject?) {
        guard let popover = popover, popover.isShown else { return }
        popover.performClose(sender)
    }

    func enableEventTap() {
        if daemonEventTap != nil { return }
        guard checkInputMonitoringPermission(prompt: false) else {
            logDaemon("Error: Input Monitoring permission missing; cannot create CGEventTap.")
            DispatchQueue.main.async {
                AppStateManager.shared.hasInputMonitoringPermission = false
                AppStateManager.shared.hasPermission = false
            }
            return
        }
        
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: daemonEventCallback,
            userInfo: nil
        ) else {
            logDaemon("Error: failed to create CGEventTap. Input Monitoring permission missing?")
            DispatchQueue.main.async {
                AppStateManager.shared.isEnabled = false
                AppStateManager.shared.hasInputMonitoringPermission = false
                AppStateManager.shared.hasPermission = false
            }
            return
        }
        daemonEventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logDaemon("Event tap enabled in GUI mode.")
        
        DispatchQueue.main.async {
            AppStateManager.shared.hasInputMonitoringPermission = true
            AppStateManager.shared.hasPermission =
                AppStateManager.shared.hasAccessibilityPermission &&
                AppStateManager.shared.hasInputMonitoringPermission
        }
    }

    func disableEventTap() {
        guard let tap = daemonEventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        daemonEventTap = nil
        logDaemon("Event tap disabled in GUI mode.")
    }
}
