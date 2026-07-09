import SwiftUI

// MARK: - OnboardingView (thin wrapper)
/// Holds `@EnvironmentObject var authManager` so it is resolved by the SwiftUI
/// runtime before any child-view `@StateObject` is evaluated. The actual form
/// content lives in `OnboardingForm`, which receives `authManager` as a plain
/// init parameter — not via `@EnvironmentObject` — so the VM is always
/// initialised with the correct, live instance.
struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.brand) private var brand: Theme.Brand

    var body: some View {
        OnboardingForm(
            authManager: authManager,
            brand: brand
        )
    }
}

// MARK: - OnboardingForm (all form content lives here)
/// Receives `authManager` as a let parameter rather than via
/// `@EnvironmentObject`, so that `@StateObject private var viewModel` can be
/// initialised with the real injected instance in its init.
struct OnboardingForm: View {
    @StateObject private var viewModel: OnboardingViewModel
    let brand: Theme.Brand

    init(authManager: AuthManager, brand: Theme.Brand) {
        self.brand = brand
        // StateObject init runs before any SwiftUI view body is evaluated.
        // Passing authManager here ensures the VM is bound to the SAME
        // AuthManager instance that RootView watches for isLoggedIn.
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(authManager: authManager)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground(brand: brand)

                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(brand.gradient)
                                    .frame(width: 84, height: 84)
                                    .shadow(color: brand.primary.opacity(0.35), radius: 12, y: 6)
                                DualAgentLogoMark()
                                    .frame(width: 52, height: 52)
                                    .foregroundColor(.white)
                            }

                            Text("DualAgent")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.Neutral.textPrimary)

                            Text("Choose your backend and connect.")
                                .font(.subheadline)
                                .foregroundColor(Theme.Neutral.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)

                        // MARK: - Backend Picker
                        Theme.BrandCard(brand: brand) {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Backend", systemImage: "server.rack")
                                    .font(.headline)
                                    .foregroundColor(brand.primary)

                                Picker("Backend", selection: $viewModel.selectedBackendType) {
                                    ForEach(Theme.Brand.allCases) { b in
                                        Text(b.displayName).tag(backendType(for: b))
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: viewModel.selectedBackendType) { newType in
                                    Haptic.selectionChanged()
                                    viewModel.authManager.switchBackend(to: newType)
                                }

                                Text("Hermes = single password.  OpenClaw = gateway token or QR pairing.")
                                    .font(.caption)
                                    .foregroundColor(Theme.Neutral.textSecondary)
                            }
                        }

                        // MARK: - Server URL
                        Theme.BrandCard(brand: brand) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Server", systemImage: "network")
                                    .font(.headline)
                                    .foregroundColor(brand.primary)

                                TextField("https://your-host.example", text: $viewModel.serverURL)
                                    .textContentType(.URL)
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Theme.Neutral.background)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Theme.Neutral.border, lineWidth: 1)
                                    )
                            }
                        }

                        // MARK: - Credentials
                        Theme.BrandCard(brand: brand) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(brand.primary)
                                    Text("Credentials")
                                        .font(.headline)
                                        .foregroundColor(brand.primary)
                                }

                                SecureField(viewModel.credentialLabel, text: $viewModel.credential)
                                    .textContentType(.password)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Theme.Neutral.background)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Theme.Neutral.border, lineWidth: 1)
                                    )

                                Text(viewModel.credentialHelp)
                                    .font(.caption)
                                    .foregroundColor(Theme.Neutral.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if viewModel.selectedBackendType == .openclaw {
                                    divider

                                    Button {
                                        Haptic.tap()
                                        viewModel.showQRScanner = true
                                    } label: {
                                        Label("Pair with QR Code", systemImage: "qrcode.viewfinder")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(brand.primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(brand.primary, lineWidth: 1)
                                            )
                                    }
                                    .disabled(viewModel.isPairing)
                                }
                            }
                        }

                        // MARK: - Pairing progress
                        if viewModel.isPairing {
                            Theme.BrandCard(brand: brand) {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(brand.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.pairingStatus)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(Theme.Neutral.textPrimary)
                                        Text("Keep the camera pointed at the code while we connect.")
                                            .font(.caption)
                                            .foregroundColor(Theme.Neutral.textSecondary)
                                    }
                                    Spacer()
                                    Button("Cancel") {
                                        viewModel.cancelPairing()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.error)
                                }
                            }
                        }

                        // MARK: - Error
                        if viewModel.showError {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.white)
                                Text(viewModel.errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.error)
                            )
                        }

                        // MARK: - Connect
                        Button {
                            viewModel.testConnection()
                        } label: {
                            Text("Connect")
                        }
                        .buttonStyle(Theme.PrimaryButtonStyle(brand: brand, isLoading: viewModel.isLoading))
                        .disabled(viewModel.isLoading || viewModel.isPairing)
                        .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.runDebugAutoConnectIfRequested()
            }
            // QR scanner sheet — viewModel and authManager are both available here
            .sheet(isPresented: $viewModel.showQRScanner) {
                OpenClawQRScannerView { payload in
                    viewModel.startPairing(from: payload)
                }
                .environment(\.brand, .openclaw)
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Theme.Neutral.divider)
                .frame(height: 1)
            Text("OR")
                .font(.caption2.weight(.semibold))
                .foregroundColor(Theme.Neutral.textSecondary)
            Rectangle()
                .fill(Theme.Neutral.divider)
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func backendType(for brand: Theme.Brand) -> BackendType {
        switch brand {
        case .hermes: return .hermes
        case .openclaw: return .openclaw
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingView()
        .environmentObject(AuthManager.shared)
        .environment(\.brand, .hermes)
}
