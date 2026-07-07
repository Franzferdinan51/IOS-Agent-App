import SwiftUI

// MARK: - Connection Status

/// Represents the current state of a backend connection.
enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case connecting
    case unknown
}

// MARK: - Connection Status View

/// A compact, glance-able indicator showing real-time backend connection health.
///
/// Shows a colored dot (green/red/yellow/gray) and an optional label.
/// Animates a pulse when the status is `.connecting`.
///
/// Example usage:
/// ```swift
/// ConnectionStatusView(status: .connected, label: "Hermes")
/// ConnectionStatusView(status: .disconnected, label: "OpenClaw")
/// ```
struct ConnectionStatusView: View {
    let status: ConnectionStatus
    let label: String?

    @State private var isPulsing = false

    init(status: ConnectionStatus, label: String? = nil) {
        self.status = status
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            statusDot
            if let label = label {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        ZStack {
            // Outer pulse ring (only visible when connecting)
            if status == .connecting {
                Circle()
                    .stroke(pulseColor.opacity(0.5), lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.7)
            }

            // Inner filled dot
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundColor(dotColor)
                .scaleEffect(status == .connecting && isPulsing ? 1.15 : 1.0)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            startPulseAnimation()
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .connecting {
                startPulseAnimation()
            }
        }
    }

    private var dotColor: Color {
        switch status {
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .connecting:
            return .yellow
        case .unknown:
            return .gray
        }
    }

    private var pulseColor: Color {
        switch status {
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .connecting:
            return .yellow
        case .unknown:
            return .gray
        }
    }

    private func startPulseAnimation() {
        guard status == .connecting else {
            isPulsing = false
            return
        }
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ConnectionStatusView(status: .connected, label: "Hermes")
            ConnectionStatusView(status: .disconnected, label: "OpenClaw")
        }
        HStack(spacing: 20) {
            ConnectionStatusView(status: .connecting, label: "Connecting")
            ConnectionStatusView(status: .unknown, label: "Unknown")
        }
        HStack(spacing: 20) {
            ConnectionStatusView(status: .connected)
            ConnectionStatusView(status: .disconnected)
        }
    }
    .padding()
}
