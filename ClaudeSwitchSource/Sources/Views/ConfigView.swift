import SwiftUI

struct ConfigView: View {
    @ObservedObject var state: AppState
    @ObservedObject var proxyManager = ProxyManager.shared
    @State private var showApiKey: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Preset Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configuration Preset")
                        .font(.headline)
                    Picker("Preset", selection: $state.selectedPreset) {
                        ForEach(PresetKind.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: state.selectedPreset) { _, newPreset in
                        state.applyPreset(newPreset)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)

                // Warning Banner for Remote HTTP URLs
                if state.isRemoteHttpUrl {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Blocks External HTTP Endpoints")
                                .font(.subheadline).bold()
                            Text("Claude Desktop strictly requires HTTPS for non-loopback hosts. To connect to an HTTP server on LAN/remote, route it through our built-in Loopback Proxy on 127.0.0.1.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Route via Local Proxy (http://127.0.0.1:8080)") {
                                let targetM = (state.displayLabel == "high-availability" || state.wireModel == "high-availability") ? "high-availability" : (state.wireModel != "claude-3-7-sonnet" ? state.wireModel : proxyManager.targetModel)
                                proxyManager.startProxy(target: state.baseUrl, localPort: 8080, targetModel: targetM.isEmpty ? "high-availability" : targetM)
                                state.baseUrl = "http://127.0.0.1:8080"
                                state.wireModel = "claude-3-7-sonnet"
                                state.showBanner("Proxy active! Base URL redirected to http://127.0.0.1:8080", status: .success)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                    .cornerRadius(8)
                }

                // Gateway & Credentials
                GroupBox(label: Label("Gateway Connection", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile Name").font(.caption).foregroundColor(.secondary)
                            TextField("e.g. DeepSeek Flash (Modal)", text: $state.profileName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Gateway Base URL").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("Do NOT include /v1 at the end").font(.caption2).foregroundColor(.secondary)
                            }
                            TextField("https://...", text: $state.baseUrl)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key / Bearer Token").font(.caption).foregroundColor(.secondary)
                            HStack {
                                if showApiKey {
                                    TextField("Enter API Key or Token...", text: $state.apiKey)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                } else {
                                    SecureField("Enter API Key or Token...", text: $state.apiKey)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                Button(action: { showApiKey.toggle() }) {
                                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Authentication Header Scheme").font(.caption).foregroundColor(.secondary)
                            Picker("", selection: $state.authScheme) {
                                Text("Authorization: Bearer <key> (Modal / Standard)").tag("bearer")
                                Text("x-api-key: <key> (Anthropic Gateway)").tag("x-api-key")
                            }
                            .pickerStyle(RadioGroupPickerStyle())
                        }
                    }
                    .padding(8)
                }

                // Model Routing & Bypass Settings
                GroupBox(label: Label("Model Routing & Validation Bypass", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Wire Model ID (Passed to Claude Client)").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("Must match an Anthropic name to bypass validation").font(.caption2).foregroundColor(.blue)
                            }
                            TextField("claude-3-7-sonnet", text: $state.wireModel)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Display Model Label (Visible in Claude UI)").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Text("This is the model name you will see in Claude").font(.caption2).foregroundColor(.green)
                            }
                            TextField("deepseek-v4-1-flash", text: $state.displayLabel)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        Toggle("Enable Model Auto-Discovery", isOn: $state.modelDiscoveryEnabled)
                            .font(.subheadline)
                        Text("Keep disabled for DeepSeek/custom models to prevent Claude from probing /v1/models and rejecting non-Anthropic model IDs.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Test Connection Status Box
                if let result = state.testResult {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: state.testStatus == .success ? "checkmark.circle.fill" : (state.testStatus == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                            .foregroundColor(state.testStatus == .success ? .green : (state.testStatus == .warning ? .orange : .red))
                        Text(result)
                            .font(.callout)
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Bottom Buttons
                HStack(spacing: 14) {
                    Button(action: {
                        state.testConnection()
                    }) {
                        HStack {
                            if state.isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isTesting)

                    Spacer()

                    Button("Save Profile Only") {
                        state.saveCurrentProfile(andRestart: false)
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        state.saveCurrentProfile(andRestart: true)
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Apply & Restart Claude")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }
}
