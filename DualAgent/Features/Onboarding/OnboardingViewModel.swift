import Foundation
import Combine

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var selectedBackendType: BackendType = .hermes
    @Published var serverURL: String = ""
    /// Single shared credential field:
    ///   - Hermes: server password (POSTed to /api/auth/login)
    ///   - OpenClaw: gateway token (sent as Bearer header; from `openclaw config get gateway.auth.token`)
    /// Hermes never uses a username; OpenClaw never uses an API key.
    @Published var credential: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isAuthenticated: Bool = false

    // QR pairing state (OpenClaw only).
    @Published var showQRScanner: Bool = false
    @Published var isPairing: Bool = false
    @Published var pairingStatus: String = "Preparing…"
    private var pairingTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    /// The AuthManager instance the UI uses. Always non-nil after init;
    /// `OnboardingForm` constructs the VM with the real injected instance.
    let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
        authManager.$isAuthenticated
            .assign(to: &$isAuthenticated)
        applyDebugLaunchArgs()
    }

    // MARK: - Debug Launch Args (simulator-only auto-fill)

    /// Read simulator-only launch arguments + env vars to pre-fill the
    /// form and optionally auto-connect. Wrapped in #if DEBUG so release
    /// builds carry zero of this code.
    private func applyDebugLaunchArgs() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        func value(forKey key: String) -> String? {
            if let v = env[key], !v.isEmpty { return v }
            if let i = args.firstIndex(of: key), i + 1 < args.count {
                return args[i + 1]
            }
            return nil
        }
        if let url = value(forKey: "-DAServerURL") ?? value(forKey: "DA_SERVER_URL") {
            serverURL = url
        }
        if let cred = value(forKey: "-DACredential") ?? value(forKey: "DA_CREDENTIAL") {
            credential = cred
        }
        if let backend = value(forKey: "-DABackend") ?? value(forKey: "DA_BACKEND") {
            if backend.lowercased() == "openclaw" { selectedBackendType = .openclaw }
        }
        #endif
    }

    func runDebugAutoConnectIfRequested() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        func value(forKey key: String) -> String? {
            if let v = env[key], !v.isEmpty { return v }
            if let i = args.firstIndex(of: key), i + 1 < args.count {
                return args[i + 1]
            }
            return nil
        }
        guard (value(forKey: "-DAAutoConnect") ?? value(forKey: "DA_AUTO_CONNECT")) == "1" else { return }
        guard UserDefaults.standard.bool(forKey: "debug.autoConnect.hasRun") == false else { return }
        UserDefaults.standard.set(true, forKey: "debug.autoConnect.hasRun")
        print("DUALAGENT_AUTO_CONNECT starting")
        try? await Task.sleep(nanoseconds: 700_000_000)
        testConnection()
        #endif
    }

    // MARK: - Connection

    /// Human-readable label for the credential field, based on the
    /// selected backend — shown in the UI as the SecureField placeholder.
    var credentialLabel: String {
        switch selectedBackendType {
        case .hermes: return "Server Password"
        case .openclaw: return "Gateway Token"
        }
    }

    var credentialHelp: String {
        switch selectedBackendType {
        case .hermes:
            return "Hermes signs in with a single server password. If the server has auth turned off, this field can be left empty."
        case .openclaw:
            return "Paste the token from OpenClaw: run `openclaw config get gateway.auth.token` on the gateway host — or use the QR option below."
        }
    }

    func testConnection() {
        Haptic.tap()
        isLoading = true
        showError = false
        errorMessage = ""

        authManager.switchBackend(to: selectedBackendType)

        Task {
            do {
                try await authManager.connect(
                    serverURL: serverURL,
                    credential: credential
                )
                Haptic.paired()
                isLoading = false
            } catch {
                Haptic.error()
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - QR Pairing

    /// Kick off pairing from a scanned QR payload. Drives the OpenClaw
    /// websocket handshake through `OpenClawBackend.startPairing` and updates
    /// the UI as events arrive.
    func startPairing(from payload: String) {
        guard selectedBackendType == .openclaw else { return }
        authManager.switchBackend(to: .openclaw)

        isPairing = true
        showError = false
        errorMessage = ""
        pairingStatus = "Connecting to gateway…"

        let backend = OpenClawBackend.shared
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let task = Task { @MainActor in
            let stream = backend.startPairing(from: payload, appVersion: appVersion)
            do {
                for try await event in stream {
                    switch event {
                    case .connecting(let url):
                        pairingStatus = "Connecting to \(url.host ?? "gateway")…"
                    case .challengeReceived:
                        pairingStatus = "Verifying setup code…"
                    case .paired(let result):
                        pairingStatus = "Paired as \(result.role). Signing in…"
                        isPairing = false
                        // Don't call authManager.connect() here — that would call
                        // backend.login(), which opens a SECOND WebSocket and re-pairs
                        // with the just-issued deviceToken. The QR pairing already
                        // established auth; just persist the token and flip state.
                        authManager.switchBackend(to: .openclaw)
                        if let openClaw = authManager.backend as? OpenClawBackend {
                            openClaw.markPaired(deviceToken: result.deviceToken,
                                                stableID: result.stableID)
                        }
                        do {
                            try await authManager.completeOpenClawPairing(
                                deviceToken: result.deviceToken,
                                stableID: result.stableID
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                        return
                    case .failed(let error):
                        isPairing = false
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        showError = true
                        return
                    }
                }
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        pairingTask = task
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        isPairing = false
        pairingStatus = "Cancelled"
    }
}
