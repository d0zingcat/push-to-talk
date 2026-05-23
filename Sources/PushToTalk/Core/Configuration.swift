import Foundation

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
    var listeningMode: String?

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
        case listeningMode = "listening_mode"
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
