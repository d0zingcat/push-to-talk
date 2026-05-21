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
    let src = CGEventSource(stateID: .hidSystemState)

    func tapOnce() {
        CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: false)?.post(tap: .cghidEventTap)
    }

    tapOnce()
    usleep(18_000)  // 18ms 间隔，与 Hammerspoon 版本一致
    tapOnce()
}

// MARK: - CLI Entry

func parseTarget(from args: [String]) -> String {
    guard let idx = args.firstIndex(of: "--target"), idx + 1 < args.count else {
        fputs("Error: --target <name> is required\n", stderr)
        exit(1)
    }
    return args[idx + 1]
}

let args = CommandLine.arguments

guard args.count >= 2 else {
    fputs("Usage: doubao-ime-helper <switch-and-trigger|restore> --target <name>\n", stderr)
    exit(1)
}

switch args[1] {
case "switch-and-trigger":
    let target = parseTarget(from: args)
    let previous = getCurrentInputSourceName() ?? ""
    print(previous)  // stdout 输出当前输入法名，供 TypeScript 侧读取

    guard selectInputSource(named: target) else {
        fputs("Error: input source '\(target)' not found\n", stderr)
        exit(2)
    }
    usleep(100_000)  // 等 100ms 让切换生效，再模拟按键
    checkAccessibilityPermission()
    doubleTapLeftOption()

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
