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

// MARK: - Logo Mark

/// Custom-drawn app logo mark. Two stacked, slightly offset rounded squares
/// — one outlined, one filled — read as a literal "two backends in one app".
/// Drawn with `Canvas` so there is zero risk of overlap with any third-party
/// brand mark (no SF Symbol, no bitmap, no chat-bubble silhouette).
///
/// Reads as the literal name: **Dual**Agent.
struct DualAgentLogoMark: View {
    /// Visual weight of the outlined (top) tile. 0.0–1.0.
    var topOpacity: Double = 1.0
    /// Visual weight of the filled (bottom) tile. 0.0–1.0.
    var bottomOpacity: Double = 1.0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let unit = min(w, h)
            let corner = unit * 0.22          // rounded corners, large enough to read as "card"
            let tileW = unit * 0.66           // each tile is 66% of the unit
            let tileH = unit * 0.46           // tiles are wide-rectangular
            let dx = unit * 0.08              // horizontal offset between tiles
            let dy = unit * 0.10              // vertical offset

            // Bottom tile — filled, slightly behind/lower-left.
            let bottomRect = CGRect(
                x: (w - tileW) / 2 - dx,
                y: (h - tileH) / 2 + dy,
                width: tileW,
                height: tileH
            )
            ctx.fill(
                Path(roundedRect: bottomRect, cornerRadius: corner),
                with: .color(.white.opacity(bottomOpacity * 0.35))
            )

            // Top tile — outlined, slightly forward/upper-right.
            let topRect = CGRect(
                x: (w - tileW) / 2 + dx,
                y: (h - tileH) / 2 - dy,
                width: tileW,
                height: tileH
            )
            ctx.stroke(
                Path(roundedRect: topRect, cornerRadius: corner),
                with: .color(.white.opacity(topOpacity)),
                lineWidth: unit * 0.10
            )

            // Single dot in the top tile — the "agent" presence marker.
            let dotR = unit * 0.06
            let dotOrigin = CGPoint(
                x: topRect.midX - dotR,
                y: topRect.midY - dotR
            )
            ctx.fill(
                Path(ellipseIn: CGRect(origin: dotOrigin, size: CGSize(width: dotR * 2, height: dotR * 2))),
                with: .color(.white.opacity(topOpacity))
            )
        }
        .accessibilityLabel("DualAgent")
    }
}

// MARK: - Persisted App Settings

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("app.appearance.theme") private(set) var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("app.appearance.accent") private(set) var accentHex: String = AccentColor.indigo.hex
    @AppStorage("app.appearance.tintsPrimaryActions") private(set) var tintsPrimaryActions: Bool = true
    @AppStorage("app.haptics.enabled") private(set) var hapticsEnabled: Bool = true
    @AppStorage("app.notifications.responseCompletion") private(set) var responseCompletionNotificationsEnabled: Bool = false
    @AppStorage("app.chat.assistantTimestamps") private(set) var showAssistantTimestamps: Bool = true
    @AppStorage("app.chat.showThinkingAndToolCards") private(set) var showThinkingAndToolCards: Bool = true
    @AppStorage("app.chat.wrapsCodeBlockLines") private(set) var wrapCodeBlockLines: Bool = true
    @AppStorage("app.defaultModel") private(set) var defaultModel: String = "MiniMax-M2.7"
    @AppStorage("app.defaultWorkspace") private(set) var defaultWorkspace: String = ""
    @AppStorage("app.chat.rtlOverride") private(set) var rtlOverrideEnabled: Bool = false

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var accent: AccentColor {
        get { AccentColor(hex: accentHex) ?? .indigo }
        set { accentHex = newValue.hex; objectWillChange.send() }
    }

    var effectiveAccent: AccentColor { accent }
    var colorScheme: ColorScheme? { theme.colorScheme }

    private init() {}

    func setTheme(_ theme: AppTheme) { self.theme = theme }
    func setAccent(_ color: AccentColor) { self.accent = color }
    func setHaptics(_ enabled: Bool) { hapticsEnabled = enabled; objectWillChange.send() }
    func setResponseCompletionNotifications(_ enabled: Bool) { responseCompletionNotificationsEnabled = enabled; objectWillChange.send() }
    func setShowAssistantTimestamps(_ enabled: Bool) { showAssistantTimestamps = enabled; objectWillChange.send() }
    func setShowThinkingAndToolCards(_ enabled: Bool) { showThinkingAndToolCards = enabled; objectWillChange.send() }
    func setWrapCodeBlockLines(_ enabled: Bool) { wrapCodeBlockLines = enabled; objectWillChange.send() }
    func setTintsPrimaryActions(_ enabled: Bool) { tintsPrimaryActions = enabled; objectWillChange.send() }
    func setDefaultModel(_ model: String) { defaultModel = model; objectWillChange.send() }
    func setDefaultWorkspace(_ workspace: String) { defaultWorkspace = workspace; objectWillChange.send() }
    func setRTLOverride(_ enabled: Bool) { rtlOverrideEnabled = enabled; objectWillChange.send() }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AccentColor: Identifiable, Equatable, Hashable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hexRGB: hex) ?? .blue }

    static let presets: [AccentColor] = [
        AccentColor(name: "Hermes Indigo", hex: "#457FF2"),
        AccentColor(name: "OpenClaw Violet", hex: "#9F57F2"),
        AccentColor(name: "Cyan", hex: "#33BDEB"),
        AccentColor(name: "Orange", hex: "#F78233"),
        AccentColor(name: "Green", hex: "#34C874"),
        AccentColor(name: "Amber", hex: "#F8B333"),
        AccentColor(name: "Pink", hex: "#FF5BAA"),
        AccentColor(name: "Red", hex: "#F34D4D")
    ]

    static let indigo = AccentColor(name: "Hermes Indigo", hex: "#457FF2")

    init(name: String, hex: String) {
        self.name = name
        self.hex = AccentColor.normalizedHex(hex) ?? hex.uppercased()
    }

    init?(hex: String) {
        guard let normalized = AccentColor.normalizedHex(hex) else { return nil }
        self.hex = normalized
        self.name = AccentColor.presets.first(where: { $0.hex == normalized })?.name ?? "Custom"
    }

    static func normalizedHex(_ raw: String) -> String? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex.uppercased()
    }
}

extension Color {
    init?(hexRGB raw: String) {
        guard let hex = AccentColor.normalizedHex(raw),
              let value = UInt32(String(hex.dropFirst()), radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}