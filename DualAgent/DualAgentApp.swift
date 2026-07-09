import SwiftUI
import UIKit

@main
struct DualAgentApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appSettings = AppSettings.shared
    @StateObject private var connectionState = ConnectionState()
    @StateObject private var approvalInbox = ApprovalInboxCoordinator()

    init() {
        // Prime the haptic engines once at launch so the first tap fires
        // instantly instead of carrying the ~30ms first-fire latency.
        Haptic.prepareAll()

        // Pin the tab bar to a fully-opaque system-background appearance
        // so scroll content underneath it doesn't ghost through the
        // translucent surface. Mirrors what `iOS 26 SwiftUI TabView` does
        // implicitly, but our SDK is 18.x so we set it manually.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor.systemBackground
        tabAppearance.shadowColor = UIColor.separator.withAlphaComponent(0.30)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.authManager)
                .environmentObject(appSettings)
                .environmentObject(connectionState)
                .environmentObject(approvalInbox)
                .environment(\.brand, appState.authManager.currentBackendType.brand)
                .preferredColorScheme(appSettings.colorScheme)
                .tint(appSettings.effectiveAccent.color)
                .task {
                    connectionState.bind(appState.authManager)
                    approvalInbox.bind(appState.authManager)
                    // Direct input-pipeline smoke. Off by default; opt in with
                    // `-DADirectChatSmoke` / `DA_DIRECT_OPENCLAW_CHAT_SMOKE=1`.
                    DirectOpenClawChatSmoke.runIfRequested(authManager: appState.authManager)
                    // Debug backend switch — runs before routing so it can
                    // switch to OpenClaw before the user sees the UI.
                    print("DEBUG: About to call switchBackendIfRequested")
                    await switchBackendIfRequested()
                    print("DEBUG: switchBackendIfRequested returned")
                }
        }
    }
}

// MARK: - Debug Backend Switch

/// If `DA_BACKEND` env/arg requests a different backend, switch + re-auth.
/// Runs at the App level so it fires regardless of whether OnboardingView
/// or MainTabView is currently displayed.
@MainActor
func switchBackendIfRequested() async {
    #if DEBUG
    print("DEBUG: switchBackendIfRequested() called")
    let env = ProcessInfo.processInfo.environment
    let args = ProcessInfo.processInfo.arguments
    func value(forKey key: String) -> String? {
        if let v = env[key], !v.isEmpty { return v }
        if let i = args.firstIndex(of: key), i + 1 < args.count {
            return args[i + 1]
        }
        return nil
    }
    print("DEBUG: Checking for DA_BACKEND...")
    guard let requested = value(forKey: "-DABackend") ?? value(forKey: "DA_BACKEND") else {
        print("DEBUG: No DA_BACKEND requested")
        return
    }
    print("DEBUG: Requested backend = \(requested)")
    let wantsOpenClaw = requested.lowercased() == "openclaw"

    guard wantsOpenClaw, AuthManager.shared.currentBackendType != .openclaw else {
        print("DEBUG: Not switching - wantsOpenClaw=\(wantsOpenClaw), current=\(AuthManager.shared.currentBackendType)")
        return
    }
    print("DUALAGENT_BACKEND_SWITCH switching to openclaw")

    let url = value(forKey: "-DAServerURL") ?? value(forKey: "DA_SERVER_URL") ?? "http://127.0.0.1:18790"
    let credential = value(forKey: "-DACredential") ?? value(forKey: "DA_CREDENTIAL") ?? ""

    AuthManager.shared.switchBackend(to: .openclaw)
    do {
        let ok = try await AuthManager.shared.connect(serverURL: url, credential: credential)
        print("DUALAGENT_BACKEND_SWITCH result=\(ok)")
    } catch {
        print("DUALAGENT_BACKEND_SWITCH failed: \(error.localizedDescription)")
    }
    #endif
}

// Map BackendType → Theme.Brand
extension BackendType {
    var brand: Theme.Brand {
        switch self {
        case .hermes: return .hermes
        case .openclaw: return .openclaw
        }
    }
}