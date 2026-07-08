import SwiftUI

/// DualAgent theme — semantic colors, gradients, and reusable components.
///
/// Colors are defined entirely in code (no asset catalog required) so the app
/// stays shippable without needing a manual xcassets merge.
///
/// Brand split:
///   - Hermes = cool cyan/indigo (calm, server-y)
///   - OpenClaw = warm purple/orange (lively, gateway-y)
///
/// Both backends share a neutral surface palette (card, subtle border, text).
enum Theme {
    // MARK: - Brand Colors

    enum Brand: String, CaseIterable, Identifiable {
        case hermes
        case openclaw

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .hermes: return "Hermes"
            case .openclaw: return "OpenClaw"
            }
        }

        /// Primary tint color (icons, accents, primary buttons).
        var primary: Color {
            switch self {
            case .hermes: return Color(red: 0.27, green: 0.51, blue: 0.95)      // #457FF2 indigo
            case .openclaw: return Color(red: 0.62, green: 0.34, blue: 0.95)   // #9F57F2 violet
            }
        }

        /// Secondary tint (highlights, secondary buttons).
        var secondary: Color {
            switch self {
            case .hermes: return Color(red: 0.20, green: 0.74, blue: 0.92)      // #33BDEB cyan
            case .openclaw: return Color(red: 0.97, green: 0.51, blue: 0.20)   // #F78233 orange
            }
        }

        /// Background gradient stops, top → bottom.
        var gradient: LinearGradient {
            LinearGradient(
                colors: [primary.opacity(0.95), secondary.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Soft card background tinted with the brand (used for headers and big surfaces).
        var surface: Color {
            primary.opacity(0.12)
        }

        /// Status dot color for the connection indicator.
        var statusDot: Color { secondary }
    }

    // MARK: - Neutrals

    enum Neutral {
        /// Slightly tinted background to give the app a non-white feel.
        static let background = Color(.systemGroupedBackground)
        /// Card surface.
        static let card = Color(.secondarySystemGroupedBackground)
        /// Border for cards.
        static let border = Color.primary.opacity(0.08)
        /// Subtle divider.
        static let divider = Color.primary.opacity(0.06)
        /// Body text.
        static let textPrimary = Color.primary
        /// Secondary text.
        static let textSecondary = Color.secondary
    }

    // MARK: - Semantic

    static let success = Color(red: 0.20, green: 0.78, blue: 0.45)   // #34C874 green
    static let warning = Color(red: 0.97, green: 0.70, blue: 0.20)   // #F8B333 amber
    static let error = Color(red: 0.95, green: 0.30, blue: 0.30)     // #F34D4D red

    // MARK: - Reusable Components

    /// A brand-tinted card used for headers, login cards, etc.
    struct BrandCard<Content: View>: View {
        let brand: Brand
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Neutral.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(brand.primary.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: brand.primary.opacity(0.10), radius: 8, y: 4)
        }
    }

    /// A primary action button that uses the active brand color.
    struct PrimaryButtonStyle: ButtonStyle {
        let brand: Brand
        let isLoading: Bool

        func makeBody(configuration: Configuration) -> some View {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                configuration.label
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(brand.gradient)
            )
            .foregroundColor(.white)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// MARK: - Brand-aware Environment

/// Injects the current brand into the environment so child views can pick it up
/// without threading it through every initializer.
struct BrandKey: EnvironmentKey {
    static let defaultValue: Theme.Brand = .hermes
}

extension EnvironmentValues {
    var brand: Theme.Brand {
        get { self[BrandKey.self] }
        set { self[BrandKey.self] = newValue }
    }
}

// MARK: - Background

/// A subtle full-screen gradient background. Apply to the root scene so it
/// shows through translucent surfaces.
struct BrandBackground: View {
    let brand: Theme.Brand

    var body: some View {
        ZStack {
            Theme.Neutral.background
                .ignoresSafeArea()
            // Soft brand-tinted glow in the upper-left.
            RadialGradient(
                colors: [brand.primary.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
            // Soft secondary-tinted glow in the lower-right.
            RadialGradient(
                colors: [brand.secondary.opacity(0.15), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}