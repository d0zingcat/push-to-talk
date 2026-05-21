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
        fputs("Error: accessibility permission required. Go to System Settings → Privacy & Security → Accessibility and grant access to Raycast (or Terminal if testing from CLI).\n", stderr)
        exit(3)
    }
}

// MARK: - Key Event Simulation

func doubleTapLeftOption() {
    func tapOnce() {
        // keyCode 61 = 右 Option (kVK_RightOption)
        CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: true)?.post(tap: .cgSessionEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: false)?.post(tap: .cgSessionEventTap)
    }

    tapOnce()
    usleep(18_000)
    tapOnce()
}

// MARK: - CLI Argument Parsers

func parseTarget(from args: [String]) -> String {
    guard let idx = args.firstIndex(of: "--target"), idx + 1 < args.count else {
        fputs("Error: --target <name> is required\n", stderr)
        exit(1)
    }
    return args[idx + 1]
}

func parseDelay(from args: [String]) -> UInt32 {
    guard let idx = args.firstIndex(of: "--delay"), idx + 1 < args.count,
          let ms = UInt32(args[idx + 1]) else {
        return 3000
    }
    return ms
}

// MARK: - CLI Entry

let args = CommandLine.arguments

guard args.count >= 2 else {
    fputs("Usage: doubao-ime-helper <full-flow|restore> --target <name> [--delay <ms>]\n", stderr)
    exit(1)
}

switch args[1] {
case "full-flow":
    // 完整流程：切换 → 双击 Option → 等待 → 恢复。作为后台进程运行，与 TypeScript 进程完全分离。
    let target = parseTarget(from: args)
    let delayMs = parseDelay(from: args)

    let previous = getCurrentInputSourceName() ?? ""

    guard selectInputSource(named: target) else {
        fputs("Error: input source '\(target)' not found\n", stderr)
        exit(2)
    }
    usleep(300_000)  // 等 300ms 让切换生效，比 100ms 更可靠
    checkAccessibilityPermission()
    doubleTapLeftOption()

    usleep(delayMs * 1000)  // 等待用户语音输入（毫秒转微秒）

    if !previous.isEmpty {
        _ = selectInputSource(named: previous)
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
