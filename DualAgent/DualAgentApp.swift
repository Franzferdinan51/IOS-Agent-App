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
                }
        }
    }
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