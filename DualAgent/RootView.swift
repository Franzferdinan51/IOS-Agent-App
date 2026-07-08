// RootView.swift
// DualAgent iOS App

import SwiftUI

/// The root view that handles routing between onboarding and the main tab interface.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var brand: Theme.Brand {
        appState.authManager.currentBackendType.brand
    }

    var body: some View {
        ZStack {
            BrandBackground(brand: brand)
            Group {
                if appState.authManager.isLoggedIn {
                    MainTabView()
                } else {
                    OnboardingView()
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