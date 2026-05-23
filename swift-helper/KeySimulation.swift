import Foundation
import CoreGraphics

// MARK: - Key Event Simulation

func tapRightOptionOnce() {
    let DAEMON_RIGHT_OPTION_FLAG_RAW = daemonSimulateFlagRaw
    let simulateKeycode = daemonSimulateKeycode
    let src = CGEventSource(stateID: .combinedSessionState)
    let rightOptionFlags = CGEventFlags(
        rawValue: CGEventFlags.maskAlternate.rawValue | DAEMON_RIGHT_OPTION_FLAG_RAW
    )

    let down = CGEvent(keyboardEventSource: src, virtualKey: simulateKeycode, keyDown: true)
    down?.type = .flagsChanged
    down?.flags = rightOptionFlags
    down?.post(tap: .cgSessionEventTap)

    let up = CGEvent(keyboardEventSource: src, virtualKey: simulateKeycode, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: .cgSessionEventTap)

    logDaemon("posted right-option tap")
}

func doubleTapRightOption() {
    tapRightOptionOnce()
    let tapIntervalUs = useconds_t(daemonOptionTapInterval * 1_000_000)
    usleep(tapIntervalUs)
    tapRightOptionOnce()
}

func simulateFnDown() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let flags = CGEventFlags.maskSecondaryFn
    let down = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: true)
    down?.type = .flagsChanged
    down?.flags = flags
    down?.post(tap: .cgSessionEventTap)
    logDaemon("posted Fn down")
}

func simulateFnUp() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: .cgSessionEventTap)
    logDaemon("posted Fn up")
}
