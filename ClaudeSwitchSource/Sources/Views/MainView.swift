import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 14) {
                if let logoPath = Bundle.main.path(forResource: "logo", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: logoPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "asterisk.circle.fill")
                        .font(.title)
                        .foregroundColor(Color(red: 217/255, green: 119/255, blue: 87/255))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("ClaudeSwitch")
                        .font(.title3).bold()
                    Text("Claude Desktop Model Switcher & Gateway Suite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Claude status pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isClaudeRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(state.isClaudeRunning ? "Claude Active (3P)" : "Claude Inactive")
                        .font(.caption2).bold()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.isClaudeRunning ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                .cornerRadius(12)

                Button(action: {
                    ConfigManager.shared.restartClaude()
                    state.showBanner("Relaunching Claude Desktop...", status: .success)
                }) {
                    Label("Restart Claude", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Segmented Picker
            Picker("", selection: $state.selectedTab) {
                Text("Model Configuration").tag(0)
                Text("HTTP Bypass Proxy").tag(1)
                Text("Profiles & Backups").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // Banner Notification
            if let msg = state.bannerMessage {
                HStack {
                    Image(systemName: state.bannerStatus == .success ? "checkmark.circle.fill" : (state.bannerStatus == .error ? "xmark.octagon.fill" : "info.circle.fill"))
                        .foregroundColor(state.bannerStatus == .success ? .green : (state.bannerStatus == .error ? .red : .blue))
                    Text(msg)
                        .font(.callout)
                    Spacer()
                }
                .padding(10)
                .background(state.bannerStatus == .success ? Color.green.opacity(0.15) : (state.bannerStatus == .error ? Color.red.opacity(0.15) : Color.blue.opacity(0.15)))
                .transition(.slide)
            }

            // Tab View Contents
            Group {
                switch state.selectedTab {
                case 0:
                    ConfigView(state: state)
                case 1:
                    ProxyView(state: state)
                case 2:
                    ProfilesView(state: state)
                default:
                    ConfigView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 640)
    }
}
