import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}

func indexRange(_ text: String, _ pattern: String, from start: String.Index? = nil) -> Range<String.Index>? {
    text.range(of: pattern, range: (start ?? text.startIndex)..<text.endIndex)
}

let source = try String(contentsOfFile: "swift-helper/main.swift", encoding: .utf8)

let delayPattern = #"let DAEMON_RESTORE_DELAY:\s*TimeInterval\s*=\s*([0-9.]+)"#
let delayRegex = try NSRegularExpression(pattern: delayPattern)
let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
guard let delayMatch = delayRegex.firstMatch(in: source, range: sourceRange),
      let valueRange = Range(delayMatch.range(at: 1), in: source),
      let restoreDelay = Double(source[valueRange]) else {
    fputs("DAEMON_RESTORE_DELAY constant is missing\n", stderr)
    exit(1)
}

require(restoreDelay >= 3, "DAEMON_RESTORE_DELAY should be at least 3 seconds")
require(source.contains("DAEMON_RIGHT_CMD_FLAG_RAW"), "right-command device flag constant is missing")
require(source.contains("DAEMON_RIGHT_OPTION_FLAG_RAW"), "right-option device flag constant is missing")
require(source.contains("daemonIgnoreRightCmdDownUntil"), "right-command release debounce state is missing")
require(source.contains("DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL"), "right-command release debounce interval is missing")
require(source.contains("daemonActivationItem"), "daemon should defer activation so short right-command taps do not switch IMEs")
require(source.contains("daemonVoiceSessionIsActive"), "daemon should track whether a voice session actually started")
require(source.contains("DAEMON_TAP_DISABLE_WINDOW"), "daemon should define an event tap disable fuse window")
require(source.contains("DAEMON_TAP_DISABLE_MAX_COUNT"), "daemon should define an event tap disable fuse threshold")
require(source.contains("exit(70)"), "daemon should exit after repeated event tap disable events")

guard let tapStart = indexRange(source, "func tapRightOptionOnce()"),
      let doubleTapStart = indexRange(source, "func doubleTapRightOption()", from: tapStart.upperBound) else {
    fputs("tapRightOptionOnce function not found\n", stderr)
    exit(1)
}

let tapBody = String(source[tapStart.lowerBound..<doubleTapStart.lowerBound])
require(
    tapBody.contains("CGEventFlags.maskAlternate.rawValue | DAEMON_RIGHT_OPTION_FLAG_RAW"),
    "right-option tap should post a plain right-option down event"
)
require(tapBody.contains("up?.flags = []"), "right-option release should post a plain modifier release event")
require(!tapBody.contains("currentRawFlags"), "right-option tap should not include held command flags")

guard let releaseStart = indexRange(source, "func daemonOnRightCmdUp()"),
      let callbackStart = indexRange(source, "func daemonEventCallback", from: releaseStart.upperBound) else {
    fputs("daemonOnRightCmdUp function not found\n", stderr)
    exit(1)
}

let releaseBody = String(source[releaseStart.lowerBound..<callbackStart.lowerBound])
guard let firstTap = releaseBody.range(of: "tapRightOptionOnce()"),
      let secondTap = releaseBody.range(of: "tapRightOptionOnce()", range: firstTap.upperBound..<releaseBody.endIndex),
      let restoreSchedule = releaseBody.range(of: "DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_RESTORE_DELAY"),
      let suppressSchedule = releaseBody.range(of: "daemonIgnoreRightCmdDownUntil = Date().addingTimeInterval(DAEMON_RIGHT_CMD_RELEASE_SUPPRESS_INTERVAL)") else {
    fputs("release flow is missing tap, restore, or suppress scheduling\n", stderr)
    exit(1)
}

require(firstTap.lowerBound < secondTap.lowerBound, "release taps should be ordered")
require(secondTap.lowerBound < restoreSchedule.lowerBound, "input-source restore should be scheduled after the stop double tap")
require(suppressSchedule.lowerBound < restoreSchedule.lowerBound, "release should suppress false right-command down events before restore")

guard let callbackEnd = indexRange(source, "// MARK: - CLI Argument Parsers", from: callbackStart.upperBound) else {
    fputs("daemonEventCallback end marker not found\n", stderr)
    exit(1)
}

let callbackBody = String(source[callbackStart.lowerBound..<callbackEnd.lowerBound])
require(
    callbackBody.contains("type == .tapDisabledByTimeout") &&
        callbackBody.contains("type == .tapDisabledByUserInput") &&
        callbackBody.contains("daemonHandleTapDisabled(type)") &&
        source.contains("CGEvent.tapEnable(tap: tap, enable: true)"),
    "event tap callback should re-enable itself after disable events"
)
require(
    callbackBody.contains("event.flags.rawValue & DAEMON_RIGHT_CMD_FLAG_RAW"),
    "right-command callback should read the physical right-command flag from the event"
)
require(
    callbackBody.contains("Date() < daemonIgnoreRightCmdDownUntil"),
    "right-command callback should ignore down events inside the release debounce window"
)
require(
    !callbackBody.contains("if daemonRightCmdIsDown {\n        daemonOnRightCmdUp()"),
    "right-command callback must not toggle state blindly"
)
require(
    callbackBody.contains("DispatchQueue.main.async") &&
        !callbackBody.contains("daemonOnRightCmdDown()\n    } else") &&
        !callbackBody.contains("daemonOnRightCmdUp()\n    }"),
    "right-command handling should be dispatched asynchronously out of the event tap callback"
)
require(callbackBody.contains("return Unmanaged.passUnretained(event)"), "right-command events should pass through in listen-only mode")
require(source.contains("options: .listenOnly"), "event tap should be listen-only so it cannot block or consume system input")

let downStart = indexRange(source, "func daemonOnRightCmdDown()")!
let upStart = indexRange(source, "func daemonOnRightCmdUp()", from: downStart.upperBound)!
let downBody = String(source[downStart.lowerBound..<upStart.lowerBound])
require(
    downBody.contains("DispatchWorkItem") &&
        downBody.contains("DAEMON_OPTION_PRESS_DELAY") &&
        downBody.contains("daemonActivateVoiceSession()"),
    "right-command down should schedule delayed activation instead of switching IMEs immediately"
)

let installScript = try String(contentsOfFile: "install-daemon.sh", encoding: .utf8)
require(installScript.contains("<key>ThrottleInterval</key>"), "LaunchAgent should throttle restarts")
require(installScript.contains("<integer>30</integer>"), "LaunchAgent restart throttle should be 30 seconds")

print("daemon release flow is correct")
