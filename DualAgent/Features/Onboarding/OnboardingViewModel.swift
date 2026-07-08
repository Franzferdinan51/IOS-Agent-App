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

    // QR pairing state (OpenClaw only).
    @Published var showQRScanner: Bool = false
    @Published var isPairing: Bool = false
    @Published var pairingStatus: String = "Preparing…"
    private var pairingTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    init() {
        AuthManager.shared.$isAuthenticated
            .assign(to: &$isAuthenticated)
        serverURL = AppConfig.hermesBaseURL.absoluteString
    }

    @Published var isAuthenticated: Bool = false

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

        AuthManager.shared.switchBackend(to: selectedBackendType)

        Task {
            do {
                try await AuthManager.shared.connect(
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
    func startPairing(from payload: String, authManager: AuthManager) {
        guard selectedBackendType == .openclaw else { return }
        // Force the backend to OpenClaw before we drive the handshake.
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
                        authManager.switchBackend(to: .openclaw)
                        do {
                            try await authManager.connect(
                                serverURL: serverURL,
                                credential: result.deviceToken
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