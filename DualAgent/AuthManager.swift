import Foundation
import SwiftUI
import LocalAuthentication

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var isBiometricEnabled = false
    
    private let keychain = KeychainHelper.standard
    private let serverURLKey = "dualagent_server_url"
    private let authMethodKey = "dualagent_auth_method"
    private let usernameKey = "dualagent_username"
    private let passwordKey = "dualagent_password"
    private let apiKeyKey = "dualagent_api_key"
    private let biometricEnabledKey = "dualagent_biometric_enabled"
    
    private init() {
        // Check if we have saved credentials and attempt silent login
        if let serverURL = keychain.read(serverURLKey),
           let authMethodString = keychain.read(authMethodKey),
           let authMethod = AuthMethod(rawValue: authMethodString) {
            
            switch authMethod {
            case .password:
                if let username = keychain.read(usernameKey),
                   let password = keychain.read(passwordKey) {
                    login(serverURL: serverURL, authMethod: authMethod, 
                          credentials: ["username": username, "password": password]) { _, _ in }
                }
            case .apiKey:
                if let apiKey = keychain.read(apiKeyKey) {
                    login(serverURL: serverURL, authMethod: authMethod, 
                          credentials: ["api_key": apiKey]) { _, _ in }
                }
            }
        }
        
        // Check if biometric authentication is enabled
        isBiometricEnabled = keychain.read(biometricEnabledKey) == "true"
    }
    
    func login(serverURL: String, authMethod: AuthMethod, credentials: [String: String], completion: @escaping (Bool, Error?) -> Void) {
        // In a real app, you would make a network request here to validate credentials
        // For this example, we'll simulate a network call
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Simulate successful login for demo purposes
            // In a real app, you would validate credentials against your server
            let success = true // Assume success for demo
            let error: Error? = nil
            
            if success {
                // Save credentials securely
                self.keychain.save(serverURL, forKey: self.serverURLKey)
                self.keychain.save(authMethod.rawValue, forKey: self.authMethodKey)
                
                switch authMethod {
                case .password:
                    self.keychain.save(credentials["username"] ?? "", forKey: self.usernameKey)
                    self.keychain.save(credentials["password"] ?? "", forKey: self.passwordKey)
                case .apiKey:
                    self.keychain.save(credentials["api_key"] ?? "", forKey: self.apiKeyKey)
                }
                
                self.isAuthenticated = true
                completion(true, nil)
            } else {
                completion(false, error)
            }
        }
    }
    
    func logout() {
        // Clear credentials from keychain
        keychain.delete(serverURLKey)
        keychain.delete(authMethodKey)
        keychain.delete(usernameKey)
        keychain.delete(passwordKey)
        keychain.delete(apiKeyKey)
        keychain.delete(biometricEnabledKey)
        
        isAuthenticated = false
    }
    
    func enableBiometricAuth(_ enabled: Bool) {
        keychain.save(enabled ? "true" : "false", forKey: biometricEnabledKey)
        isBiometricEnabled = enabled
    }
    
    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func authenticateWithBiometrics(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access DualAgent") { success, evalError in
            DispatchQueue.main.async {
                completion(success, evalError)
            }
        }
    }
    
    func getStoredServerURL() -> String? {
        return keychain.read(serverURLKey)
    }
    
    func getStoredAuthMethod() -> AuthMethod? {
        guard let authMethodString = keychain.read(authMethodKey) else { return nil }
        return AuthMethod(rawValue: authMethodString)
    }
    
    func getStoredCredentials() -> [String: String]? {
        guard let authMethod = getStoredAuthMethod() else { return nil }
        
        switch authMethod {
        case .password:
            guard let username = keychain.read(usernameKey),
                  let password = keychain.read(passwordKey) else { return nil }
            return ["username": username, "password": password]
        case .apiKey:
            guard let apiKey = keychain.read(apiKeyKey) else { return nil }
            return ["api_key": apiKey]
        }
    }
}

// MARK: - Keychain Helper
final class KeychainHelper {
    static let standard = KeychainHelper()
    
    private init() {}
    
    func save(_ string: String, forKey key: String) {
        let data = Data(string.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == noErr {
            let data = dataTypeRef as! Data
            return String(data: data, encoding: .utf8)
        } else {
            return nil
        }
    }
    
    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Auth Method Enum
enum AuthMethod: String, CaseIterable, CaseIterable {
    case password = "Password"
    case apiKey = "API Key"
}