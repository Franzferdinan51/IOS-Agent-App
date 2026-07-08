import SwiftUI

@main
struct DualAgentApp: App {
    @StateObject private var appState = AppState()

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
                .environment(\.brand, appState.authManager.currentBackendType.brand)
                .preferredColorScheme(nil) // honor system dark/light; the palette adapts automatically
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