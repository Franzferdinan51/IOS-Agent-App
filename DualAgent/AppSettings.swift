import Foundation
import SwiftUI

/// User-facing appearance settings, persisted via @AppStorage so they survive
/// app restarts. Backed by the same shape hermex uses (AppTheme / HeaderLogoColor
/// in `Config/AppTheme.swift`) so the two iOS apps look like siblings.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Stored properties

    /// Light / dark / follow-system. Mirrors hermex's `AppTheme`.
    @AppStorage("app.appearance.theme") private(set) var themeRaw: String = AppTheme.system.rawValue
    /// Accent color used to tint primary actions (Compose, Send, the active tab).
    /// Defaults to the Hermes indigo brand; OpenClaw backend swaps to violet on
    /// sign-in. Mirrors hermex's `HeaderLogoColor` presets.
    @AppStorage("app.appearance.accent") private(set) var accentHex: String = "#457FF2"
    /// Tints primary actions (compose/send) with the accent color. Mirrors
    /// hermex's `PrimaryActionTintSettings`.
    @AppStorage("app.appearance.tintsPrimaryActions") private(set) var tintsPrimaryActions: Bool = true
    /// Haptic feedback. Mirrors hermex's `AppHaptics`.
    @AppStorage("app.haptics.enabled") private(set) var hapticsEnabled: Bool = true
    /// Push notification when an agent run finishes. Mirrors hermex's
    /// `ResponseCompletionNotifications`.
    @AppStorage("app.notifications.responseCompletion") private(set) var responseCompletionNotificationsEnabled: Bool = false
    /// Show timestamps above assistant turns. Mirrors
    /// `ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey`.
    @AppStorage("app.chat.assistantTimestamps") private(set) var showAssistantTimestamps: Bool = true
    /// Show thinking + tool-call cards in chat. Mirrors
    /// `ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey`.
    @AppStorage("app.chat.showThinkingAndToolCards") private(set) var showThinkingAndToolCards: Bool = true
    /// Wrap long code-block lines. Mirrors
    /// `ChatTranscriptDisplaySettings.wrapsCodeBlockLinesKey`.
    @AppStorage("app.chat.wrapsCodeBlockLines") private(set) var wrapCodeBlockLines: Bool = true
    /// Default model used when starting a new chat.
    @AppStorage("app.defaultModel") private(set) var defaultModel: String = "MiniMax-M2.7"
    /// Default workspace used when starting a new chat. Empty means the backend default.
    @AppStorage("app.defaultWorkspace") private(set) var defaultWorkspace: String = ""
    /// Chat layout direction override (nil = follow device language).
    @AppStorage("app.chat.rtlOverride") private(set) var rtlOverrideEnabled: Bool = false

    // MARK: - Derived

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var accent: AccentColor {
        get { AccentColor(hex: accentHex) ?? .indigo }
        set { accentHex = newValue.hex; objectWillChange.send() }
    }

    /// The accent actually used for the active backend. OpenClaw sessions
    /// pull toward violet, Hermes toward indigo. The user can still pick a
    /// custom color from the picker and it sticks across backends.
    var effectiveAccent: AccentColor { accent }

    /// The active color scheme for the window. nil = follow system.
    var colorScheme: ColorScheme? { theme.colorScheme }

    /// 0.0–1.0 haptics intensity (mirrors hermex's switch with an extra
    /// intensity knob so power users can dial it down).
    var hapticsIntensity: Double { hapticsEnabled ? 1.0 : 0.0 }

    private init() {}

    // MARK: - Mutators

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

// MARK: - AppTheme (matches hermex/Config/AppTheme.swift)

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - AccentColor (mirrors hermex/Config/AppTheme.swift HeaderLogoColor)

struct AccentColor: Identifiable, Equatable, Hashable {
    let name: String
    let hex: String

    var id: String { hex }

    var color: Color { Color(hexRGB: hex) ?? .blue }

    /// Presets. Mirrors hermex's HeaderLogoColor.presets but with a
    /// brand-default pair at the top (Hermes indigo / OpenClaw violet).
    static let presets: [AccentColor] = [
        AccentColor(name: "Hermes Indigo",  hex: "#457FF2"),
        AccentColor(name: "OpenClaw Violet", hex: "#9F57F2"),
        AccentColor(name: "Cyan",            hex: "#33BDEB"),
        AccentColor(name: "Orange",          hex: "#F78233"),
        AccentColor(name: "Green",           hex: "#34C874"),
        AccentColor(name: "Amber",           hex: "#F8B333"),
        AccentColor(name: "Pink",            hex: "#FF5BAA"),
        AccentColor(name: "Red",             hex: "#F34D4D"),
        AccentColor(name: "Mint",            hex: "#34D6B4"),
        AccentColor(name: "Gold",            hex: "#FFD700"),
    ]

    static let indigo  = AccentColor(name: "Hermes Indigo",  hex: "#457FF2")
    static let violet  = AccentColor(name: "OpenClaw Violet", hex: "#9F57F2")
    static let cyan    = AccentColor(name: "Cyan",            hex: "#33BDEB")
    static let orange  = AccentColor(name: "Orange",          hex: "#F78233")

    init(name: String, hex: String) {
        self.name = name
        self.hex = AccentColor.normalize(hex)
    }

    /// Failable lookup from a stored hex string. Returns nil on invalid input
    /// so the caller can fall back to a sane default.
    init?(hex: String) {
        guard let normalized = AccentColor.normalizedHex(hex) else { return nil }
        self.hex = normalized
        // Try to match a preset name; otherwise "Custom".
        self.name = AccentColor.presets.first { $0.hex == normalized }?.name ?? "Custom"
    }

    static func normalize(_ raw: String) -> String { normalizedHex(raw) ?? raw.uppercased() }

    /// Strips a leading `#`, lowercases everything, and re-adds `#` so stored
    /// values match the preset list. Returns nil for invalid lengths/chars.
    static func normalizedHex(_ raw: String) -> String? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex.uppercased()
    }
}

// MARK: - Color hex helper

extension Color {
    /// Build a Color from a 6-digit hex string ("#RRGGBB" or "RRGGBB").
    /// Mirrors hermex's `Color(hexRGB:)`. Returns nil on invalid input.
    init?(hexRGB raw: String) {
        guard let hex = AccentColor.normalizedHex(raw),
              let value = UInt32(String(hex.dropFirst()), radix: 16) else { return nil }
        self.init(
            red:   Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8)  / 255.0,
            blue:  Double( value & 0x0000FF)        / 255.0
        )
    }
}
