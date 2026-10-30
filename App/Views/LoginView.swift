import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !model.isSigningIn
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("IPTV Player")
                .font(.title.bold())

            Form {
                TextField("Server", text: $server, prompt: Text("http://example.com:8080"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .formStyle(.columns)
            .frame(width: 320)
            .onSubmit(submit)

            if let error = model.loginError {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
            }

            HStack(spacing: 8) {
                if model.isSigningIn { ProgressView().controlSize(.small) }
                Button("Sign In", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(40)
        .frame(minWidth: 460, minHeight: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await model.signIn(server: server, username: username, password: password) }
    }
}
