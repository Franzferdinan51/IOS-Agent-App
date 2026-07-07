import Foundation
import Combine

@MainActor
final class DeviceControlsViewModel: ObservableObject {
    @Published var cameraEnabled = false
    @Published var microphoneEnabled = false
    @Published var locationEnabled = false
    @Published var isLoading = false

    func requestCameraAccess() async {
        // Request camera permission via OpenClaw device auth
        cameraEnabled = true
    }

    func requestMicrophoneAccess() async {
        microphoneEnabled = true
    }

    func requestLocationAccess() async {
        locationEnabled = true
    }
}
