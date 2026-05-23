import Foundation
import CoreGraphics

let loadedConfig = loadConfig()

var daemonTargetIME = loadedConfig.targetIME ?? "豆包输入法"
var daemonListeningMode = loadedConfig.listeningMode ?? "double_tap_option"
var daemonTriggerKeycode = loadedConfig.triggerKeycode ?? 54
var daemonSimulateKeycode = loadedConfig.simulateKeycode ?? 61
var daemonRestoreDelay = loadedConfig.restoreDelay ?? 3.0
var daemonSettleDelay = loadedConfig.settleDelay ?? 0.3
var daemonOptionTapInterval = loadedConfig.optionTapInterval ?? 0.18
var daemonOptionPressDelay = loadedConfig.optionPressDelay ?? 0.30
var daemonTriggerFlagRaw = loadedConfig.triggerFlagRaw ?? 0x00000010
var daemonSimulateFlagRaw = loadedConfig.simulateFlagRaw ?? 0x00000040
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
let DAEMON_INPUT_SOURCE_SETTLE_DELAY: TimeInterval = 0.30  // 切换输入法后等待系统完成生效
let DAEMON_OPTION_TAP_INTERVAL: TimeInterval = 0.18  // 双击间隔
let DAEMON_RESTORE_DELAY: TimeInterval = 3.0          // 松开后多久恢复输入法
let DAEMON_TAP_DISABLE_WINDOW: TimeInterval = 60.0
let DAEMON_TAP_DISABLE_MAX_COUNT = 3
