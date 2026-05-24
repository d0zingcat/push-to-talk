import Foundation
import CoreGraphics
import ApplicationServices

// 用法: swift tests/hold-right-option.swift [duration_ms]
// 默认按住右 Option 3000ms 再松开。
// 触发前会等 2 秒，给你时间切到目标应用（如微信）。

let args = CommandLine.arguments
let durationMs: UInt32 = (args.count >= 2 ? UInt32(args[1]) : nil) ?? 3000
let leadInSec: UInt32 = 2

let FN_KEYCODE: CGKeyCode = 63

let isTrusted = AXIsProcessTrusted()
fputs("Accessibility trusted: \(isTrusted)\n", stderr)
if !isTrusted {
    fputs("⚠️  当前进程没有辅助功能权限。请把运行此脚本的终端 (Terminal/iTerm/etc.) 加入：\n", stderr)
    fputs("   系统设置 → 隐私与安全性 → 辅助功能\n", stderr)
    fputs("   或者编译此脚本为独立可执行并对其授权。\n", stderr)
}

fputs("等待 \(leadInSec)s 后按下 Fn，持续 \(durationMs)ms...\n", stderr)
sleep(leadInSec)

let src = CGEventSource(stateID: .hidSystemState)

let down = CGEvent(keyboardEventSource: src, virtualKey: FN_KEYCODE, keyDown: true)
down?.type = .flagsChanged
down?.flags = .maskSecondaryFn
down?.post(tap: .cghidEventTap)
fputs("→ posted Fn DOWN (HID tap) at \(Date())\n", stderr)

usleep(durationMs * 1000)

let up = CGEvent(keyboardEventSource: src, virtualKey: FN_KEYCODE, keyDown: false)
up?.type = .flagsChanged
up?.flags = []
up?.post(tap: .cghidEventTap)
fputs("→ posted Fn UP (HID tap) at \(Date())\n", stderr)

fputs("完成。\n", stderr)
