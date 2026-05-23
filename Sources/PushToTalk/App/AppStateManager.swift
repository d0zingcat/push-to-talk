import Foundation
import AppKit
import Carbon
import SwiftUI

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
    @Published var listeningMode: String = "double_tap_option" {
        didSet {
            if listeningMode != daemonListeningMode {
                daemonListeningMode = listeningMode
                saveConfig()
            }
        }
    }

    @Published var hasPermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasInputMonitoringPermission: Bool = false
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
        self.listeningMode = daemonListeningMode
        self.restoreDelay = daemonRestoreDelay
        self.settleDelay = daemonSettleDelay
        self.optionTapInterval = daemonOptionTapInterval
        self.optionPressDelay = daemonOptionPressDelay
        self.hasAccessibilityPermission = checkAccessibilityPermission(prompt: false)
        self.hasInputMonitoringPermission = checkInputMonitoringPermission(prompt: false)
        self.hasPermission = self.hasAccessibilityPermission && self.hasInputMonitoringPermission
        self.availableIMEs = getAvailableInputSources()
        
        let plistURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.pushtotalk.gui.plist")
        self.launchAtLogin = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func refreshPermissionState() {
        let accessibility = checkAccessibilityPermission(prompt: false)
        let inputMonitoring = checkInputMonitoringPermission(prompt: false)
        let perm = accessibility && inputMonitoring
        if accessibility != self.hasAccessibilityPermission ||
            inputMonitoring != self.hasInputMonitoringPermission ||
            perm != self.hasPermission {
            DispatchQueue.main.async {
                self.hasAccessibilityPermission = accessibility
                self.hasInputMonitoringPermission = inputMonitoring
                self.hasPermission = perm
            }
        }
    }

    func getAvailableInputSources() -> [String] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        var names = Set<String>()
        let allowed = ["微信输入法", "豆包输入法", "typeless"]
        for src in list {
            if let name = getInputSourceName(src) {
                if allowed.contains(name) {
                    names.insert(name)
                }
            }
        }
        var result = Array(names)
        for item in allowed {
            if !result.contains(item) {
                result.append(item)
            }
        }
        return result.sorted()
    }

    func requestPermission() {
        if !hasAccessibilityPermission {
            _ = checkAccessibilityPermission(prompt: true)
        }
        if !hasInputMonitoringPermission {
            _ = checkInputMonitoringPermission(prompt: true)
        }
        refreshPermissionState()
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
        self.listeningMode = "double_tap_option"
    }

    func saveConfig() {
        var cfg = AppConfig()
        cfg.targetIME = targetIME
        cfg.listeningMode = listeningMode
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
