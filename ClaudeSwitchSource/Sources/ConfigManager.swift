import Foundation
import AppKit

struct ProfileEntry: Codable, Identifiable, Hashable {
    let id: String
    var name: String
}

struct MetaConfig: Codable {
    var appliedId: String
    var entries: [ProfileEntry]
}

struct InferenceModel: Codable {
    var name: String
    var labelOverride: String?
    var supports1m: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case labelOverride
        case supports1m
    }
}

struct ProfileConfig: Codable {
    var inferenceGatewayBaseUrl: String
    var inferenceGatewayApiKey: String?
    var inferenceGatewayAuthScheme: String?
    var modelDiscoveryEnabled: Bool?
    var modelPrefer1mContext: Bool?
    var inferenceModels: [InferenceModel]?
    var defaultModelEffort: String?
    var coworkEgressAllowedHosts: [String]?
    var disableDeploymentModeChooser: Bool?
    var inferenceProvider: String?
    var inferenceCredentialKind: String?

    static func defaultDeepSeek() -> ProfileConfig {
        return ProfileConfig(
            inferenceGatewayBaseUrl: "https://imfreak695--ep-deepseek-v4-1-flash-server.us-west.modal.direct",
            inferenceGatewayApiKey: "",
            inferenceGatewayAuthScheme: "bearer",
            modelDiscoveryEnabled: false,
            modelPrefer1mContext: false,
            inferenceModels: [
                InferenceModel(name: "claude-3-7-sonnet", labelOverride: "deepseek-v4-1-flash", supports1m: false)
            ],
            defaultModelEffort: "max",
            coworkEgressAllowedHosts: ["*"],
            disableDeploymentModeChooser: true,
            inferenceProvider: "gateway",
            inferenceCredentialKind: "static"
        )
    }
}

struct BackupItem: Identifiable {
    let id: String
    let name: String
    let date: String
    let path: String
    let sizeDesc: String
}

class ConfigManager {
    static let shared = ConfigManager()

    var homeDir: String {
        return NSHomeDirectory()
    }

    var claudeDir: String {
        return "\(homeDir)/Library/Application Support/Claude"
    }

    var claude3pDir: String {
        return "\(homeDir)/Library/Application Support/Claude-3p"
    }

    var backupRootDir: String {
        return "\(homeDir)/.claude_desktop_backups"
    }

    private let fileManager = FileManager.default

    // MARK: - Backups
    func createBackup() throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupDir = "\(backupRootDir)/backup_\(timestamp)"

        try fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)

        let targetDirs = [("Claude", claudeDir), ("Claude-3p", claude3pDir)]
        for (name, dirPath) in targetDirs {
            let dest = "\(backupDir)/\(name)"
            if fileManager.fileExists(atPath: dirPath) {
                try fileManager.createDirectory(atPath: dest, withIntermediateDirectories: true)
                let cfgFile = "\(dirPath)/claude_desktop_config.json"
                if fileManager.fileExists(atPath: cfgFile) {
                    try? fileManager.copyItem(atPath: cfgFile, toPath: "\(dest)/claude_desktop_config.json")
                }
                let libDir = "\(dirPath)/configLibrary"
                if fileManager.fileExists(atPath: libDir) {
                    try? fileManager.copyItem(atPath: libDir, toPath: "\(dest)/configLibrary")
                }
            }
        }
        return backupDir
    }

    func listBackups() -> [BackupItem] {
        guard let items = try? fileManager.contentsOfDirectory(atPath: backupRootDir) else { return [] }
        var result: [BackupItem] = []

        for item in items where item.hasPrefix("backup_") {
            let path = "\(backupRootDir)/\(item)"
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                let attrs = try? fileManager.attributesOfItem(atPath: path)
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .short

                let subitems = (try? fileManager.subpathsOfDirectory(atPath: path)) ?? []
                result.append(BackupItem(
                    id: item,
                    name: item,
                    date: df.string(from: modDate),
                    path: path,
                    sizeDesc: "\(subitems.count) files"
                ))
            }
        }
        return result.sorted { $0.id > $1.id }
    }

    func restoreBackup(path: String) throws {
        let targets = [("Claude", claudeDir), ("Claude-3p", claude3pDir)]
        for (name, dirPath) in targets {
            let source = "\(path)/\(name)"
            if fileManager.fileExists(atPath: source) {
                try fileManager.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
                let cfgSource = "\(source)/claude_desktop_config.json"
                if fileManager.fileExists(atPath: cfgSource) {
                    let cfgDest = "\(dirPath)/claude_desktop_config.json"
                    try? fileManager.removeItem(atPath: cfgDest)
                    try fileManager.copyItem(atPath: cfgSource, toPath: cfgDest)
                }
                let libSource = "\(source)/configLibrary"
                if fileManager.fileExists(atPath: libSource) {
                    let libDest = "\(dirPath)/configLibrary"
                    try? fileManager.removeItem(atPath: libDest)
                    try fileManager.copyItem(atPath: libSource, toPath: libDest)
                }
            }
        }
    }

    // MARK: - Profiles & Meta
    init() {
        normalizeExistingConfigFiles()
    }

    func normalizeExistingConfigFiles() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        for baseDir in [claudeDir, claude3pDir] {
            let configLib = "\(baseDir)/configLibrary"
            guard let files = try? fileManager.contentsOfDirectory(atPath: configLib) else { continue }
            for file in files where file.hasSuffix(".json") && file != "_meta.json" {
                let lower = file.lowercased()
                if file != lower {
                    let oldPath = "\(configLib)/\(file)"
                    let newPath = "\(configLib)/\(lower)"
                    try? fileManager.moveItem(atPath: oldPath, toPath: newPath)
                }
            }

            if var meta = loadMeta(fromBaseDir: baseDir) {
                meta.appliedId = meta.appliedId.lowercased()
                meta.entries = meta.entries.map { ProfileEntry(id: $0.id.lowercased(), name: $0.name) }
                if let data = try? encoder.encode(meta) {
                    try? data.write(to: URL(fileURLWithPath: "\(configLib)/_meta.json"))
                }
            }
        }
    }

    func loadMeta(fromBaseDir baseDir: String? = nil) -> MetaConfig? {
        let dir = baseDir ?? claude3pDir
        let metaPath = "\(dir)/configLibrary/_meta.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)) else {
            return nil
        }
        guard var meta = try? JSONDecoder().decode(MetaConfig.self, from: data) else {
            return nil
        }
        meta.appliedId = meta.appliedId.lowercased()
        meta.entries = meta.entries.map { ProfileEntry(id: $0.id.lowercased(), name: $0.name) }
        return meta
    }

    func loadProfile(id: String, fromBaseDir baseDir: String? = nil) -> ProfileConfig? {
        let dir = baseDir ?? claude3pDir
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let profilePath = "\(dir)/configLibrary/\(cleanId).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)) else {
            return nil
        }
        return try? JSONDecoder().decode(ProfileConfig.self, from: data)
    }

    func saveProfile(
        id: String,
        name: String,
        config: ProfileConfig,
        setAsActive: Bool = true
    ) throws {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try createBackup()

        let targetDirs = [claudeDir, claude3pDir]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let configData = try encoder.encode(config)

        for baseDir in targetDirs {
            let configLib = "\(baseDir)/configLibrary"
            try fileManager.createDirectory(atPath: configLib, withIntermediateDirectories: true)

            // 1. Write Profile JSON
            let profilePath = "\(configLib)/\(cleanId).json"
            try configData.write(to: URL(fileURLWithPath: profilePath))

            // 2. Update _meta.json
            var meta = loadMeta(fromBaseDir: baseDir) ?? MetaConfig(appliedId: cleanId, entries: [])
            if setAsActive {
                meta.appliedId = cleanId
            }

            var entries = meta.entries.map { ProfileEntry(id: $0.id.lowercased(), name: $0.name) }
            if let index = entries.firstIndex(where: { $0.id == cleanId }) {
                entries[index].name = name
            } else {
                entries.insert(ProfileEntry(id: cleanId, name: name), at: 0)
            }
            meta.entries = entries

            let metaData = try encoder.encode(meta)
            let metaPath = "\(configLib)/_meta.json"
            try metaData.write(to: URL(fileURLWithPath: metaPath))

            // 3. Ensure claude_desktop_config.json sets deploymentMode = 3p
            let desktopCfgPath = "\(baseDir)/claude_desktop_config.json"
            var cfgDict: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: URL(fileURLWithPath: desktopCfgPath)),
               let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                cfgDict = json
            }
            cfgDict["deploymentMode"] = "3p"
            if let outData = try? JSONSerialization.data(withJSONObject: cfgDict, options: [.prettyPrinted, .sortedKeys]) {
                try? outData.write(to: URL(fileURLWithPath: desktopCfgPath))
            }
        }
    }

    func setActiveProfile(id: String) throws {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try createBackup()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        for baseDir in [claudeDir, claude3pDir] {
            if var meta = loadMeta(fromBaseDir: baseDir) {
                meta.appliedId = cleanId
                meta.entries = meta.entries.map { ProfileEntry(id: $0.id.lowercased(), name: $0.name) }
                let metaData = try encoder.encode(meta)
                try metaData.write(to: URL(fileURLWithPath: "\(baseDir)/configLibrary/_meta.json"))
            }
        }
    }

    // MARK: - Process Management
    func isClaudeRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { app in
            app.bundleIdentifier == "com.anthropic.claudefordesktop" ||
            (app.localizedName == "Claude" && app.bundleIdentifier != Bundle.main.bundleIdentifier)
        }
    }

    func restartClaude() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-x", "Claude"]
        try? task.run()
        task.waitUntilExit()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            let openTask = Process()
            openTask.launchPath = "/usr/bin/open"
            openTask.arguments = ["-a", "Claude"]
            try? openTask.run()
        }
    }
}
