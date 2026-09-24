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
        self.targetUrl = userDefaults.string(forKey: kTargetUrlKey) ?? "http://127.0.0.1:8000"
        let savedPort = userDefaults.integer(forKey: kPortKey)
        self.port = savedPort > 0 ? savedPort : 8080
        let savedModel = userDefaults.string(forKey: kTargetModelKey)
        if let m = savedModel, !m.isEmpty && m != "high-availability" {
            self.targetModel = m
        } else {
            self.targetModel = "antigravity/claude-sonnet-4-6"
        }

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.checkIfAlreadyRunning()
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
