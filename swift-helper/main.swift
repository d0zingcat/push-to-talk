import Foundation
import Carbon
import CoreGraphics

func logDaemon(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

// MARK: - Input Source Helpers

func getInputSourceName(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func getCurrentInputSourceName() -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    return getInputSourceName(source)
}

func selectInputSource(named name: String) -> Bool {
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    for source in list {
        if getInputSourceName(source) == name {
            TISSelectInputSource(source)
            return true
        }
    }
    return false
}

// MARK: - Accessibility Permission Check

func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func requireAccessibilityPermission(prompt: Bool = false) {
    guard hasAccessibilityPermission(prompt: prompt) else {
        fputs("Error: accessibility permission required.\nGo to System Settings → Privacy & Security → Accessibility and grant access.\n", stderr)
        exit(3)
    }
}

// MARK: - Key Event Simulation

func tapRightOptionOnce() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let rightOptionFlags = CGEventFlags(
        rawValue: CGEventFlags.maskAlternate.rawValue | DAEMON_RIGHT_OPTION_FLAG_RAW
    )

    let down = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: true)
    down?.type = .flagsChanged
    down?.flags = rightOptionFlags
    down?.post(tap: .cgSessionEventTap)

    let up = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: .cgSessionEventTap)

    logDaemon("posted right-option tap")
}

func doubleTapRightOption() {
    tapRightOptionOnce()
    usleep(180_000)  // 180ms，与 Hammerspoon OPTION_DOUBLE_TAP_INTERVAL = 0.18 一致
    tapRightOptionOnce()
}

// MARK: - Daemon State（全局，供 CGEventTap callback 使用）

var daemonTargetIME = "豆包输入法"
var daemonPreviousInputSource: String? = nil
var daemonRightCmdIsDown = false
var daemonVoiceSessionIsActive = false
var daemonActivationItem: DispatchWorkItem? = nil
var daemonRestoreItem: DispatchWorkItem? = nil
var daemonIgnoreRightCmdDownUntil = Date.distantPast
var daemonEventTap: CFMachPort? = nil
var daemonTapDisableEvents: [Date] = []

let DAEMON_KEYCODE_RIGHT_CMD: CGKeyCode = 54
let DAEMON_RIGHT_CMD_FLAG_RAW: UInt64 = 0x00000010
let DAEMON_RIGHT_OPTION_FLAG_RAW: UInt64 = 0x00000040
let DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL: TimeInterval = 0.45
let DAEMON_OPTION_PRESS_DELAY: TimeInterval = 0.30   // 按下后多久触发开始
let DAEMON_OPTION_TAP_INTERVAL: TimeInterval = 0.18  // 双击间隔
let DAEMON_RESTORE_DELAY: TimeInterval = 3.0          // 松开后多久恢复输入法
let DAEMON_TAP_DISABLE_WINDOW: TimeInterval = 60.0
let DAEMON_TAP_DISABLE_MAX_COUNT = 3

func daemonOnRightCmdDown() {
    logDaemon("right-command down")

    daemonActivationItem?.cancel()
    let item = DispatchWorkItem {
        daemonActivateVoiceSession()
    }
    daemonActivationItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_PRESS_DELAY, execute: item)
}

func daemonActivateVoiceSession() {
    guard daemonRightCmdIsDown else {
        logDaemon("right-command press was shorter than activation delay")
        return
    }
    guard !daemonVoiceSessionIsActive else { return }
    daemonVoiceSessionIsActive = true

    // 取消上一轮未执行完的恢复
    daemonRestoreItem?.cancel()
    daemonRestoreItem = nil

    // 记录当前输入法，切换到豆包
    daemonPreviousInputSource = getCurrentInputSourceName()
    let switched = selectInputSource(named: daemonTargetIME)
    logDaemon("switch to target '\(daemonTargetIME)' result=\(switched), previous='\(daemonPreviousInputSource ?? "")'")
    guard switched else {
        daemonVoiceSessionIsActive = false
        daemonPreviousInputSource = nil
        return
    }

    // 模拟双击右 Option → 开始录音
    logDaemon("starting right-option double tap, current='\(getCurrentInputSourceName() ?? "")'")
    tapRightOptionOnce()
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
        guard daemonRightCmdIsDown, daemonVoiceSessionIsActive else { return }
        tapRightOptionOnce()
    }
}

func daemonOnRightCmdUp() {
    daemonActivationItem?.cancel()
    daemonActivationItem = nil
    daemonIgnoreRightCmdDownUntil = Date().addingTimeInterval(DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL)
    guard daemonVoiceSessionIsActive else {
        logDaemon("right-command up before voice session activation")
        return
    }
    daemonVoiceSessionIsActive = false
    logDaemon("right-command up")

    // 模拟双击右 Option → 停止录音
    tapRightOptionOnce()
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
        tapRightOptionOnce()
    }

    // 延迟 3 秒后恢复原输入法（给豆包时间完成识别和插字）
    let previous = daemonPreviousInputSource
    let item = DispatchWorkItem {
        if let src = previous, !src.isEmpty {
            let restored = selectInputSource(named: src)
            logDaemon("restore previous '\(src)' result=\(restored)")
        }
        daemonPreviousInputSource = nil
    }
    daemonRestoreItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_RESTORE_DELAY, execute: item)
}

func daemonHandleTapDisabled(_ type: CGEventType) {
    let now = Date()
    daemonTapDisableEvents = daemonTapDisableEvents.filter { now.timeIntervalSince($0) <= DAEMON_TAP_DISABLE_WINDOW }
    daemonTapDisableEvents.append(now)

    if daemonTapDisableEvents.count >= DAEMON_TAP_DISABLE_MAX_COUNT {
        logDaemon("event tap disabled \(daemonTapDisableEvents.count) times in \(Int(DAEMON_TAP_DISABLE_WINDOW))s; exiting to protect system input")
        if let tap = daemonEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        exit(70)
    }

    if let tap = daemonEventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
        logDaemon("event tap re-enabled after \(type), count=\(daemonTapDisableEvents.count)")
    }
}

// CGEventTap callback：必须是全局函数，不能是闭包
func daemonEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        daemonHandleTapDisabled(type)
        return nil
    }

    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keycode == DAEMON_KEYCODE_RIGHT_CMD else { return Unmanaged.passUnretained(event) }

    let isRightCmdDown = (event.flags.rawValue & DAEMON_RIGHT_CMD_FLAG_RAW) != 0
    if isRightCmdDown {
        if Date() < daemonIgnoreRightCmdDownUntil {
            logDaemon("ignored right-command down during release suppress window")
            return Unmanaged.passUnretained(event)
        }
        guard !daemonRightCmdIsDown else { return Unmanaged.passUnretained(event) }
        daemonRightCmdIsDown = true
        DispatchQueue.main.async {
            daemonOnRightCmdDown()
        }
    } else {
        guard daemonRightCmdIsDown else { return Unmanaged.passUnretained(event) }
        daemonRightCmdIsDown = false
        daemonIgnoreRightCmdDownUntil = Date().addingTimeInterval(DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL)
        DispatchQueue.main.async {
            daemonOnRightCmdUp()
        }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - CLI Argument Parsers

func parseTarget(from args: [String]) -> String {
    guard let idx = args.firstIndex(of: "--target"), idx + 1 < args.count else {
        return "豆包输入法"
    }
    return args[idx + 1]
}

func parseDelay(from args: [String]) -> UInt32 {
    guard let idx = args.firstIndex(of: "--delay"), idx + 1 < args.count,
          let ms = UInt32(args[idx + 1]) else { return 3000 }
    return ms
}

// MARK: - CLI Entry

let args = CommandLine.arguments

guard args.count >= 2 else {
    fputs("""
    Usage:
      doubao-ime-helper daemon   [--target <ime-name>]
      doubao-ime-helper full-flow --target <ime-name> --delay <ms>
      doubao-ime-helper restore  --target <ime-name>
      doubao-ime-helper check-permission
    """, stderr)
    exit(1)
}

switch args[1] {

case "daemon":
    // Push-to-Talk 守护进程：按住右 Command 说话，松开停止，3 秒后恢复输入法
    daemonTargetIME = parseTarget(from: args)

    if !hasAccessibilityPermission(prompt: false) {
        logDaemon("accessibility preflight returned false; attempting CGEventTap anyway")
    }

    let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: daemonEventCallback,
        userInfo: nil
    ) else {
        fputs("Error: failed to create CGEventTap. Make sure accessibility permission is granted.\n", stderr)
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
    usleep(300_000)
    requireAccessibilityPermission(prompt: true)
    doubleTapRightOption()
    usleep(delayMs * 1000)
    if !previous.isEmpty { _ = selectInputSource(named: previous) }

case "check-permission":
    requireAccessibilityPermission(prompt: true)
    print("accessibility permission granted")

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
