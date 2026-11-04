import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Applies the stored appearance: color scheme, palette and backdrop.
struct ThemedRoot<Content: View>: View {
  let preferences: PreferencesStore
  @ViewBuilder let content: Content

  var body: some View {
    let appearance = DesignAppearance(preferences.appearance)
    Palette(backdrop: appearance.backdrop, density: appearance.density) { content }
      .preferredColorScheme(appearance.colorScheme)
  }

  /// Separate view so it reads the color scheme after `preferredColorScheme` applied.
  private struct Palette<Inner: View>: View {
    let backdrop: Backdrop
    let density: Density
    @ViewBuilder let inner: Inner
    @Environment(\.colorScheme) private var scheme

    var body: some View {
      let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: density)
      inner
        .environment(\.theme, theme)
        // Selection and prominent controls follow the brand, as on the web,
        // instead of the system accent color.
        .tint(theme.brand)
        .background(BackdropView(backdrop))
    }
  }
}

/// The server's appearance strings mapped to the design system's types; unknown
/// or missing values fall back to the web's defaults (`lib/theme.ts`).
struct DesignAppearance {
  let theme: ThemePreference
  let density: Density
  let backdrop: Backdrop

  init(_ appearance: Appearance) {
    theme = appearance.theme.flatMap { ThemePreference(rawValue: $0.rawValue) } ?? .system
    density = appearance.density.flatMap { Density(rawValue: $0.rawValue) } ?? .comfortable
    backdrop = appearance.backdrop.flatMap { Backdrop(rawValue: $0.rawValue) } ?? .mesh
  }

  var colorScheme: ColorScheme? {
    switch theme {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
