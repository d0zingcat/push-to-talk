import Foundation
import CoreGraphics
import ApplicationServices

// 测试：按住右 Command → 模拟 Fn HID long-press，松开右 Command → 松开 Fn
// 用法: ./rcmd-to-fn   (Ctrl+C 退出)
// 需要 Accessibility + Input Monitoring 权限。测试前关闭 PushToTalk daemon。
//
// 关键发现：
// - 必须用 hidSystemState + cghidEventTap 才能触发验 HID 状态的输入法（如微信）
// - 按住右 Cmd 触发时，必须先向 HID 注入一个 Cmd UP 把 Command 从 HID 状态清掉，
//   否则 WeChat 验到 Fn+Cmd 组合不触发
// - 注入的 Cmd UP 会被自己的 listenOnly tap 收到，需用 eventSourceUnixProcessID
//   区分物理事件（pid=0）和自己注入的事件（pid=本进程）

let RIGHT_CMD_KEYCODE: CGKeyCode = 54
let RIGHT_CMD_FLAG_RAW: UInt64 = 0x00000010
let FN_KEYCODE: CGKeyCode = 63
let OUR_PID = Int64(ProcessInfo.processInfo.processIdentifier)

fputs("Accessibility trusted: \(AXIsProcessTrusted()), pid=\(OUR_PID)\n", stderr)
fputs("Hold Right Command to simulate Fn long-press. Ctrl+C to quit.\n", stderr)

let SETTLE_DELAY = 0.3

var isCmdDown = false
var pendingDown: DispatchWorkItem? = nil

func postFnDown() {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: FN_KEYCODE, keyDown: true)
    e?.type = .flagsChanged
    e?.flags = .maskSecondaryFn
    e?.post(tap: .cghidEventTap)
    fputs("→ Fn DOWN at \(Date())\n", stderr)
}

func postFnUp() {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: FN_KEYCODE, keyDown: false)
    e?.type = .flagsChanged
    e?.flags = []
    e?.post(tap: .cghidEventTap)
    fputs("→ Fn UP at \(Date())\n", stderr)
}

func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
    let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.rawValue
    // 打印所有 flagsChanged 事件，帮助诊断
    fputs("  flagsChanged: keycode=\(keycode) pid=\(sourcePID) flags=0x\(String(flags, radix:16)) isCmdDown=\(isCmdDown)\n", stderr)

    // 跳过我们自己注入的事件，只响应物理键盘事件（物理事件 pid=0）
    guard sourcePID != OUR_PID else { return Unmanaged.passUnretained(event) }
    guard keycode == RIGHT_CMD_KEYCODE else { return Unmanaged.passUnretained(event) }

    let isDown = (flags & RIGHT_CMD_FLAG_RAW) != 0
    if isDown, !isCmdDown {
        isCmdDown = true
        fputs("right-Cmd down, waiting \(Int(SETTLE_DELAY * 1000))ms...\n", stderr)
        let item = DispatchWorkItem {
            guard isCmdDown else { return }
            // 向 HID 层注入 Cmd UP，把 Command 从 HID 状态清掉，
            // 让 WeChat 看到"纯 Fn 长按"而非 Fn+Cmd 组合
            let cmdSrc = CGEventSource(stateID: .hidSystemState)
            let cmdUp = CGEvent(keyboardEventSource: cmdSrc, virtualKey: RIGHT_CMD_KEYCODE, keyDown: false)
            cmdUp?.type = .flagsChanged
            cmdUp?.flags = []
            cmdUp?.post(tap: .cghidEventTap)
            fputs("→ right-Cmd UP (HID suppress) at \(Date())\n", stderr)
            postFnDown()
        }
        pendingDown = item
        DispatchQueue.main.asyncAfter(deadline: .now() + SETTLE_DELAY, execute: item)
    } else if !isDown, isCmdDown {
        isCmdDown = false
        pendingDown?.cancel()
        pendingDown = nil
        postFnUp()
    }
    return Unmanaged.passUnretained(event)
}

let eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: tapCallback,
    userInfo: nil
) else {
    fputs("Failed to create event tap — grant Input Monitoring to this binary.\n", stderr)
    exit(1)
}

let runSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), runSrc, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

CFRunLoopRun()
