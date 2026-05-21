import Foundation
import Carbon
import CoreGraphics

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

func checkAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        fputs("Error: accessibility permission required.\nGo to System Settings → Privacy & Security → Accessibility and grant access.\n", stderr)
        exit(3)
    }
}

// MARK: - Key Event Simulation

func tapRightOptionOnce() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: true)
    down?.type = .flagsChanged
    down?.flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x00000040)
    down?.post(tap: .cgSessionEventTap)

    let up = CGEvent(keyboardEventSource: src, virtualKey: 61, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: .cgSessionEventTap)
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
var daemonRestoreItem: DispatchWorkItem? = nil

let DAEMON_KEYCODE_RIGHT_CMD: CGKeyCode = 54
let DAEMON_OPTION_PRESS_DELAY: TimeInterval = 0.30   // 按下后多久触发开始
let DAEMON_OPTION_TAP_INTERVAL: TimeInterval = 0.18  // 双击间隔
let DAEMON_RESTORE_DELAY: TimeInterval = 2.0          // 松开后多久恢复输入法

func daemonOnRightCmdDown() {
    guard !daemonRightCmdIsDown else { return }
    daemonRightCmdIsDown = true

    // 取消上一轮未执行完的恢复
    daemonRestoreItem?.cancel()
    daemonRestoreItem = nil

    // 记录当前输入法，切换到豆包
    daemonPreviousInputSource = getCurrentInputSourceName()
    _ = selectInputSource(named: daemonTargetIME)

    // 延迟后模拟双击右 Option → 开始录音
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_PRESS_DELAY) {
        guard daemonRightCmdIsDown else { return }
        tapRightOptionOnce()
        DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
            guard daemonRightCmdIsDown else { return }
            tapRightOptionOnce()
        }
    }
}

func daemonOnRightCmdUp() {
    guard daemonRightCmdIsDown else { return }
    daemonRightCmdIsDown = false

    // 模拟双击右 Option → 停止录音
    tapRightOptionOnce()
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
        tapRightOptionOnce()
    }

    // 延迟 2 秒后恢复原输入法（给豆包时间完成识别和插字）
    let previous = daemonPreviousInputSource
    let item = DispatchWorkItem {
        if let src = previous, !src.isEmpty {
            _ = selectInputSource(named: src)
        }
        daemonPreviousInputSource = nil
    }
    daemonRestoreItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_RESTORE_DELAY, execute: item)
}

// CGEventTap callback：必须是全局函数，不能是闭包
func daemonEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keycode == DAEMON_KEYCODE_RIGHT_CMD else { return Unmanaged.passUnretained(event) }

    // 用内部状态判断按下/松开，不依赖 flags.cmd（更可靠，与 Hammerspoon 相同策略）
    if daemonRightCmdIsDown {
        daemonOnRightCmdUp()
    } else {
        daemonOnRightCmdDown()
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
    """, stderr)
    exit(1)
}

switch args[1] {

case "daemon":
    // Push-to-Talk 守护进程：按住右 Command 说话，松开停止，2 秒后恢复输入法
    daemonTargetIME = parseTarget(from: args)

    checkAccessibilityPermission()

    let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: daemonEventCallback,
        userInfo: nil
    ) else {
        fputs("Error: failed to create CGEventTap. Make sure accessibility permission is granted.\n", stderr)
        exit(1)
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    print("doubao-ime daemon started (target: \(daemonTargetIME)). Hold Right Command to talk.")
    CFRunLoopRun()

case "full-flow":
    // 单次触发：切换 → 双击 → 等待 → 恢复（供 Raycast 版本使用）
    let target = parseTarget(from: args)
    let delayMs = parseDelay(from: args)
    let previous = getCurrentInputSourceName() ?? ""
    print(previous)

    guard selectInputSource(named: target) else {
        fputs("Error: input source '\(target)' not found\n", stderr)
        exit(2)
    }
    usleep(300_000)
    checkAccessibilityPermission()
    doubleTapRightOption()
    usleep(delayMs * 1000)
    if !previous.isEmpty { _ = selectInputSource(named: previous) }

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
