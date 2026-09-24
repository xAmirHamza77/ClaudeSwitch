import SwiftUI

struct ProxyView: View {
    @ObservedObject var state: AppState
    @ObservedObject var proxyManager = ProxyManager.shared
    @State private var targetInput: String = ""
    @State private var portInput: String = "8080"
    @State private var targetModelInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Info Card
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("HTTP-to-HTTPS Bypass (Loopback Forwarder)")
                        .font(.headline)
                    Text("Claude Desktop strictly forbids plain HTTP URLs across external networks ('must use https or http on loopback') and rejects non-Anthropic wire model names. This local proxy listens on 127.0.0.1, rewrites the model name, and forwards all traffic seamlessly to your custom upstream gateway.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            // Configuration Form
            GroupBox(label: Label("Forwarder Settings", systemImage: "arrow.triangle.swap")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Remote / LAN HTTP URL").font(.caption).foregroundColor(.secondary)
                            TextField("http://192.168.1.50:8000 or https://your-gateway.com", text: $targetInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(proxyManager.isRunning)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local Port").font(.caption).foregroundColor(.secondary)
                            TextField("8080", text: $portInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .disabled(proxyManager.isRunning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Target Model Translation").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("Translates incoming 'claude-3-7-sonnet' to your gateway's model name").font(.caption2).foregroundColor(.blue)
                        }
                        TextField("e.g. antigravity/claude-sonnet-4-6 (Leave blank for 1:1 forwarding)", text: $targetModelInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(proxyManager.isRunning)

                        HStack(spacing: 6) {
                            Text("Fast Presets:").font(.caption2).foregroundColor(.secondary)
                            Button("⚡ Claude Sonnet (1.4s)") {
                                targetModelInput = "antigravity/claude-sonnet-4-6"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(proxyManager.isRunning)

                            Button("🚀 Claude No-Think (1.2s)") {
                                targetModelInput = "no-think/antigravity/claude-sonnet-4-6"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(proxyManager.isRunning)

                            Button("🔥 Gemini 2.5 Flash (1.2s)") {
                                targetModelInput = "antigravity/gemini-2.5-flash"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(proxyManager.isRunning)

                            Button("🐢 Gemini 3.6 (14s)") {
                                targetModelInput = "high-availability"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(proxyManager.isRunning)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            if proxyManager.isRunning {
                                proxyManager.stopProxy()
                            } else {
                                let port = Int(portInput) ?? 8080
                                proxyManager.startProxy(target: targetInput, localPort: port, targetModel: targetModelInput)
                            }
                        }) {
                            HStack {
                                Image(systemName: proxyManager.isRunning ? "stop.fill" : "play.fill")
                                Text(proxyManager.isRunning ? "Stop Loopback Proxy" : "Start Loopback Proxy")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(proxyManager.isRunning ? .red : .green)

                        if proxyManager.isRunning {
                            Button("Apply to Current Profile (http://127.0.0.1:\(proxyManager.port))") {
                                state.baseUrl = "http://127.0.0.1:\(proxyManager.port)"
                                state.wireModel = "claude-3-7-sonnet"
                                if !targetModelInput.isEmpty {
                                    state.displayLabel = targetModelInput
                                }
                                state.selectedTab = 0
                                state.showBanner("Gateway Base URL set to local proxy (127.0.0.1:\(proxyManager.port))!", status: .success)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(8)
            }
            .onAppear {
                self.targetInput = proxyManager.targetUrl
                self.portInput = String(proxyManager.port)
                self.targetModelInput = proxyManager.targetModel
            }

            // Status Indicator
            HStack {
                Circle()
                    .fill(proxyManager.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                if proxyManager.isRunning {
                    Text("Proxy is ACTIVE: Listening on http://127.0.0.1:\(proxyManager.port) ➔ Forwarding to \(proxyManager.targetUrl)")
                        .font(.callout)
                        .foregroundColor(.green)
                } else {
                    Text("Proxy is STOPPED.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Live Logs
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Traffic & Server Logs").font(.caption).bold()
                    Spacer()
                    Button("Clear Logs") {
                        proxyManager.logs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            if proxyManager.logs.isEmpty {
                                Text("No logs yet. Start proxy to observe forwarded requests.")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(Array(proxyManager.logs.enumerated()), id: \.offset) { idx, log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.white)
                                        .id(idx)
                                }
                                .padding(8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .frame(height: 180)
                    .onChange(of: proxyManager.logs.count) { _, _ in
                        if let lastIdx = proxyManager.logs.indices.last {
                            proxy.scrollTo(lastIdx, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}
