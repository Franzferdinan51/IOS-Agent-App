import SwiftUI

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