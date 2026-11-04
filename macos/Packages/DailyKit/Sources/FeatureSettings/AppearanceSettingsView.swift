import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Theme, density, backdrop and content width (`components/AppearancePanel.tsx`).
/// Each pick applies at once and is saved with `PATCH /api/preferences`.
struct AppearanceSettingsView: View {
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
    Form {
      Section("Tema") {
        Picker("Tema", selection: binding(\.theme, default: .system) { Appearance(theme: $0) }) {
          ForEach(Self.themes, id: \.0) { value, label, symbol in
            Label(label, systemImage: symbol).tag(value)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      Section("Densidade") {
        Picker("Densidade", selection: binding(\.density, default: .comfortable) { Appearance(density: $0) }) {
          ForEach(Self.densities, id: \.0) { value, label in
            Text(label).tag(value)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      Section("Fundo") {
        Picker("Fundo", selection: binding(\.backdrop, default: .mesh) { Appearance(backdrop: $0) }) {
          ForEach(Self.backdrops, id: \.0) { value, label in
            Text(label).tag(value)
          }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
      }
      Section("Largura do conteúdo") {
        Toggle(isOn: limitedWidth) {
          Text("Limitar largura")
          Text(
            "Ligado, o conteúdo fica com no máximo \(Self.limitedWidth)px, centralizado. "
              + "Desligado, ocupa a largura toda da tela, como o cabeçalho.")
        }
      }
    }
    .formStyle(.grouped)
  }

  private var limitedWidth: Binding<Bool> {
    Binding(
      get: { preferences.appearance.width == .limited },
      set: { on in
        Task { await preferences.updateAppearance(Appearance(width: on ? .limited : .full)) }
      }
    )
  }

  /// The saved value, or the web's default when never chosen; a pick saves
  /// only that field.
  private func binding<Value>(
    _ keyPath: KeyPath<Appearance, Value?>,
    default fallback: Value,
    patch: @escaping (Value) -> Appearance
  ) -> Binding<Value> {
    Binding(
      get: { preferences.appearance[keyPath: keyPath] ?? fallback },
      set: { value in
        Task { await preferences.updateAppearance(patch(value)) }
      }
    )
  }
}
