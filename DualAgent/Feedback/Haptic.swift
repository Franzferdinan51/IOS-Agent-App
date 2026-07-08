import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Haptic language for DualAgent — subtle, native-feeling feedback on
/// key events. Use instead of sprinkling `UIImpactFeedbackGenerator` calls
/// across view code; the centralized API lets us tune intensity, audit
/// every site, and disable globally for accessibility.
enum Haptic {

    /// Pre-generators cached at app start for low-latency invocation.
    /// `prepare()` is called once on `Haptic.prepareAll()` from
    /// `DualAgentApp.onAppear` to avoid the ~30ms first-fire cost.
    #if canImport(UIKit)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()
    #endif

    /// Call once at app launch to prime the haptic engines.
    static func prepareAll() {
        #if canImport(UIKit)
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
        #endif
    }

    // MARK: - Discrete events

    /// Message sent.
    static func send() {
        #if canImport(UIKit)
        impactMedium.impactOccurred()
        #endif
    }

    /// Stream finished / reply complete — the signature "I'm done" feel.
    static func completion() {
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        impactLight.impactOccurred(intensity: 0.6)
        #endif
    }

    /// Error / 401 / failed send.
    static func error() {
        #if canImport(UIKit)
        notification.notificationOccurred(.error)
        #endif
    }

    /// Validation issue (empty send, bad URL).
    static func warning() {
        #if canImport(UIKit)
        notification.notificationOccurred(.warning)
        #endif
    }

    /// User pulled-to-refresh or tapped a tab.
    static func tap() {
        #if canImport(UIKit)
        impactLight.impactOccurred()
        #endif
    }

    /// Picker / segmented control change.
    static func selectionChanged() {
        #if canImport(UIKit)
        selection.selectionChanged()
        #endif
    }

    /// Long-press started (e.g. message action menu).
    static func longPress() {
        #if canImport(UIKit)
        impactMedium.impactOccurred(intensity: 0.8)
        #endif
    }

    /// Successful QR scan / pairing complete.
    static func paired() {
        #if canImport(UIKit)
        notification.notificationOccurred(.success)
        // Double-pulse for the "yes, you're in" feel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            impactLight.impactOccurred()
        }
        #endif
    }
}
