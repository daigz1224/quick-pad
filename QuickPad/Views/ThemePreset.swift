import SwiftUI

/// All visual tokens for QuickPad. Single set of values — no preset
/// switching, no font-size scaling. Light/dark variants exist where
/// they have to (text/surface/divider/hover); accents are scheme-
/// agnostic so they read on either backdrop.
struct Palette {
    let idea         = Color(red: 0.95, green: 0.75, blue: 0.30)
    let taskDone     = Color(red: 0.30, green: 0.78, blue: 0.60)
    let accent       = Color(red: 0.40, green: 0.55, blue: 0.90)
    let priority     = Color(red: 0.90, green: 0.40, blue: 0.40)

    let bgLight      = Color(red: 0.98, green: 0.98, blue: 0.99)
    let bgDark       = Color(red: 0.08, green: 0.08, blue: 0.09)
    let surfaceLight = Color(red: 0.96, green: 0.96, blue: 0.97)
    let surfaceDark  = Color(red: 0.11, green: 0.11, blue: 0.12)

    let textPrimaryLight   = Color(red: 0.08, green: 0.08, blue: 0.08)
    let textPrimaryDark    = Color(red: 0.95, green: 0.95, blue: 0.95)
    let textSecondaryLight = Color(red: 0.40, green: 0.40, blue: 0.40)
    let textSecondaryDark  = Color(red: 0.65, green: 0.65, blue: 0.65)
    let textTertiaryLight  = Color(red: 0.60, green: 0.60, blue: 0.60)
    let textTertiaryDark   = Color(red: 0.45, green: 0.45, blue: 0.45)

    let dividerLight = Color(red: 0.85, green: 0.85, blue: 0.87)
    let dividerDark  = Color(red: 0.25, green: 0.25, blue: 0.27)
    let hoverLight   = Color(red: 0.90, green: 0.90, blue: 0.92)
    let hoverDark    = Color(red: 0.18, green: 0.18, blue: 0.20)
}

/// Single source of truth for theme tokens. Holds no mutable state —
/// every value is constant. `@Observable` is preserved purely so views
/// can keep injecting it via `@Environment(ThemeManager.self)` without
/// disruption if state is reintroduced later.
@Observable
@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private let palette = Palette()

    // Density / typography knobs. Tuned for mixed CJK + Latin in a
    // 420-wide popover.
    let contentTracking: CGFloat    = -0.15
    let ideaItalic: Bool            = false
    let lineSpacing: CGFloat        = 3
    let rowVerticalPadding: CGFloat = 3
    let cornerRadius: CGFloat       = 6

    /// Base size multiplier — bumped above 1.0 because the hardcoded
    /// per-call sizes were tuned too small for comfortable reading.
    private let scale: CGFloat = 1.1

    init() {}

    // MARK: Accents

    var idea: Color     { palette.idea }
    var taskDone: Color { palette.taskDone }
    var accent: Color   { palette.accent }
    var priority: Color { palette.priority }

    // MARK: Surfaces

    func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.bgDark : palette.bgLight
    }
    func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.surfaceDark : palette.surfaceLight
    }

    // MARK: Text

    func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.textPrimaryDark : palette.textPrimaryLight
    }
    func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.textSecondaryDark : palette.textSecondaryLight
    }
    func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.textTertiaryDark : palette.textTertiaryLight
    }

    // MARK: Lines

    func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.dividerDark : palette.dividerLight
    }
    func hover(for scheme: ColorScheme) -> Color {
        scheme == .dark ? palette.hoverDark : palette.hoverLight
    }

    /// Faint accent-tinted color for timestamps and metadata — stays
    /// readable but stamps the brand accent on chrome rows.
    func timestampColor(for scheme: ColorScheme) -> Color {
        palette.accent.opacity(scheme == .dark ? 0.55 : 0.7)
    }

    // MARK: Fonts

    func contentFont(size: CGFloat) -> Font {
        Font.system(size: size * scale, weight: .regular, design: .default)
    }

    func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size * scale, weight: weight, design: .default)
    }

    /// Chrome font (timestamps, tags, shortcut hints). Always monospaced
    /// for tabular alignment.
    func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size * scale, weight: weight, design: .monospaced)
    }
}

// MARK: - BulletType theme integration

@MainActor
extension BulletType {
    /// Theme-aware glyph color for the fixed-width column. Pass
    /// `taskState` for `.task` bullets so done/cancelled/migrated states
    /// pick up their own colors. Island callers pass `.dark` regardless
    /// of system appearance because the pill is always on a black backdrop.
    func glyphColor(
        theme: ThemeManager,
        scheme: ColorScheme,
        taskState: TaskState? = nil
    ) -> Color {
        if self == .task, let state = taskState {
            switch state {
            case .done: return theme.taskDone
            case .cancelled: return theme.textTertiary(for: scheme)
            case .migrated: return theme.accent
            case .pending: return theme.textPrimary(for: scheme)
            }
        }
        switch self {
        case .idea: return theme.idea
        case .question: return theme.accent
        case .task, .note: return theme.textPrimary(for: scheme)
        case .unknown: return theme.textTertiary(for: scheme)
        }
    }

    /// Placeholder text for the input bar in both Popover and Island.
    var placeholder: String {
        switch self {
        case .note: return "note — what's on your mind?"
        case .task: return "task — what needs doing?"
        case .question: return "question — what are you wondering?"
        case .idea: return "idea — capture the spark"
        case .unknown: return "…"
        }
    }
}

// MARK: - View helpers

/// Subtle horizontal divider that fades at the edges. Picks up the
/// active theme's divider color via environment.
struct ThemeFadeDivider: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, theme.divider(for: scheme), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 0.5)
    }
}
