import AppKit
import SwiftUI

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
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening Mode")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $state.listeningMode) {
                        Text("Double-tap Option").tag("double_tap_option")
                        Text("Long-press Fn").tag("long_press_fn")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity)
                }
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
                            if !state.hasAccessibilityPermission {
                                Text("Accessibility Permission Required")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Grant access to let PushToTalk simulate the voice trigger.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            if !state.hasInputMonitoringPermission {
                                Text("Input Monitoring Permission Required")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Grant access to let PushToTalk listen for Right Command.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            if state.hasAccessibilityPermission && state.hasInputMonitoringPermission {
                                Text("Permission Required")
                                .font(.system(size: 11, weight: .bold))
                                Text("Grant access to enable push-to-talk.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            }
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
