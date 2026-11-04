import IPTVCore
import SwiftUI

/// Opened by the toolbar's account button: the saved login, which can be edited, and the
/// subscription's status. Saving checks the new login with the server first.
struct AccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var error: String?

    private var hasChanges: Bool {
        guard let saved = model.credentials else { return false }
        return server != saved.server.absoluteString || username != saved.username || password != saved.password
    }

    private var canSave: Bool {
        hasChanges
            && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Login") {
                    TextField("Server", text: $server, prompt: Text("http://example.com:8080"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    LabeledContent("Password") {
                        HStack(spacing: 6) {
                            Group {
                                if showsPassword {
                                    TextField("Password", text: $password).autocorrectionDisabled()
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            Button {
                                showsPassword.toggle()
                            } label: {
                                Image(systemName: showsPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(showsPassword ? "Hide password" : "Show password")
                            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                        }
                    }
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(isSaving)
                .onSubmit(save)

                AccountStatusSection()
            }
            .formStyle(.grouped)

            HStack(spacing: 8) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    model.signOut()
                }
                .disabled(isSaving)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 4)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: fill)
        // Cancel during a save: the check stops and its answer is never applied.
        .onDisappear { saveTask?.cancel() }
    }

    private func fill() {
        guard let saved = model.credentials else { return }
        server = saved.server.absoluteString
        username = saved.username
        password = saved.password
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        saveTask = Task {
            let message = await model.updateLogin(server: server, username: username, password: password)
            guard !Task.isCancelled else { return }
            isSaving = false
            if let message { error = message } else { dismiss() }
        }
    }
}

/// Status, expiry and connections, asked from the server each time it appears and after the login changes.
struct AccountStatusSection: View {
    @Environment(AppModel.self) private var model
    @State private var result: Result<AccountInfo, Error>?

    var body: some View {
        Section {
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
        } header: {
            Text("Subscription")
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
