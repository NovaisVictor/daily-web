import SwiftUI

/// The pill controls and list rows of spec 013 (FR-013-05 to 08) on one page, for the
/// visual check beside the web. Sample data only.
public struct ControlsGallery: View {
  private let scheme: ColorScheme
  private let backdrop: Backdrop
  private let density: Density

  public init(scheme: ColorScheme, backdrop: Backdrop, density: Density = .comfortable) {
    self.scheme = scheme
    self.backdrop = backdrop
    self.density = density
  }

  public var body: some View {
    ControlsGalleryContent()
      .background { BackdropView(backdrop) }
      .environment(\.theme, Theme.resolve(scheme: scheme, backdrop: backdrop, density: density))
      .environment(\.colorScheme, scheme)
  }
}

private enum PanelTab: Hashable { case abertos, revisao, entregues }
private enum TaskView: Hashable { case lista, quadro }

private struct ControlsGalleryContent: View {
  @Environment(\.theme) private var theme
  @State private var tab = PanelTab.abertos
  @State private var view = TaskView.lista
  @State private var unreadOnly = true
  @State private var selectedFolder = 1

  private let rows = [
    ("PROJ-101", "Ajustar o filtro de sprint"),
    ("PROJ-102", "Corrigir a ordenação por prioridade"),
    ("PROJ-103", "Revisar a tela de login"),
    ("PROJ-104", "Atualizar as dependências"),
  ]
  private let folders = [("Entrada", 12), ("Enviados", 0), ("Arquivo", 3), ("Lixeira", 0)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        card("Botões") {
          ForEach(PillButtonSize.allCases, id: \.self) { size in
            HStack(spacing: 12) {
              Button("Entrar") {}.pillButtonStyle(.primary, size: size, glow: true)
              Button("Salvar", systemImage: "checkmark") {}.pillButtonStyle(.primary, size: size)
              Button("Cancelar") {}.pillButtonStyle(.outline, size: size)
              Button("Limpar") {}.pillButtonStyle(.ghost, size: size)
              Button("Excluir", systemImage: "trash") {}.pillButtonStyle(.destructive, size: size)
              Button("Desativado") {}.pillButtonStyle(.primary, size: size).disabled(true)
            }
          }
          HStack(spacing: 12) {
            ForEach(IconButtonSize.allCases, id: \.self) { size in
              IconButton("Arquivar", systemImage: "archivebox", size: size) {}
            }
            IconButton("Mais ações", systemImage: "ellipsis", size: .small, isActive: true) {}
            IconButton("Ordenar: Prioridade", systemImage: "arrow.up.arrow.down", variant: .outline) {}
          }
        }
        card("Abas e filtros") {
          SegmentedPills(
            "Pull requests",
            items: [
              .init(id: PanelTab.abertos, label: "Abertos", count: 4),
              .init(id: .revisao, label: "Em revisão", count: 0),
              .init(id: .entregues, label: "Entregues", count: 2),
            ],
            selection: $tab
          )
          SegmentedPills(
            "Visualização",
            items: [.init(id: TaskView.lista, label: "Lista"), .init(id: .quadro, label: "Quadro")],
            selection: $view,
            style: .toggle
          )
          FilterBar("Filtros do e-mail") {
            Chip("Não lidos", isOn: unreadOnly) { unreadOnly.toggle() }
            Chip("Com anexo", isOn: false) {}
            Chip("Indisponível", isOn: false, isDisabled: true) {}
          }
          HStack(spacing: 8) {
            RepoPill("acme/daily-web") {}
            RepoPill("acme/api") {}
          }
        }
        card("Linhas") {
          VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
              ListRow(index: index, isLast: index == rows.count - 1, isActive: index == 2) {
                HStack(spacing: 12) {
                  Text(row.0).font(.system(size: 14).monospacedDigit()).foregroundStyle(theme.inkDim)
                  Text(row.1).font(.system(size: 14)).foregroundStyle(theme.ink)
                  Spacer(minLength: 0)
                  IconButton("Abrir no Jira", systemImage: "arrow.up.right", size: .small) {}
                }
              }
            }
          }
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
              HStack(spacing: 4) {
                Text(folder.0).font(.system(size: 14))
                Spacer(minLength: 0)
                CountSlot(folder.1)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .activeRow(index == selectedFolder)
              .onTapGesture { selectedFolder = index }
            }
          }
          .frame(width: 240)
        }
      }
      .padding(24)
    }
  }

  private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      SectionHeader(title, compact: true)
      content()
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.surface2.opacity(0.7), in: .rect(cornerRadius: Radius.extraLarge))
    .overlay { RoundedRectangle(cornerRadius: Radius.extraLarge).strokeBorder(theme.line) }
  }
}

#Preview("Controles · Claro · mesh") {
  ControlsGallery(scheme: .light, backdrop: .mesh).frame(width: 900, height: 900)
}
#Preview("Controles · Claro · Catppuccin") {
  ControlsGallery(scheme: .light, backdrop: .catppuccin).frame(width: 900, height: 900)
}
#Preview("Controles · Claro · Dracula") {
  ControlsGallery(scheme: .light, backdrop: .dracula).frame(width: 900, height: 900)
}
#Preview("Controles · Claro · WezTerm") {
  ControlsGallery(scheme: .light, backdrop: .wezterm).frame(width: 900, height: 900)
}
#Preview("Controles · Escuro · mesh") {
  ControlsGallery(scheme: .dark, backdrop: .mesh).frame(width: 900, height: 900)
}
#Preview("Controles · Escuro · Catppuccin") {
  ControlsGallery(scheme: .dark, backdrop: .catppuccin).frame(width: 900, height: 900)
}
#Preview("Controles · Escuro · Dracula") {
  ControlsGallery(scheme: .dark, backdrop: .dracula).frame(width: 900, height: 900)
}
#Preview("Controles · Escuro · WezTerm") {
  ControlsGallery(scheme: .dark, backdrop: .wezterm).frame(width: 900, height: 900)
}
#Preview("Controles · Compacto") {
  ControlsGallery(scheme: .light, backdrop: .mesh, density: .compact).frame(width: 900, height: 900)
}
