// AppState.swift
// DualAgent iOS App

import SwiftUI

/// Global application state shared across all views.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Dependencies

    /// The shared authentication manager.
    @Published var authManager: AuthManager

    /// The currently selected backend type.
    @Published var selectedBackendType: BackendType = .hermes

    // MARK: - Navigation State

    /// The currently selected tab in the main tab bar.
    @Published var selectedTab: Tab = .sessions

    /// The active session, if any.
    @Published var activeSession: UnifiedSession?

    // MARK: - Initialization

    init() {
        // Use the shared AuthManager so the same instance the UI talks to
        // (via OnboardingViewModel.connect → AuthManager.shared) is the one
        // RootView observes. Otherwise successful logins never reach the
        // navigation state and the user is stuck on the onboarding screen.
        self.authManager = .shared
    }

    // MARK: - Tab Enum

    enum Tab: Int, CaseIterable {
        case sessions
        case skills
        case memory
        case crons
        case settings

        var title: String {
            switch self {
            case .sessions: return "Sessions"
            case .skills: return "Skills"
            case .memory: return "Memory"
            case .crons: return "Crons"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .sessions: return "bubble.left.and.bubble.right"
            case .skills: return "star"
            case .memory: return "brain"
            case .crons: return "clock"
            case .settings: return "gear"
            }
        }
    }
}
