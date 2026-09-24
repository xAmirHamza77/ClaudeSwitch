import SwiftUI

struct ProfilesView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Section 1: Configured Profiles
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Configured Profiles")
                            .font(.headline)
                        Spacer()
                        Button(action: { state.refreshAll() }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }

                    if state.profiles.isEmpty {
                        Text("No profiles found in configLibrary.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(state.profiles) { entry in
                            ProfileCard(entry: entry, state: state)
                        }
                    }
                }

                Divider()

                // Section 2: Configuration Backups
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Configuration Backups")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            do {
                                let dir = try ConfigManager.shared.createBackup()
                                state.refreshAll()
                                state.showBanner("Created backup in \(dir)!", status: .success)
                            } catch {
                                state.showBanner("Backup failed: \(error.localizedDescription)", status: .error)
                            }
                        }) {
                            Label("Backup Now", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if state.backups.isEmpty {
                        Text("No backups found in ~/.claude_desktop_backups.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(state.backups) { item in
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline).bold()
                                    Text("\(item.date) • \(item.sizeDesc)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    state.restoreBackup(item: item)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ProfileCard: View {
    let entry: ProfileEntry
    @ObservedObject var state: AppState

    var isActive: Bool {
        state.activeProfileId == entry.id
    }

    var config: ProfileConfig? {
        ConfigManager.shared.loadProfile(id: entry.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .gray)
                .font(.title3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name)
                        .font(.headline)
                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                if let cfg = config {
                    Text("Gateway: \(cfg.inferenceGatewayBaseUrl)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let model = cfg.inferenceModels?.first {
                        Text("Model: \(model.labelOverride ?? model.name) (Wire: \(model.name))")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Edit") {
                    state.editProfile(id: entry.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !isActive {
                    Button("Switch & Relaunch") {
                        state.activateProfile(id: entry.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(8)
    }
}
