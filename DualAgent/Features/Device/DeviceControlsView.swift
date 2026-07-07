import SwiftUI

/// Shows device control panels (camera, mic, location, sensors) when connected to OpenClaw backend.
/// This view is conditionally shown based on the connected backend type.
struct DeviceControlsView: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraEnabled = false
    @State private var microphoneEnabled = false
    @State private var locationEnabled = false
    @State private var isLoading = false

    var isOpenClawBackend: Bool {
        appState.selectedBackend == .openclaw
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isOpenClawBackend {
                    ContentUnavailableView {
                        Label("Device Controls", systemImage: "sensor.tag.radiowaves")
                    } description: {
                        Text("Device controls are only available when connected to an OpenClaw gateway.")
                    } actions: {
                        Button("Switch to OpenClaw") {
                            appState.switchBackend(to: .openclaw)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            Toggle("Camera", isOn: $cameraEnabled)
                            Toggle("Microphone", isOn: $microphoneEnabled)
                            Toggle("Location", isOn: $locationEnabled)
                        } header: {
                            Text("Sensors")
                        } footer: {
                            Text("Enable sensors to allow the agent to use your device capabilities.")
                        }

                        Section("Status") {
                            LabeledContent("Backend", value: appState.selectedBackend.rawValue)
                            LabeledContent("Connection", value: "Connected")
                        }
                    }
                }
            }
            .navigationTitle("Device Controls")
        }
    }
}
