import Foundation
import AppKit
import CoreGraphics

func daemonOnRightCmdDown() {
    let DAEMON_OPTION_PRESS_DELAY = daemonOptionPressDelay
    logDaemon("right-command down")

    daemonActivationItem?.cancel()
    let item = DispatchWorkItem {
        daemonActivateVoiceSession()
    }
    daemonActivationItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_PRESS_DELAY, execute: item)
}

func daemonActivateVoiceSession() {
    let DAEMON_INPUT_SOURCE_SETTLE_DELAY = daemonSettleDelay
    let DAEMON_OPTION_TAP_INTERVAL = daemonOptionTapInterval
    guard daemonRightCmdIsDown else {
        logDaemon("right-command press was shorter than activation delay")
        return
    }
    guard !daemonVoiceSessionIsActive else { return }
    daemonVoiceSessionIsActive = true
    DispatchQueue.main.async {
        if NSApplication.shared.delegate != nil {
            AppStateManager.shared.voiceSessionIsActive = true
        }
    }

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
        DispatchQueue.main.async {
            if NSApplication.shared.delegate != nil {
                AppStateManager.shared.voiceSessionIsActive = false
            }
        }
        return
    }

    // 等输入法切换真正生效后，再模拟双击右 Option → 开始录音
    logDaemon("waiting \(Int(DAEMON_INPUT_SOURCE_SETTLE_DELAY * 1000))ms for input source settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_INPUT_SOURCE_SETTLE_DELAY) {
        guard daemonRightCmdIsDown, daemonVoiceSessionIsActive else { return }
        if daemonListeningMode == "long_press_fn" {
            logDaemon("starting Fn long press, current='\(getCurrentInputSourceName() ?? "")'")
            simulateFnDown()
        } else {
            logDaemon("starting right-option double tap, current='\(getCurrentInputSourceName() ?? "")'")
            tapRightOptionOnce()
            DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
                guard daemonRightCmdIsDown, daemonVoiceSessionIsActive else { return }
                tapRightOptionOnce()
            }
        }
    }
}

func daemonOnRightCmdUp() {
    let DAEMON_RESTORE_DELAY = daemonRestoreDelay
    daemonActivationItem?.cancel()
    daemonActivationItem = nil
    daemonIgnoreRightCmdDownUntil = Date().addingTimeInterval(DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL)
    guard daemonVoiceSessionIsActive else {
        logDaemon("right-command up before voice session activation")
        return
    }
    daemonVoiceSessionIsActive = false
    DispatchQueue.main.async {
        if NSApplication.shared.delegate != nil {
            AppStateManager.shared.voiceSessionIsActive = false
        }
    }
    logDaemon("right-command up")

    if daemonListeningMode == "long_press_fn" {
        simulateFnUp()
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
    let DAEMON_KEYCODE_RIGHT_CMD = daemonTriggerKeycode
    let DAEMON_RIGHT_CMD_FLAG_RAW = daemonTriggerFlagRaw

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        daemonHandleTapDisabled(type)
        return nil
    }

    if type == .keyDown {
        DispatchQueue.main.async {
            if daemonRestoreItem != nil {
                logDaemon("typing detected during restore delay; interrupting wait and restoring immediately")
                daemonRestoreItem?.cancel()
                daemonRestoreItem = nil
                if let src = daemonPreviousInputSource, !src.isEmpty {
                    let restored = selectInputSource(named: src)
                    logDaemon("restore previous '\(src)' result=\(restored)")
                }
                daemonPreviousInputSource = nil
            }
        }
        return Unmanaged.passUnretained(event)
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
