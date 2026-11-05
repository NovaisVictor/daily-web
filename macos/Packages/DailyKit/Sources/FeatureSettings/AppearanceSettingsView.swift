import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Theme, density, backdrop and content width (`components/AppearancePanel.tsx`).
/// Each pick applies at once and is saved with `PATCH /api/preferences`.
struct AppearanceSettingsView: View {
  @Environment(\.theme) private var theme
  let preferences: PreferencesStore

  /// `THEME_OPTIONS`, `DENSITY_OPTIONS` and `BACKDROP_OPTIONS` of the web.
  static let themes: [(AppearanceTheme, String, String)] = [
    (.system, "Sistema", "desktopcomputer"), (.light, "Claro", "sun.max"), (.dark, "Escuro", "moon"),
  ]
  static let densities: [(AppearanceDensity, String)] = [(.comfortable, "Confortável"), (.compact, "Compacto")]
  static let backdrops: [(AppearanceBackdrop, String)] = [
    (.mesh, "Gradiente"), (.catppuccin, "Catppuccin"),
    // Only the dark theme is remapped, so the hint keeps a light-theme pick from looking broken.
    (.dracula, "Dracula (só no tema escuro)"), (.wezterm, "WezTerm (só no tema escuro)"),
  ]
  /// `LIMITED_CONTENT_WIDTH`, `lib/theme.ts:14`.
  static let limitedWidth = 1216

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SettingsSection("Tema") {
        options(Self.themes.map { ($0.0, $0.1, $0.2) }, selected: preferences.appearance.theme ?? .system) {
          Appearance(theme: $0)
        }
      }
      SettingsSection("Densidade") {
        options(
          Self.densities.map { ($0.0, $0.1, nil) }, selected: preferences.appearance.density ?? .comfortable
        ) { Appearance(density: $0) }
      }
      SettingsSection("Fundo") {
        options(Self.backdrops.map { ($0.0, $0.1, nil) }, selected: preferences.appearance.backdrop ?? .mesh) {
          Appearance(backdrop: $0)
        }
      }
      SettingsSection("Largura do conteúdo") {
        widthCard
      }
    }
  }

  /// The web's row of `size="sm"` buttons, `default` for the current pick and
  /// `outline` for the others, with `aria-pressed`.
  private func options<Value: Hashable>(
    _ items: [(Value, String, String?)],
    selected: Value,
    patch: @escaping (Value) -> Appearance
  ) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(items, id: \.0) { value, label, symbol in
        let isOn = value == selected
        Button {
          Task { await preferences.updateAppearance(patch(value)) }
        } label: {
          if let symbol {
            Label(label, systemImage: symbol)
          } else {
            Text(label)
          }
        }
        .pillButtonStyle(isOn ? .primary : .outline, size: .small)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
      }
    }
  }

  /// `w-56 rounded-xl border bg-glass p-4 shadow-e1` with the switch and the hint.
  private var widthCard: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        Image(systemName: "arrow.left.and.right")
          .font(.system(size: 18))
          .foregroundStyle(theme.inkMid)
          .accessibilityHidden(true)
        Spacer()
        Toggle("Limitar largura", isOn: limitedWidth)
          .toggleStyle(.switch)
          .labelsHidden()
      }
      HStack(spacing: 8) {
        Text("Limitar largura")
          .typeRole(.data)
          .foregroundStyle(theme.ink)
          .accessibilityHidden(true)
        Spacer()
        Image(systemName: "info.circle")
          .font(.system(size: 14))
          .foregroundStyle(theme.inkDim)
          .help(Self.widthHint)
          .accessibilityLabel("Sobre limitar a largura")
          .accessibilityHint(Self.widthHint)
      }
    }
    .padding(16)
    .frame(width: 224)
    .glassSurface(.panel, elevation: .e1)
  }

  static let widthHint =
    "Ligado, o conteúdo fica com no máximo \(limitedWidth)px, centralizado. "
    + "Desligado, ocupa a largura toda da tela, como o cabeçalho."

  private var limitedWidth: Binding<Bool> {
    Binding(
      get: { preferences.appearance.width == .limited },
      set: { on in
        Task { await preferences.updateAppearance(Appearance(width: on ? .limited : .full)) }
      }
    )
  }
}
