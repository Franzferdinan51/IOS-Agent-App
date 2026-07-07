//
//  OnboardingViewModel.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation
import Combine

/// ViewModel for the onboarding screen handling authentication flows.
@MainActor
final class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showPassword: Bool = false
    @Published var showConfirmPassword: Bool = false
    
    // MARK: - Dependencies
    private let authManager: AuthManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(authManager: AuthManager) {
        self.authManager = authManager
        
        // Subscribe to auth state changes
        authManager.$isLoggedIn
            .sink { [weak self] isLoggedIn in
                // In a real app, we might navigate away from onboarding when logged in
                // For now, we just observe
            }
            .store(in: &cancellables)
        
        authManager.$errorMessage
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Signs in the user with email and password.
    /// - Parameters:
    ///   - email: The user's email address
    ///   - password: The user's password
    func signIn(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        // Validate input
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            isLoading = false
            return
        }
        
        // Simple email validation
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        guard emailPredicate.evaluate(with: email) else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        // Authenticate
        authManager.login(username: email, password: password)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] success in
                if success {
                    // Sign in successful - in a real app, we'd navigate to main app
                    // For now, we just update state
                    self?.errorMessage = nil
                }
            }
            .store(in: &cancellables)
    }
    
    /// Signs up a new user with email and password.
    /// - Parameters:
    ///   - email: The user's email address
    ///   - password: The user's password
    func signUp(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        // Validate input
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            isLoading = false
            return
        }
        
        // Simple email validation
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        guard emailPredicate.evaluate(with: email) else {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        // Password strength validation
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters long"
            isLoading = false
            return
        }
        
        // For now, we'll simulate sign up by treating it as sign in
        // In a real app, this would call a signup endpoint
        authManager.login(username: email, password: password)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] success in
                if success {
                    // Sign up successful
                    self?.errorMessage = nil
                }
            }
            .store(in: &cancellables)
    }
    
    /// Signs out the current user.
    func signOut() {
        authManager.logout()
    }
    
    /// Checks if the user is currently authenticated.
    func isAuthenticated() -> Bool {
        return authManager.isLoggedIn
    }
    
    /// Clears any error messages.
    func clearError() {
        errorMessage = nil
    }
}