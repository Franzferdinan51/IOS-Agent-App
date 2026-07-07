import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Backend Selection
                Section(header: Text("Backend")) {
                    Picker("Backend Type", selection: $viewModel.selectedBackendType) {
                        Text("Hermes").tag(BackendType.hermes)
                        Text("OpenClaw").tag(BackendType.openclaw)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: viewModel.selectedBackendType) { newType in
                        viewModel.serverURL = defaultURL(for: newType)
                    }
                }

                // MARK: - Server Configuration
                Section(header: Text("Server")) {
                    TextField("Server URL", text: $viewModel.serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                // MARK: - Credentials
                Section(header: Text("Credentials")) {
                    if viewModel.selectedBackendType == .hermes {
                        TextField("Username", text: $viewModel.username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        SecureField("Password", text: $viewModel.password)
                            .textContentType(.password)
                    } else {
                        SecureField("API Key / Token", text: $viewModel.apiKey)
                            .textContentType(.password)
                    }
                }

                // MARK: - Error Message
                if viewModel.showError {
                    Section {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                // MARK: - Login Button
                Section {
                    Button(action: {
                        viewModel.testConnection()
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Login")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .navigationTitle("Welcome")
        }
    }

    private func defaultURL(for backendType: BackendType) -> String {
        switch backendType {
        case .hermes:
            return AppConfig.hermesBaseURL.absoluteString
        case .openclaw:
            return AppConfig.openClawBaseURL.absoluteString
        }
    }
}
