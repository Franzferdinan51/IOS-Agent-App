import SwiftUI

@main
struct DualAgentApp: App {
    var body: some Scene {
        WindowGroup {
            // For now, we'll show the onboarding view.
            // In the future, we'll check if we are authenticated and show the session list.
            OnboardingView()
        }
    }
}