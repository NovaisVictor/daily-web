import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Theme, density, backdrop and content width (`components/AppearancePanel.tsx`).
/// Each pick applies at once and is saved with `PATCH /api/preferences`; the panel
/// material is the exception, kept on this Mac only.
struct AppearanceSettingsView: View {
  @Environment(\.theme) private var theme
  @AppStorage(PanelMaterial.storageKey) private var panelMaterial: PanelMaterial = .defaultValue
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
  /// Named after Apple's Liquid Glass variants; the web has no equivalent option.
  static let materials: [(PanelMaterial, String, String)] = [
    (.liquidGlass, "Liquid Glass", "Vidro regular: desfoca o fundo para manter a leitura"),
    (
      .clearGlass, "Liquid Glass transparente",
      "Variante clear: mais translúcida, com escurecimento sobre fundos claros"
    ),
    (
      .standard, "Material padrão",
      "Recomendação da Apple: vidro só nos controles e na navegação; painéis com material padrão"
    ),
  ]
  static let materialFootnote =
    "O app respeita a preferência de Liquid Glass do sistema e as opções de acessibilidade "
    + "Reduzir transparência e Aumentar contraste."
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
      SettingsSection("Material dos painéis") {
        materialPicker
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
    optionButtons(items, selected: selected) { value in
      Task { await preferences.updateAppearance(patch(value)) }
    }
  }

  /// The same row for a choice that is not a server preference.
  private func optionButtons<Value: Hashable>(
    _ items: [(Value, String, String?)],
    selected: Value,
    select: @escaping (Value) -> Void
  ) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(items, id: \.0) { value, label, symbol in
        let isOn = value == selected
        Button {
          select(value)
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

  private var materialPicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      optionButtons(Self.materials.map { ($0.0, $0.1, nil) }, selected: panelMaterial) { panelMaterial = $0 }
      if let description = Self.materials.first(where: { $0.0 == panelMaterial })?.2 {
        Text(description)
          .typeRole(.data)
          .foregroundStyle(theme.inkMid)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(Self.materialFootnote)
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .fixedSize(horizontal: false, vertical: true)
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

extension PanelMaterial {
  /// Read by the settings picker and by the app root that injects the material,
  /// so both always agree on where the choice lives.
  public static let storageKey = "io.github.novaisvictor.dailyweb.panelMaterial"
  public static let defaultValue: PanelMaterial = .liquidGlass
}
