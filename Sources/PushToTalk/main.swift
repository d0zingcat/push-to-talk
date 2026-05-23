import Foundation
import Carbon
import CoreGraphics
import AppKit

// MARK: - CLI Entry

let args = CommandLine.arguments

if args.count < 2 {
    logDaemon("Starting Push-to-Talk Menu Bar GUI...")
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}

switch args[1] {

case "daemon":
    // Push-to-Talk 守护进程：按住右 Command 说话，松开停止，3 秒后恢复输入法
    daemonTargetIME = parseTarget(from: args)

    if !checkAccessibilityPermission(prompt: false) {
        fputs("Error: daemon requires Accessibility permission to post right Option events.\nGrant access to ~/.local/bin/pushtotalk in System Settings → Privacy & Security → Accessibility, then run ./scripts/restart-daemon.sh.\n", stderr)
        exit(3)
    }
    if !checkInputMonitoringPermission(prompt: false) {
        fputs("Error: daemon requires Input Monitoring permission to observe right Command events.\nGrant access to ~/.local/bin/pushtotalk in System Settings → Privacy & Security → Input Monitoring, then run ./scripts/restart-daemon.sh.\n", stderr)
        exit(3)
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
        fputs("Error: failed to create CGEventTap. Make sure Input Monitoring permission is granted.\n", stderr)
        exit(1)
    }
    daemonEventTap = tap

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    logDaemon("doubao-ime daemon started (target: \(daemonTargetIME)). Hold Right Command to talk.")
    CFRunLoopRun()

case "full-flow":
    // 单次触发：切换 → 双击 → 等待 → 恢复
    let target = parseTarget(from: args)
    let delayMs = parseDelay(from: args)
    let previous = getCurrentInputSourceName() ?? ""
    print(previous)

    guard selectInputSource(named: target) else {
        fputs("Error: input source '\(target)' not found\n", stderr)
        exit(2)
    }
    usleep(UInt32(DAEMON_INPUT_SOURCE_SETTLE_DELAY * 1_000_000))
    requireAccessibilityPermission(prompt: true)
    doubleTapRightOption()
    usleep(delayMs * 1000)
    if !previous.isEmpty { _ = selectInputSource(named: previous) }

case "check-permission":
    requireAccessibilityPermission(prompt: true)
    print("accessibility permission granted")

case "list-sources":
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    var names = Set<String>()
    for src in list {
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            names.insert(name)
        }
    }
    for name in names.sorted() {
        print(name)
    }

case "restore":
    let target = parseTarget(from: args)
    guard selectInputSource(named: target) else {
        fputs("Error: input source '\(target)' not found\n", stderr)
        exit(2)
    }

default:
    fputs("Error: unknown command '\(args[1])'\n", stderr)
    exit(1)
}
