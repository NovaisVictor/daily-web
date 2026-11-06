import SwiftUI

/// Every DailyDesign component on one page, for a given scheme, backdrop and density.
/// Sample data only; nothing here touches the network.
public struct DesignGallery: View {
  private let scheme: ColorScheme
  private let backdrop: Backdrop
  private let density: Density

  public init(scheme: ColorScheme, backdrop: Backdrop, density: Density = .comfortable) {
    self.scheme = scheme
    self.backdrop = backdrop
    self.density = density
  }

  public var body: some View {
    let theme = Theme.resolve(scheme: scheme, backdrop: backdrop, density: density)
    VStack(spacing: 0) {
      SegmentedPills("Galeria", items: GalleryPage.items, selection: $page)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
      switch page {
      case .components: GalleryContent()
      case .controls: ControlsGallery(scheme: scheme, backdrop: backdrop, density: density)
      case .glass: GlassGallery(scheme: scheme, backdrop: backdrop)
      case .fonts: FontsGallery()
      }
    }
    .background { BackdropView(backdrop) }
    .environment(\.theme, theme)
    .environment(\.colorScheme, scheme)
  }

  @State private var page = GalleryPage.components
}

/// The pages of the gallery: the first components, then the spec 013 controls, glass
/// surfaces and type faces, each with its own sample page.
private enum GalleryPage: Hashable, CaseIterable {
  case components, controls, glass, fonts

  static let items: [SegmentedPills<GalleryPage>.Item] = [
    .init(id: .components, label: "Componentes"),
    .init(id: .controls, label: "Controles"),
    .init(id: .glass, label: "Vidro"),
    .init(id: .fonts, label: "Fontes"),
  ]
}

private struct GalleryContent: View {
  @Environment(\.theme) private var theme
  @State private var search = ""
  @State private var range = 7
  @State private var confirm: ConfirmRequest?
  @State private var toasts: [ToastMessage] = [
    ToastMessage(kind: .success, text: "Tarefa concluída", action: .init(title: "Desfazer") {}),
    ToastMessage(kind: .error, text: "Falha ao salvar"),
    ToastMessage(kind: .info, text: "Sincronizado agora"),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        typeScale
        swatches
        card {
          SectionHeader("Agenda", count: "12") {
            Button("Atualizar") {}.pillButtonStyle(.outline, size: .small)
          }
          FilterBar("Período da agenda") {
            ForEach([1, 7, 14, 30], id: \.self) { days in
              Chip("\(days) dias", isOn: range == days) { range = days }
            }
            Chip("Indisponível", isOn: false, isDisabled: true) {}
            SearchField(text: $search, label: "Buscar eventos")
          }
          HStack(spacing: 8) {
            ForEach(BadgeStyle.allCases, id: \.self) { Badge($0.rawValue, style: $0) }
          }
          HStack(spacing: 12) {
            StatusPill("Ativo", glyph: .live, tone: .success)
            StatusPill("Pendente", glyph: .idle, tone: .neutral, note: "há 2 dias")
            StatusPill("Em revisão", glyph: .moving, tone: .info)
            StatusPill("Atrasado", glyph: .moving, tone: .warning)
            StatusPill("Erro", glyph: .alert, tone: .destructive)
            StatusDot(.success)
          }
          HStack(spacing: 8) {
            Avatar(name: "Ana Souza")
            Avatar(name: "Victor", size: 40)
            Avatar(name: "Maria da Silva Lima", imageData: Data([0x00]), size: 24)
          }
          PanelError("Não foi possível carregar o Jira. Mostrando o que já chegou.")
          FocusDropTarget("Solte aqui para agendar um bloco de foco", for: String.self) { _ in }
          Button("Excluir tarefa…") {
            confirm = ConfirmRequest(
              title: "Excluir tarefa?",
              message: "Esta ação não pode ser desfeita.",
              confirmLabel: "Excluir",
              destructive: true,
              onConfirm: {}
            )
          }
          .pillButtonStyle(.destructive, size: .small)
        }
        card {
          EmptyState("Nenhuma tarefa", description: "Crie a primeira para começar.", systemImage: "checklist") {
            Button("Nova tarefa") {}.pillButtonStyle(.primary)
          }
          ErrorState("Falha ao carregar", description: "O servidor não respondeu.", retry: {})
          LoadingState()
        }
        card {
          ConfirmDialogView(
            request: ConfirmRequest(title: "Excluir nota?", destructive: true, onConfirm: {}),
            confirm: {},
            cancel: {}
          )
          ForEach(toasts) { toast in
            ToastView(toast) { toasts.removeAll { $0.id == toast.id } }
          }
        }
      }
      .padding(24)
    }
    .confirmDialog($confirm)
  }

  private var typeScale: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(TypeRole.allCases, id: \.self) { role in
        Text("\(role.rawValue) 1234").typeRole(role).foregroundStyle(theme.ink)
      }
    }
  }

  private var swatches: some View {
    let colors: [(String, Color)] = [
      ("surface0", theme.surface0), ("surface1", theme.surface1), ("surface2", theme.surface2),
      ("surface3", theme.surface3), ("brand", theme.brand), ("success", theme.success),
      ("warning", theme.warning), ("danger", theme.danger), ("info", theme.info),
    ]
    return VStack(alignment: .leading, spacing: 8) {
      FlowLayout(spacing: 6) {
        ForEach(colors, id: \.0) { name, color in
          Text(name)
            .font(.daily(size: 11))
            .foregroundStyle(theme.inkMid)
            .frame(width: 72, height: 40, alignment: .bottomLeading)
            .padding(4)
            .background(color, in: .rect(cornerRadius: Radius.small))
            .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.line) }
        }
      }
      FlowLayout(spacing: 6) {
        ForEach(PostitPaper.allCases, id: \.self) { paper in
          if let color = theme.postit[paper.rawValue] {
            Text(paper.rawValue)
              .font(.daily(size: 12, weight: .medium))
              .foregroundStyle(theme.postitInk)
              .frame(width: 72, height: 56)
              .background(color, in: .rect(cornerRadius: Radius.hairline))
          }
        }
      }
    }
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16, content: content)
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.surface2.opacity(0.7), in: .rect(cornerRadius: Radius.extraLarge))
      .overlay { RoundedRectangle(cornerRadius: Radius.extraLarge).strokeBorder(theme.line) }
  }
}

#Preview("Claro · mesh") { DesignGallery(scheme: .light, backdrop: .mesh).frame(width: 900, height: 1100) }
#Preview("Claro · Catppuccin") {
  DesignGallery(scheme: .light, backdrop: .catppuccin).frame(width: 900, height: 1100)
}
#Preview("Claro · Dracula") { DesignGallery(scheme: .light, backdrop: .dracula).frame(width: 900, height: 1100) }
#Preview("Claro · WezTerm") { DesignGallery(scheme: .light, backdrop: .wezterm).frame(width: 900, height: 1100) }
#Preview("Escuro · mesh") { DesignGallery(scheme: .dark, backdrop: .mesh).frame(width: 900, height: 1100) }
#Preview("Escuro · Catppuccin") {
  DesignGallery(scheme: .dark, backdrop: .catppuccin).frame(width: 900, height: 1100)
}
#Preview("Escuro · Dracula") { DesignGallery(scheme: .dark, backdrop: .dracula).frame(width: 900, height: 1100) }
#Preview("Escuro · WezTerm") { DesignGallery(scheme: .dark, backdrop: .wezterm).frame(width: 900, height: 1100) }
#Preview("Compacto") {
  DesignGallery(scheme: .light, backdrop: .mesh, density: .compact).frame(width: 900, height: 1100)
}
#Preview("Toasts") {
  ToastStack(
    [
      ToastMessage(kind: .success, text: "Nota salva"),
      ToastMessage(kind: .error, text: "Falha ao mover a nota", action: .init(title: "Tentar de novo") {}),
    ],
    dismiss: { _ in }
  )
  .frame(width: 500, height: 300)
}
