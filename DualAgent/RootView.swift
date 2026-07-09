// RootView.swift
// DualAgent iOS App

import SwiftUI

/// The root view that handles routing between onboarding and the main tab interface.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var authManager = AuthManager.shared

    private var brand: Theme.Brand {
        authManager.currentBackendType.brand
    }

    private var forceMainTabsForDebug: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        return env["DA_FORCE_MAIN_TABS"] == "1" || args.contains("-DAForceMainTabs")
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            BrandBackground(brand: brand)
            Group {
                if forceMainTabsForDebug || authManager.isLoggedIn {
                    MainTabView()
                } else {
                    OnboardingView()
                        .environmentObject(authManager)
                }
            }
        }
        .environment(\.brand, brand)
        .onOpenURL { url in
            // Backend-neutral: route any `dualagent://` URL into AppState
            // intent publishers; UI views consume and clear them.
            handleOpenURL(url)
        }
    }

    private func handleOpenURL(_ url: URL) {
        switch DualAgentDeepLink.resolve(url) {
        case .newChat(let voice, let profile):
            appState.selectedTab = .sessions
            appState.pendingNewSessionRequest = NewSessionRequest(autoStartsVoice: voice, profileName: profile)
        case .openSession(let id):
            appState.selectedTab = .sessions
            appState.pendingOpenSessionID = id
        case .unknown:
            break
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}