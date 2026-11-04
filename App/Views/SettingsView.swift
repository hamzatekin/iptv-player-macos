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
            if model.credentials != nil { AccountStatusSection() }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: userAgent) { model.userAgentChanged() }
    }
}

/// Read-only here: the account button in the main window's toolbar edits the login.
private struct AccountSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if let credentials = model.credentials {
                LabeledContent("Server", value: credentials.server.absoluteString)
                LabeledContent("Username", value: credentials.username)
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
    }
}
