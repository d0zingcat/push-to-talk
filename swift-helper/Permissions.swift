import Foundation
import AppKit
import CoreGraphics

// MARK: - Accessibility Permission Check

func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func checkInputMonitoringPermission(prompt: Bool = false) -> Bool {
    if prompt {
        return CGRequestListenEventAccess()
    }
    return CGPreflightListenEventAccess()
}

func requireAccessibilityPermission(prompt: Bool = false) {
    guard checkAccessibilityPermission(prompt: prompt) else {
        fputs("Error: accessibility permission required.\nGo to System Settings → Privacy & Security → Accessibility and grant access.\n", stderr)
        exit(3)
    }
}
