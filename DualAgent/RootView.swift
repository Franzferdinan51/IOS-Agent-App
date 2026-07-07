// RootView.swift
// DualAgent iOS App

import SwiftUI

/// The root view that handles routing between onboarding and the main tab interface.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.authManager.isLoggedIn {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
