import SwiftUI

@main
struct DualAgentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
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