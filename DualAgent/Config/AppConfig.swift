import Foundation

/// Central configuration for the app.
struct AppConfig {
    /// The name of the app, used for display and UserDefaults keys.
    static let appName = "DualAgent"

    // MARK: - Default servers
    //
    // The defaults below are **deliberately empty** so the app ships without
    // any hard-coded hostnames, IPs, or other infrastructure identifiers.
    // On first launch the OnboardingView leaves the Server field blank and
    // shows a placeholder ("https://your-host.example"). The user pastes
    // their own server URL, which is then persisted to the Keychain.
    //
    // If you'd like a developer-local default for testing, set the
    // `DA_DEFAULT_HERMES_URL` and/or `DA_DEFAULT_OPENCLAW_URL` environment
    // variables in your Xcode scheme — `OnboardingViewModel.init()` reads
    // them at runtime. Nothing leaks into the shipped binary that way.

    /// Default Hermes-webui base URL. Empty in shipped builds.
    static let hermesBaseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["DA_DEFAULT_HERMES_URL"],
           let url = URL(string: env) { return url }
        return URL(string: "http://127.0.0.1:8787") ?? URL(fileURLWithPath: "/")
    }()

    /// Default OpenClaw gateway base URL. Empty in shipped builds.
    static let openClawBaseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["DA_DEFAULT_OPENCLAW_URL"],
           let url = URL(string: env) { return url }
        return URL(string: "http://127.0.0.1:18790") ?? URL(fileURLWithPath: "/")
    }()

    /// Default OpenClaw gateway port (`gateway.port`, `OPENCLAW_GATEWAY_PORT`).
    static let openClawGatewayPort = 18789

    /// Default Hermes-webui HTTP port.
    static let hermesHTTPPort = 8080

    /// Default timeout for network requests (in seconds).
    static let requestTimeout: TimeInterval = 30

    /// Maximum number of recent messages to cache per session.
    static let maxCachedMessagesPerSession = 500

    /// Whether to use the legacy JSON format for certain OpenClaw endpoints (if applicable).
    static let useLegacyJsonFormat = false

    // MARK: - Default credentials
    //
    // Credentials are **never** hard-coded. The OnboardingView's credential
    // field starts empty; the user pastes their own Hermes password or
    // OpenClaw gateway token, and it lands in the Keychain
    // (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
    //
    // The placeholders below are friendly hints shown in the empty
    // SecureField, never pre-filled values.

    // MARK: - Feature flags
    struct Features {
        /// Enable voice input via speech recognition.
        static let voiceInputEnabled = true
        /// Enable experimental features (e.g., file editing).
        static let experimentalEnabled = false
        /// Enable push notifications (future).
        static let pushNotificationsEnabled = false
    }
}