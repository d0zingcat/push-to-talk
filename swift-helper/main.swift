import Foundation
import Carbon
import CoreGraphics
import AppKit
import SwiftUI

func logDaemon(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date())
    let line = "[\(timestamp)] \(message)"
    print(line)
    fflush(stdout)
    
    // Also append to state manager if GUI is running
    DispatchQueue.main.async {
        if NSApplication.shared.delegate != nil {
            AppStateManager.shared.logs.append(line)
            if AppStateManager.shared.logs.count > 100 {
                AppStateManager.shared.logs.removeFirst()
            }
        }
    }
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

// MARK: - Daemon State（全局，供 CGEventTap callback 使用）

struct AppConfig: Codable {
    var targetIME: String?
    var triggerKeycode: UInt16?
    var simulateKeycode: UInt16?
    var restoreDelay: TimeInterval?
    var settleDelay: TimeInterval?
    var optionTapInterval: TimeInterval?
    var optionPressDelay: TimeInterval?
    var triggerFlagRaw: UInt64?
    var simulateFlagRaw: UInt64?

    enum CodingKeys: String, CodingKey {
        case targetIME = "target_ime"
        case triggerKeycode = "trigger_keycode"
        case simulateKeycode = "simulate_keycode"
        case restoreDelay = "restore_delay"
        case settleDelay = "settle_delay"
        case optionTapInterval = "option_tap_interval"
        case optionPressDelay = "option_press_delay"
        case triggerFlagRaw = "trigger_flag_raw"
        case simulateFlagRaw = "simulate_flag_raw"
    }
}

func loadConfig() -> AppConfig {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let configURL = home.appendingPathComponent(".config/pushtotalk/config.json")
    do {
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        let cfg = try decoder.decode(AppConfig.self, from: data)
        logDaemon("loaded custom configuration from \(configURL.path)")
        return cfg
    } catch CocoaError.fileReadNoSuchFile {
        return AppConfig()
    } catch {
        logDaemon("warning: failed to parse config at \(configURL.path): \(error). Using defaults.")
        return AppConfig()
    }
}

let loadedConfig = loadConfig()

var daemonTargetIME = loadedConfig.targetIME ?? "豆包输入法"
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
        logDaemon("starting right-option double tap, current='\(getCurrentInputSourceName() ?? "")'")
        tapRightOptionOnce()
        DispatchQueue.main.asyncAfter(deadline: .now() + DAEMON_OPTION_TAP_INTERVAL) {
            guard daemonRightCmdIsDown, daemonVoiceSessionIsActive else { return }
            tapRightOptionOnce()
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

if args.count < 2 {
    logDaemon("Starting Push-to-Talk Menu Bar GUI...")
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}

switch args[1] {

case "daemon":
    // Push-to-Talk 守护进程：按住右 Command 说话，松开停止，3 秒后恢复输入法
    daemonTargetIME = parseTarget(from: args)

    if !hasAccessibilityPermission(prompt: false) {
        fputs("Error: daemon requires Accessibility permission to post right Option events.\nGrant access to ~/.local/bin/pushtotalk in System Settings → Privacy & Security → Accessibility, then run ./restart-daemon.sh.\n", stderr)
        exit(3)
    }

    let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
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
    usleep(UInt32(DAEMON_INPUT_SOURCE_SETTLE_DELAY * 1_000_000))
    requireAccessibilityPermission(prompt: true)
    doubleTapRightOption()
    usleep(delayMs * 1000)
    if !previous.isEmpty { _ = selectInputSource(named: previous) }

case "check-permission":
    requireAccessibilityPermission(prompt: true)
    print("accessibility permission granted")

case "list-sources":
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    var names = Set<String>()
    for src in list {
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            names.insert(name)
        }
    }
    for name in names.sorted() {
        print(name)
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

// ==========================================
// MARK: - GUI Implementation
// ==========================================

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ConfigSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced))
                    .bold()
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

struct MainMenuView: View {
    @ObservedObject var state = AppStateManager.shared
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Push to Talk")
                        .font(.system(size: 15, weight: .bold))
                    
                    if state.voiceSessionIsActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording Voice...")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    } else if state.isEnabled {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Ready (Hold Right Cmd)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 8, height: 8)
                            Text("Stopped")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: $state.isEnabled)
                    .toggleStyle(SwitchToggleStyle())
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            // Core controls
            VStack(alignment: .leading, spacing: 6) {
                Text("Target Input Method")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $state.targetIME) {
                    ForEach(state.availableIMEs, id: \.self) { ime in
                        Text(ime).tag(ime)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            
            // Permission Alert
            if !state.hasPermission {
                VStack(spacing: 8) {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility Permission Required")
                                .font(.system(size: 11, weight: .bold))
                            Text("To simulate Right Option key and switch input methods, please grant permission.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Button(action: { state.requestPermission() }) {
                            Text("Request")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { state.openSettings() }) {
                            Text("Open Settings")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.1))
                                .foregroundColor(.primary)
                                .cornerRadius(4)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .padding(.horizontal)
            }
            
            // Advanced Settings Disclosure Group
            DisclosureGroup(
                isExpanded: $showSettings,
                content: {
                    VStack(spacing: 10) {
                        ConfigSlider(
                            label: "Restore Delay",
                            value: $state.restoreDelay,
                            range: 0.5...10.0,
                            format: "%.1fs"
                        )
                        ConfigSlider(
                            label: "Settle Delay",
                            value: $state.settleDelay,
                            range: 0.1...1.5,
                            format: "%.2fs"
                        )
                        ConfigSlider(
                            label: "Option Tap Interval",
                            value: $state.optionTapInterval,
                            range: 0.05...0.5,
                            format: "%.2fs"
                        )
                        ConfigSlider(
                            label: "Option Press Delay",
                            value: $state.optionPressDelay,
                            range: 0.1...1.5,
                            format: "%.2fs"
                        )
                        
                        Button("Restore Defaults") {
                            state.restoreDefaults()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 6)
                },
                label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text("Advanced Parameters")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            )
            .padding(.horizontal)
            
            Divider()
            
            // Live Logs
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Live Activity Logs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Directory") {
                        state.openLogsDirectory()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 9))
                    .foregroundColor(.accentColor)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(state.logs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 70)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Footer
            HStack {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
                    .font(.system(size: 10))
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .background(VisualEffectView().ignoresSafeArea())
    }
}

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    @Published var isEnabled: Bool = true {
        didSet {
            updateEventTapState()
        }
    }
    @Published var targetIME: String = "" {
        didSet {
            if targetIME != daemonTargetIME {
                daemonTargetIME = targetIME
                saveConfig()
            }
        }
    }
    @Published var restoreDelay: Double = 3.0 {
        didSet {
            if restoreDelay != daemonRestoreDelay {
                daemonRestoreDelay = restoreDelay
                saveConfig()
            }
        }
    }
    @Published var settleDelay: Double = 0.3 {
        didSet {
            if settleDelay != daemonSettleDelay {
                daemonSettleDelay = settleDelay
                saveConfig()
            }
        }
    }
    @Published var optionTapInterval: Double = 0.18 {
        didSet {
            if optionTapInterval != daemonOptionTapInterval {
                daemonOptionTapInterval = optionTapInterval
                saveConfig()
            }
        }
    }
    @Published var optionPressDelay: Double = 0.3 {
        didSet {
            if optionPressDelay != daemonOptionPressDelay {
                daemonOptionPressDelay = optionPressDelay
                saveConfig()
            }
        }
    }

    @Published var hasPermission: Bool = false
    @Published var voiceSessionIsActive: Bool = false
    @Published var logs: [String] = []
    @Published var availableIMEs: [String] = []
    @Published var launchAtLogin: Bool = false {
        didSet {
            setLaunchAtLogin(launchAtLogin)
        }
    }

    init() {
        self.targetIME = daemonTargetIME
        self.restoreDelay = daemonRestoreDelay
        self.settleDelay = daemonSettleDelay
        self.optionTapInterval = daemonOptionTapInterval
        self.optionPressDelay = daemonOptionPressDelay
        self.hasPermission = hasAccessibilityPermission(prompt: false)
        self.availableIMEs = getAvailableInputSources()
        
        let plistURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.pushtotalk.gui.plist")
        self.launchAtLogin = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func refreshPermissionState() {
        let perm = hasAccessibilityPermission(prompt: false)
        if perm != self.hasPermission {
            DispatchQueue.main.async {
                self.hasPermission = perm
            }
        }
    }

    func getAvailableInputSources() -> [String] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        var names = Set<String>()
        for src in list {
            if let name = getInputSourceName(src) {
                names.insert(name)
            }
        }
        return names.sorted()
    }

    func requestPermission() {
        _ = hasAccessibilityPermission(prompt: true)
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openLogsDirectory() {
        let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/pushtotalk")
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logDir.path)
    }

    func restoreDefaults() {
        self.restoreDelay = 3.0
        self.settleDelay = 0.3
        self.optionTapInterval = 0.18
        self.optionPressDelay = 0.3
    }

    func saveConfig() {
        var cfg = AppConfig()
        cfg.targetIME = targetIME
        cfg.restoreDelay = restoreDelay
        cfg.settleDelay = settleDelay
        cfg.optionTapInterval = optionTapInterval
        cfg.optionPressDelay = optionPressDelay
        cfg.triggerKeycode = daemonTriggerKeycode
        cfg.simulateKeycode = daemonSimulateKeycode
        cfg.triggerFlagRaw = daemonTriggerFlagRaw
        cfg.simulateFlagRaw = daemonSimulateFlagRaw

        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".config/pushtotalk/config.json")
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cfg)
            try data.write(to: configURL)
        } catch {
            logDaemon("error saving config: \(error)")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.pushtotalk.gui.plist")
        if enabled {
            let appPath = Bundle.main.bundlePath
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.pushtotalk.gui</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)/Contents/MacOS/PushToTalk</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    func updateEventTapState() {
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            if isEnabled {
                delegate.enableEventTap()
            } else {
                delegate.disableEventTap()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Push to Talk") {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.title = "🎙️"
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Build popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainMenuView())
        self.popover = popover

        // Load config and update state
        AppStateManager.shared.refreshPermissionState()
        
        if AppStateManager.shared.isEnabled {
            enableEventTap()
        }

        // Start timer to check permission state when window is active or periodically
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            AppStateManager.shared.refreshPermissionState()
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if let popover = popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func enableEventTap() {
        if daemonEventTap != nil { return }
        
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: daemonEventCallback,
            userInfo: nil
        ) else {
            logDaemon("Error: failed to create CGEventTap. Accessibility permission missing?")
            DispatchQueue.main.async {
                AppStateManager.shared.isEnabled = false
                AppStateManager.shared.hasPermission = false
            }
            return
        }
        daemonEventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logDaemon("Event tap enabled in GUI mode.")
        
        DispatchQueue.main.async {
            AppStateManager.shared.hasPermission = true
        }
    }

    func disableEventTap() {
        guard let tap = daemonEventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        daemonEventTap = nil
        logDaemon("Event tap disabled in GUI mode.")
    }
}
