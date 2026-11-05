import SwiftUI

/// Every glass role and every elevation over one backdrop and scheme, for the visual
/// check of spec 013 (SC-013-2). Sample content only.
struct GlassGallery: View {
  let scheme: ColorScheme
  let backdrop: Backdrop

  var body: some View {
    GlassGalleryContent()
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background { BackdropView(backdrop) }
      .environment(\.theme, Theme.resolve(scheme: scheme, backdrop: backdrop, density: .comfortable))
      .environment(\.colorScheme, scheme)
  }
}

private struct GlassGalleryContent: View {
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack(alignment: .top, spacing: 24) {
        sample("panel", detail: "Painel do Início · e2")
          .frame(width: 240, height: 120, alignment: .topLeading)
          .glassSurface(.panel)
        sample("popover", detail: "Menu, sino, paleta · e4")
          .frame(width: 220, height: 120, alignment: .topLeading)
          .glassSurface(.popover)
      }
      sample("bar", detail: "Barra de ferramentas · e2")
        .frame(maxWidth: 480, alignment: .leading)
        .glassSurface(.bar)
      GlassGroup(spacing: 8) {
        HStack(spacing: 8) {
          ForEach(["Hoje", "7 dias", "30 dias"], id: \.self) { label in
            Button(label) {}
              .buttonStyle(.plain)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(theme.ink)
              .padding(.horizontal, 14)
              .padding(.vertical, 6)
              .glassSurface(.pill)
          }
        }
      }
      HStack(spacing: 20) {
        ForEach(Elevation.allCases, id: \.self) { level in
          Text("e\(level.rawValue)")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.ink)
            .frame(width: 72, height: 56)
            .background(theme.surface2, in: .rect(cornerRadius: Radius.medium))
            .elevation(level)
        }
      }
    }
  }

  private func sample(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(theme.ink)
      Text(detail)
        .font(.system(size: 13))
        .foregroundStyle(theme.inkMid)
    }
    .padding(16)
  }
}

#Preview("Vidro · claro · mesh") { GlassGallery(scheme: .light, backdrop: .mesh).frame(width: 640, height: 520) }
#Preview("Vidro · claro · Catppuccin") {
  GlassGallery(scheme: .light, backdrop: .catppuccin).frame(width: 640, height: 520)
}
#Preview("Vidro · claro · Dracula") { GlassGallery(scheme: .light, backdrop: .dracula).frame(width: 640, height: 520) }
#Preview("Vidro · claro · WezTerm") { GlassGallery(scheme: .light, backdrop: .wezterm).frame(width: 640, height: 520) }
#Preview("Vidro · escuro · mesh") { GlassGallery(scheme: .dark, backdrop: .mesh).frame(width: 640, height: 520) }
#Preview("Vidro · escuro · Catppuccin") {
  GlassGallery(scheme: .dark, backdrop: .catppuccin).frame(width: 640, height: 520)
}
#Preview("Vidro · escuro · Dracula") { GlassGallery(scheme: .dark, backdrop: .dracula).frame(width: 640, height: 520) }
#Preview("Vidro · escuro · WezTerm") { GlassGallery(scheme: .dark, backdrop: .wezterm).frame(width: 640, height: 520) }
