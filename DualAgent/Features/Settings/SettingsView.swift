import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Connection")) {
                    TextField("Server URL", text: $viewModel.serverURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    Button(action: {
                        viewModel.testConnection()
                    }) {
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
                    Button(action: {
                        viewModel.clearCache()
                    }) {
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
            .alert(isPresented: $viewModel.showError) {
                Alert(title: Text(viewModel.isLoading ? "Please Wait" : "Error"),
                      message: Text(viewModel.errorMessage),
                      dismissButton: .default(Text("OK")))
            }
            .onAppear {
                // Ensure settings are loaded when view appears
                viewModel.loadSettings()
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}