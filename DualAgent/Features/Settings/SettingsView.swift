import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Server Connection")) {
                    TextField("Server URL", text: $viewModel.serverURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    Button {
                        viewModel.testConnection()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test Connection")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.serverURL.isEmpty || viewModel.isLoading)
                    .buttonStyle(.borderedProminent)
                }

                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $viewModel.themeSelection) {
                        Text("System").tag("System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Model Settings")) {
                    TextField("Default Model", text: $viewModel.defaultModel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Section(header: Text("Advanced")) {
                    Button {
                        Task { try? await viewModel.clearCache() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Clear Cache")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Settings")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                viewModel.loadSettings()
            }
        }
    }
}

#Preview {
    SettingsView()
}