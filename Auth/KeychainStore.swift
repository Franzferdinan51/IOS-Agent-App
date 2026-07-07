//
//  KeychainStore.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation
import KeychainAccess

/// A wrapper around KeychainAccess for storing authentication tokens.
final class KeychainStore {
    // MARK: - Properties
    private let keychain = Keychain(service: "com.hermes.DualAgent")
    
    // MARK: - Keys
    private enum Keys {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let userID = "userID"
    }
    
    // MARK: - Public Properties
    var accessToken: String? {
        get { try? keychain.get(Keys.accessToken) }
        set {
            if let value = newValue {
                try? keychain.set(value, key: Keys.accessToken)
            } else {
                try? keychain.remove(Keys.accessToken)
            }
        }
    }
    
    var refreshToken: String? {
        get { try? keychain.get(Keys.refreshToken) }
        set {
            if let value = newValue {
                try? keychain.set(value, key: Keys.refreshToken)
            } else {
                try? keychain.remove(Keys.refreshToken)
            }
        }
    }
    
    var userID: String? {
        get { try? keychain.get(Keys.userID) }
        set {
            if let value = newValue {
                try? keychain.set(value, key: Keys.userID)
            } else {
                try? keychain.remove(Keys.userID)
            }
        }
    }
    
    // MARK: - Methods
    /// Clears all authentication data from the keychain.
    func clear() {
        try? keychain.remove(Keys.accessToken)
        try? keychain.remove(Keys.refreshToken)
        try? keychain.remove(Keys.userID)
    }
    
    /// Checks if the user is currently logged in (has an access token).
    var isLoggedIn: Bool {
        return accessToken != nil
    }
}