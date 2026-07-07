//
//  AuthManager.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation
import Combine

/// Manages authentication state and handles login/logout operations.
final class AuthManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var userID: String?
    
    // MARK: - Dependencies
    private let backend: any Backend
    private let keychainStore: KeychainStore
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(backend: any Backend, keychainStore: KeychainStore = KeychainStore()) {
        self.backend = backend
        self.keychainStore = keychainStore
        self.isLoggedIn = keychainStore.isLoggedIn
        self.userID = keychainStore.userID
        
        // Sync with backend authentication state
        if let _ = keychainStore.accessToken {
            // We have a token, but we should verify it's still valid with the backend
            // For now, we'll trust the keychain, but in a real app you might want to validate
        }
    }
    
    // MARK: - Public Methods
    
    /// Logs in with the provided credentials.
    /// - Parameters:
    ///   - credentials: Dictionary containing username/email and password
    func login(credentials: [String: String]) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await backend.login(credentials: credentials)
                if success {
                    // In a real implementation, the backend would return tokens
                    // For now, we'll simulate receiving tokens from the login response
                    // This would typically come from the backend response
                    let accessToken = "mock_access_token_\(UUID().uuidString)"
                    let refreshToken = "mock_refresh_token_\(UUID().uuidString)"
                    let userID = "user_\(UUID().uuidString)"
                    
                    keychainStore.accessToken = accessToken
                    keychainStore.refreshToken = refreshToken
                    keychainStore.userID = userID
                    
                    await MainActor.run {
                        self.isLoggedIn = true
                        self.userID = userID
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Invalid credentials"
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Logs out the current user and clears authentication data.
    func logout() {
        isLoading = true
        
        Task {
            do {
                try await backend.logout()
            } catch {
                // Even if logout fails on the server, we still clear local data
                print("Logout error: \(error)")
            }
            
            keychainStore.clear()
            
            await MainActor.run {
                self.isLoggedIn = false
                self.userID = nil
                self.isLoading = false
                self.errorMessage = nil
            }
        }
    }
    
    /// Refreshes the access token using the refresh token.
    func refreshToken() {
        guard let refreshToken = keychainStore.refreshToken else {
            // No refresh token, force logout
            logout()
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // In a real implementation, we'd call a refresh token endpoint
                // For now, we'll simulate by generating new tokens
                let accessToken = "mock_access_token_\(UUID().uuidString)"
                let userID = keychainStore.userID ?? "user_\(UUID().uuidString)"
                
                keychainStore.accessToken = accessToken
                // Keep the same refresh token (in a real app, you might rotate this)
                
                await MainActor.run {
                    self.isLoggedIn = true
                    self.userID = userID
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to refresh token: \(error.localizedDescription)"
                    self.isLoading = false
                    // If refresh fails, log out
                    logout()
                }
            }
        }
    }
    
    /// Checks if the user is currently authenticated by verifying with the backend.
    func checkAuthStatus() {
        isLoading = true
        
        Task {
            do {
                let isAuthenticated = backend.isAuthenticated
                await MainActor.run {
                    self.isLoggedIn = isAuthenticated
                    self.isLoading = false
                    
                    if !isAuthenticated {
                        // If backend says not authenticated, clear local state
                        keychainStore.clear()
                        self.userID = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to check auth status: \(error.localizedDescription)"
                    self.isLoading = false
                    // On error, assume not authenticated for safety
                    self.isLoggedIn = false
                    self.userID = nil
                }
            }
        }
    }
    
    /// Gets the current access token from keychain.
    func getAccessToken() -> String? {
        return keychainStore.accessToken
    }
    
    /// Gets the current refresh token from keychain.
    func getRefreshToken() -> String? {
        return keychainStore.refreshToken
    }
}