import Foundation
import Combine

class ProxyManager: ObservableObject {
    static let shared = ProxyManager()

    @Published var isRunning = false
    @Published var port: Int = 8080
    @Published var targetUrl: String = "http://192.168.1.50:8000"
    @Published var logs: [String] = []

    private var process: Process?
    private var outputPipe: Pipe?

    private let userDefaults = UserDefaults.standard
    private let kTargetUrlKey = "ClaudeSwitch_ProxyTargetUrl"
    private let kPortKey = "ClaudeSwitch_ProxyPort"
    private let kTargetModelKey = "ClaudeSwitch_ProxyTargetModel"

    @Published var targetModel: String = ""

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cfgPath = "\(home)/.claude_proxy_config.json"
        var loadedFromConfig = false
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cfgPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let tu = json["target_url"] as? String, !tu.isEmpty {
                self.targetUrl = tu
                loadedFromConfig = true
            }
            if let tm = json["target_model"] as? String, !tm.isEmpty {
                self.targetModel = tm
            }
            if let p = json["port"] as? Int, p > 0 {
                self.port = p
            }
        }

        if !loadedFromConfig {
            self.targetUrl = userDefaults.string(forKey: kTargetUrlKey) ?? "http://209.46.123.170:20128/v1"
            let savedPort = userDefaults.integer(forKey: kPortKey)
            self.port = savedPort > 0 ? savedPort : 8080
            let savedModel = userDefaults.string(forKey: kTargetModelKey)
            if let m = savedModel, !m.isEmpty {
                self.targetModel = m
            } else {
                self.targetModel = "high-availability"
            }
        }

        syncConfigFile()
        ensureLaunchAgentInstalled()

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.checkIfAlreadyRunning()
        }
    }

    func syncConfigFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cfgPath = "\(home)/.claude_proxy_config.json"
        let dict: [String: Any] = [
            "port": self.port,
            "target_url": self.targetUrl,
            "target_model": self.targetModel
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: cfgPath))
        }
    }

    func ensureLaunchAgentInstalled() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plistDir = "\(home)/Library/LaunchAgents"
        let plistPath = "\(plistDir)/com.anthropic.claude.proxy.plist"

        let pythonBin = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/python3") ? "/opt/homebrew/bin/python3" : "/usr/bin/python3"
        let scriptPath = "/Applications/ClaudeSwitch.app/Contents/Resources/proxy_daemon.py"

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.anthropic.claude.proxy</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(pythonBin)</string>
                <string>\(scriptPath)</string>
                <string>--port</string>
                <string>\(port)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(home)/Library/Logs/claude_proxy.log</string>
            <key>StandardErrorPath</key>
            <string>\(home)/Library/Logs/claude_proxy.err</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        try? FileManager.default.createDirectory(atPath: plistDir, withIntermediateDirectories: true)
        try? plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // Bootstrap or kickstart launchd job in background
        DispatchQueue.global(qos: .background).async {
            let kick = Process()
            kick.launchPath = "/bin/launchctl"
            let uid = getuid()
            kick.arguments = ["kickstart", "-k", "gui/\(uid)/com.anthropic.claude.proxy"]
            try? kick.run()
            kick.waitUntilExit()

            if kick.terminationStatus != 0 {
                let boot = Process()
                boot.launchPath = "/bin/launchctl"
                boot.arguments = ["bootstrap", "gui/\(uid)", plistPath]
                try? boot.run()
                boot.waitUntilExit()
            }
        }
    }

    func checkIfAlreadyRunning() {
        let task = Process()
        task.launchPath = "/usr/bin/lsof"
        task.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !out.isEmpty {
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.logs.append("ℹ️ Port \(self.port) is currently in use (proxy or server active).")
                }
            }
        } catch {
            // Ignore
        }
    }

    func startProxy(target: String, localPort: Int, targetModel: String = "") {
        stopProxy()

        self.targetUrl = target
        self.port = localPort
        self.targetModel = targetModel

        userDefaults.set(target, forKey: kTargetUrlKey)
        userDefaults.set(localPort, forKey: kPortKey)
        userDefaults.set(targetModel, forKey: kTargetModelKey)

        syncConfigFile()
        ensureLaunchAgentInstalled()

        let scriptPath: String
        if let bundlePath = Bundle.main.path(forResource: "proxy_daemon", ofType: "py") {
            scriptPath = bundlePath
        } else {
            // Fallback for development / running outside bundle
            let cwd = FileManager.default.currentDirectoryPath
            let devPath = "\(cwd)/ClaudeSwitchSource/Resources/proxy_daemon.py"
            scriptPath = FileManager.default.fileExists(atPath: devPath) ? devPath : "proxy_daemon.py"
        }

        var procArgs = [scriptPath, "--port", String(localPort), "--target", target]
        if !targetModel.isEmpty {
            procArgs.append(contentsOf: ["--target-model", targetModel])
        }

        let proc = Process()
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/python3") {
            proc.launchPath = "/opt/homebrew/bin/python3"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/python3") {
            proc.launchPath = "/usr/local/bin/python3"
        } else {
            proc.launchPath = "/usr/bin/python3"
        }
        proc.arguments = procArgs

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe
        self.process = proc

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    let lines = str.components(separatedBy: "\n").filter { !$0.isEmpty }
                    self?.logs.append(contentsOf: lines)
                    if (self?.logs.count ?? 0) > 300 {
                        self?.logs.removeFirst(100)
                    }
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.logs.append("⏹ Proxy stopped.")
            }
        }

        do {
            try proc.run()
            self.isRunning = true
            self.logs.append("🚀 Proxy started on http://127.0.0.1:\(localPort) -> \(target)")
        } catch {
            self.logs.append("❌ Failed to start proxy: \(error.localizedDescription)")
            self.isRunning = false
        }
    }

    func stopProxy() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            process = nil
        }
        // Also kill any orphan on that port if needed
        let killTask = Process()
        killTask.launchPath = "/bin/bash"
        killTask.arguments = ["-c", "lsof -ti :\(port) | xargs kill -9 2>/dev/null || true"]
        try? killTask.run()
        killTask.waitUntilExit()

        self.isRunning = false
    }

    deinit {
        stopProxy()
    }
}
