import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch model.phase {
            case .login: LoginView()
            case .loading: LoadingView()
            case .ready: MainView()
            }
        }
        .background(WindowAccessor { model.window.attach($0) })
        .alert("Another device is watching.", isPresented: busyAlertShown) {
            Button("Watch here") { model.confirmPendingPlay() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Watch here anyway?")
        }
        .onAppear {
            AppDelegate.openMainWindow = { openWindow(id: AppDelegate.mainWindowID) }
            model.start()
        }
    }

    private var busyAlertShown: Binding<Bool> {
        Binding(
            get: { model.pendingPlay != nil },
            set: { if !$0 { model.pendingPlay = nil } }
        )
    }
}

/// Shown after sign in until the first catalog arrives, or when that first load failed.
struct LoadingView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAccount = false

    var body: some View {
        VStack(spacing: 14) {
            if let error = model.loadError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Couldn't load the channels")
                    .font(.headline)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                HStack {
                    Button("Retry") { Task { await model.refresh() } }
                        .keyboardShortcut(.defaultAction)
                    // A typo in a just-edited login lands here; fix it without retyping everything.
                    Button("Edit Login…") { showsAccount = true }
                    Button("Sign Out", role: .destructive) { model.signOut() }
                }
            } else {
                ProgressView()
                Text("Loading channels…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showsAccount) {
            AccountSheet().environment(model)
        }
    }
}
