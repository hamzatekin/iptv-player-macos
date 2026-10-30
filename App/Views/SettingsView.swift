import IPTVCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.userAgentKey) private var userAgent = AppSettings.defaultUserAgent

    var body: some View {
        Form {
            Section {
                TextField("User agent", text: $userAgent)
                    .autocorrectionDisabled()
                HStack {
                    Text("The provider ignores requests from user agents it doesn't know.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to default") { userAgent = AppSettings.defaultUserAgent }
                        .disabled(userAgent == AppSettings.defaultUserAgent)
                }
            } header: {
                Text("Connection")
            }

            AccountSection()
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: userAgent) { model.userAgentChanged() }
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @State private var result: Result<AccountInfo, Error>?

    var body: some View {
        Section {
            if let credentials = model.credentials {
                LabeledContent("Server", value: credentials.server.absoluteString)
                LabeledContent("Username", value: credentials.username)
                switch result {
                case .success(let info):
                    LabeledContent("Status", value: info.status.capitalized)
                    LabeledContent("Expires", value: info.expiresAt?.formatted(date: .long, time: .omitted) ?? "Never")
                    LabeledContent("Connections", value: "\(info.activeConnections) / \(info.maxConnections)")
                case .failure(let error):
                    Text(AppModel.message(for: error)).foregroundStyle(.red)
                case nil:
                    LabeledContent("Status") { ProgressView().controlSize(.small) }
                }
                HStack {
                    Button("Refresh Channels") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                    Spacer()
                    Button("Sign Out", role: .destructive) { model.signOut() }
                }
            } else {
                Text("Not signed in").foregroundStyle(.secondary)
            }
        } header: {
            Text("Account")
        }
        .task(id: model.credentials) { await load() }
    }

    private func load() async {
        result = nil
        guard model.credentials != nil else { return }
        do {
            result = .success(try await model.loadAccountInfo())
        } catch {
            result = .failure(error)
        }
    }
}
