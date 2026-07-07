import Foundation

/// Central configuration for the app.
struct AppConfig {
    /// The name of the app, used for display and UserDefaults keys.
    static let appName = "DualAgent"
    
    /// Default timeout for network requests (in seconds).
    static let requestTimeout: TimeInterval = 30
    
    /// Maximum number of recent messages to cache per session.
    static let maxCachedMessagesPerSession = 500
    
    /// Whether to use the legacy JSON format for certain OpenClaw endpoints (if applicable).
    static let useLegacyJsonFormat = false
    
    /// Feature flags
    struct Features {
        /// Enable voice input via speech recognition.
        static let voiceInputEnabled = true
        /// Enable experimental features (e.g., file editing).
        static let experimentalEnabled = false
        /// Enable push notifications (future).
        static let pushNotificationsEnabled = false
    }
}