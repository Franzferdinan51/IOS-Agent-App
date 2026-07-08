import SwiftUI
import AVFoundation

/// AVCapture-based QR scanner, presented as a sheet from the onboarding screen.
///
/// On the first valid QR scan it calls `onResult` and dismisses itself.
/// The scanner intentionally ignores duplicates after the first hit.
struct OpenClawQRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (String) -> Void

    @State private var cameraAuthorized: Bool? = nil
    @State private var scannedOnce = false

    var body: some View {
        ZStack {
            BrandBackground(brand: .openclaw)

            VStack(spacing: 18) {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text("Scan OpenClaw QR Code")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.clear)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Scanner viewport with branded frame
                ZStack {
                    if cameraAuthorized == true {
                        ScannerRepresentable(onScan: handleScan)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else if cameraAuthorized == false {
                        PermissionDeniedView()
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.4)
                    }

                    // Viewfinder overlay
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                }
                .frame(width: 280, height: 280)
                .shadow(color: Theme.Brand.openclaw.primary.opacity(0.6), radius: 20, y: 8)

                Text("Point at the QR code shown by `openclaw devices setup-code` on the gateway host.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear { requestCameraAccess() }
    }

    private func handleScan(_ raw: String) {
        guard !scannedOnce else { return }
        scannedOnce = true
        Haptic.paired()
        onResult(raw)
        dismiss()
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraAuthorized = granted }
            }
        case .denied, .restricted:
            cameraAuthorized = false
        @unknown default:
            cameraAuthorized = false
        }
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundColor(.white)
            Text("Camera access required")
                .font(.headline)
                .foregroundColor(.white)
            Text("Enable camera in Settings → DualAgent to scan QR codes.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .foregroundColor(.white)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - AVCaptureSession-backed UIViewController

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onScan: onScan)
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onScan: (String) -> Void
    private var hasFired = false
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasFired,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let payload = obj.stringValue
        else { return }
        hasFired = true
        onScan(payload)
        session.stopRunning()
    }
}