// RootView.swift
// DualAgent iOS App

import SwiftUI

/// The root view that handles routing between onboarding and the main tab interface.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var brand: Theme.Brand {
        appState.authManager.currentBackendType.brand
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
                if forceMainTabsForDebug || appState.authManager.isLoggedIn {
                    MainTabView()
                } else {
                    OnboardingView()
                        .environmentObject(appState.authManager)
                }
            }
        }
        .environment(\.brand, brand)
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}