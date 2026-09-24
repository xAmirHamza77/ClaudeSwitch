import Foundation
import Combine
import SwiftUI

enum StatusKind {
    case idle
    case success
    case warning
    case error
}

enum PresetKind: String, CaseIterable, Identifiable {
    case modalDeepSeek = "DeepSeek V4.1 Flash (Modal)"
    case localOllama = "Local Ollama (HTTP Loopback)"
    case localVllm = "Local vLLM / LiteLLM (HTTP Loopback)"
    case claudeSwitch = "Claude Switch (AgentRouter)"
    case custom = "Custom Endpoint"

    var id: String { self.rawValue }
}

class AppState: ObservableObject {
    @Published var selectedTab: Int = 0

    // MARK: - Current Form State
    @Published var profileId: String = "00000000-0000-4000-8000-000000000001"
    @Published var profileName: String = "DeepSeek Flash (Modal)"
    @Published var baseUrl: String = "https://imfreak695--ep-deepseek-v4-1-flash-server.us-west.modal.direct"
    @Published var apiKey: String = ""
    @Published var authScheme: String = "bearer" // "bearer" or "x-api-key"
    @Published var wireModel: String = "claude-3-7-sonnet"
    @Published var displayLabel: String = "deepseek-v4-1-flash"
    @Published var modelDiscoveryEnabled: Bool = false
    @Published var selectedPreset: PresetKind = .modalDeepSeek

    // MARK: - Status & Testing
    @Published var isTesting: Bool = false
    @Published var testResult: String?
    @Published var testStatus: StatusKind = .idle
    @Published var bannerMessage: String?
    @Published var bannerStatus: StatusKind = .idle

    // MARK: - App Status
    @Published var isClaudeRunning: Bool = false
    @Published var activeProfileId: String?
    @Published var profiles: [ProfileEntry] = []
    @Published var backups: [BackupItem] = []

    private var statusTimer: AnyCancellable?

    init() {
        refreshAll()
        statusTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClaudeStatus()
            }
    }

    func checkClaudeStatus() {
        self.isClaudeRunning = ConfigManager.shared.isClaudeRunning()
    }

    func refreshAll() {
        checkClaudeStatus()
        let meta = ConfigManager.shared.loadMeta()
        self.activeProfileId = meta?.appliedId
        self.profiles = meta?.entries ?? []
        self.backups = ConfigManager.shared.listBackups()

        // Load active profile into form if available
        if let activeId = self.activeProfileId,
           let cfg = ConfigManager.shared.loadProfile(id: activeId) {
            self.profileId = activeId
            if let entry = self.profiles.first(where: { $0.id == activeId }) {
                self.profileName = entry.name
            }
            self.baseUrl = cfg.inferenceGatewayBaseUrl
            self.apiKey = cfg.inferenceGatewayApiKey ?? ""
            self.authScheme = cfg.inferenceGatewayAuthScheme ?? "bearer"
            self.modelDiscoveryEnabled = cfg.modelDiscoveryEnabled ?? false

            if let firstModel = cfg.inferenceModels?.first {
                self.wireModel = firstModel.name
                self.displayLabel = firstModel.labelOverride ?? firstModel.name
            }
        }
    }

    func applyPreset(_ preset: PresetKind) {
        self.selectedPreset = preset
        switch preset {
        case .modalDeepSeek:
            self.profileId = "00000000-0000-4000-8000-000000000001"
            self.profileName = "DeepSeek Flash (Modal)"
            self.baseUrl = "https://imfreak695--ep-deepseek-v4-1-flash-server.us-west.modal.direct"
            self.apiKey = ""
            self.authScheme = "bearer"
            self.wireModel = "claude-3-7-sonnet"
            self.displayLabel = "deepseek-v4-1-flash"
            self.modelDiscoveryEnabled = false

        case .localOllama:
            self.profileId = UUID().uuidString.lowercased()
            self.profileName = "Local Ollama (DeepSeek R1)"
            self.baseUrl = "http://127.0.0.1:11434"
            self.apiKey = ""
            self.authScheme = "bearer"
            self.wireModel = "claude-3-7-sonnet"
            self.displayLabel = "deepseek-r1"
            self.modelDiscoveryEnabled = false

        case .localVllm:
            self.profileId = UUID().uuidString.lowercased()
            self.profileName = "Local vLLM / LiteLLM"
            self.baseUrl = "http://127.0.0.1:8000"
            self.apiKey = ""
            self.authScheme = "bearer"
            self.wireModel = "claude-3-7-sonnet"
            self.displayLabel = "deepseek-v4-1-flash"
            self.modelDiscoveryEnabled = false

        case .claudeSwitch:
            self.profileId = "00000000-0000-4000-8000-000000157210"
            self.profileName = "Claude Switch"
            self.baseUrl = "https://agentrouter.org/"
            self.apiKey = ""
            self.authScheme = "bearer"
            self.wireModel = "claude-opus-5"
            self.displayLabel = "claude-opus-5"
            self.modelDiscoveryEnabled = false

        case .custom:
            self.profileId = UUID().uuidString.lowercased()
            self.profileName = "Custom Gateway"
            self.modelDiscoveryEnabled = false
        }
    }

    var isRemoteHttpUrl: Bool {
        guard let url = URL(string: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        if url.scheme?.lowercased() == "http" {
            let host = url.host?.lowercased() ?? ""
            return host != "localhost" && host != "127.0.0.1" && host != "[::1]"
        }
        return false
    }

    func buildProfileConfig() -> ProfileConfig {
        var cleanUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clean trailing slash
        while cleanUrl.hasSuffix("/") {
            cleanUrl.removeLast()
        }
        // Remove trailing /v1 if user accidentally typed it
        if cleanUrl.hasSuffix("/v1") {
            cleanUrl = String(cleanUrl.dropLast(3))
        }

        return ProfileConfig(
            inferenceGatewayBaseUrl: cleanUrl,
            inferenceGatewayApiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            inferenceGatewayAuthScheme: authScheme,
            modelDiscoveryEnabled: modelDiscoveryEnabled,
            modelPrefer1mContext: false,
            inferenceModels: [
                InferenceModel(
                    name: wireModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    labelOverride: displayLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                    supports1m: false
                )
            ],
            defaultModelEffort: "max",
            coworkEgressAllowedHosts: ["*"],
            disableDeploymentModeChooser: true,
            inferenceProvider: "gateway",
            inferenceCredentialKind: "static"
        )
    }

    func saveCurrentProfile(andRestart restart: Bool = false) {
        do {
            let cleanId = profileId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.profileId = cleanId
            let config = buildProfileConfig()
            try ConfigManager.shared.saveProfile(
                id: cleanId,
                name: profileName,
                config: config,
                setAsActive: true
            )

            // If profile points to loopback proxy port 8080 and proxy is not running, ensure it starts
            if config.inferenceGatewayBaseUrl.contains("127.0.0.1:8080") || config.inferenceGatewayBaseUrl.contains("localhost:8080") {
                if !ProxyManager.shared.isRunning {
                    let targetM = ProxyManager.shared.targetModel.isEmpty ? "high-availability" : ProxyManager.shared.targetModel
                    ProxyManager.shared.startProxy(target: ProxyManager.shared.targetUrl, localPort: 8080, targetModel: targetM)
                }
            }

            refreshAll()

            if restart {
                ConfigManager.shared.restartClaude()
                showBanner("Profile applied! Relaunching Claude Desktop...", status: .success)
            } else {
                showBanner("Profile saved successfully as active!", status: .success)
            }
        } catch {
            showBanner("Failed to save profile: \(error.localizedDescription)", status: .error)
        }
    }

    func activateProfile(id: String) {
        do {
            let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try ConfigManager.shared.setActiveProfile(id: cleanId)

            if let cfg = ConfigManager.shared.loadProfile(id: cleanId) {
                if cfg.inferenceGatewayBaseUrl.contains("127.0.0.1:8080") || cfg.inferenceGatewayBaseUrl.contains("localhost:8080") {
                    if !ProxyManager.shared.isRunning {
                        let targetM = ProxyManager.shared.targetModel.isEmpty ? "high-availability" : ProxyManager.shared.targetModel
                        ProxyManager.shared.startProxy(target: ProxyManager.shared.targetUrl, localPort: 8080, targetModel: targetM)
                    }
                }
            }

            refreshAll()
            ConfigManager.shared.restartClaude()
            showBanner("Activated profile! Claude Desktop restarted.", status: .success)
        } catch {
            showBanner("Failed to activate: \(error.localizedDescription)", status: .error)
        }
    }

    func editProfile(id: String) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let cfg = ConfigManager.shared.loadProfile(id: cleanId) else { return }
        self.profileId = cleanId
        if let entry = self.profiles.first(where: { $0.id.lowercased() == cleanId }) {
            self.profileName = entry.name
        }
        self.baseUrl = cfg.inferenceGatewayBaseUrl
        self.apiKey = cfg.inferenceGatewayApiKey ?? ""
        self.authScheme = cfg.inferenceGatewayAuthScheme ?? "bearer"
        self.modelDiscoveryEnabled = cfg.modelDiscoveryEnabled ?? false

        if let firstModel = cfg.inferenceModels?.first {
            self.wireModel = firstModel.name
            self.displayLabel = firstModel.labelOverride ?? firstModel.name
        }
        self.selectedTab = 0
        showBanner("Loaded '\(self.profileName)' into editor.", status: .idle)
    }

    func restoreBackup(item: BackupItem) {
        do {
            try ConfigManager.shared.restoreBackup(path: item.path)
            refreshAll()
            ConfigManager.shared.restartClaude()
            showBanner("Restored from \(item.name) and restarted Claude!", status: .success)
        } catch {
            showBanner("Restore failed: \(error.localizedDescription)", status: .error)
        }
    }

    func showBanner(_ msg: String, status: StatusKind) {
        self.bannerMessage = msg
        self.bannerStatus = status
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            if self?.bannerMessage == msg {
                self?.bannerMessage = nil
            }
        }
    }

    // MARK: - Test Connection
    func testConnection() {
        guard URL(string: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            testResult = "❌ Invalid Gateway Base URL format."
            testStatus = .error
            return
        }

        isTesting = true
        testResult = nil
        testStatus = .idle

        var endpoint = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while endpoint.hasSuffix("/") { endpoint.removeLast() }
        if endpoint.hasSuffix("/v1") { endpoint = String(endpoint.dropLast(3)) }
        guard let requestUrl = URL(string: "\(endpoint)/v1/messages") else {
            isTesting = false
            testResult = "❌ Failed to construct /v1/messages test URL."
            testStatus = .error
            return
        }

        var req = URLRequest(url: requestUrl)
        req.httpMethod = "POST"
        req.timeoutInterval = 12.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if authScheme == "bearer" {
            req.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue(cleanKey, forHTTPHeaderField: "x-api-key")
        }

        let bodyPayload: [String: Any] = [
            "model": wireModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": 5,
            "messages": [
                ["role": "user", "content": "ping"]
            ]
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)

        let startTime = Date()

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isTesting = false
                let latency = Int(Date().timeIntervalSince(startTime) * 1000)

                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain && error.code == NSURLErrorServerCertificateUntrusted {
                        self?.testResult = "❌ SSL Handshake Error. For non-HTTPS local servers, use our Loopback Proxy on 127.0.0.1!"
                    } else if error.domain == NSURLErrorDomain && error.code == NSURLErrorCannotConnectToHost {
                        self?.testResult = "❌ Connection refused. Ensure the server or tunnel is running at \(requestUrl.host ?? "")."
                    } else {
                        self?.testResult = "❌ Connection failed: \(error.localizedDescription)"
                    }
                    self?.testStatus = .error
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    self?.testResult = "❌ No HTTP response received."
                    self?.testStatus = .error
                    return
                }

                if http.statusCode == 200 {
                    var modelName = self?.displayLabel ?? ""
                    if let d = data,
                       let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let m = json["model"] as? String {
                        modelName = m
                    }
                    self?.testResult = "✅ Connected successfully! (HTTP 200, \(latency)ms) Backend Model: \(modelName)"
                    self?.testStatus = .success
                } else if http.statusCode == 429 {
                    self?.testResult = "⚠️ Reached endpoint, but rate limit / quota exceeded (HTTP 429: usage limit reached). Check your Modal credits."
                    self?.testStatus = .warning
                } else if http.statusCode == 401 {
                    self?.testResult = "❌ Authentication failed (HTTP 401). Verify your API key and Auth Scheme."
                    self?.testStatus = .error
                } else if http.statusCode == 404 {
                    self?.testResult = "⚠️ HTTP 404 Not Found. Make sure Gateway Base URL does not end with /v1."
                    self?.testStatus = .warning
                } else {
                    let bodyPreview = data != nil ? String(data: data!, encoding: .utf8)?.prefix(100) ?? "" : ""
                    self?.testResult = "HTTP \(http.statusCode) response: \(bodyPreview)"
                    self?.testStatus = .warning
                }
            }
        }.resume()
    }
}
