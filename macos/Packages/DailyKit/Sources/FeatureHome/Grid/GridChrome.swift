import AppKit
import DailyDesign
import DailyModels
import SwiftUI

/// Names and symbols of the modules on Início.
nonisolated enum HomeModuleInfo {
  /// The tab titles (`WorkspaceHome.tsx:16-24`).
  static func tabTitle(_ module: ModuleID) -> String {
    switch module {
    case .email: "E-mail"
    case .tasks: "Tarefas"
    case .notes: "Notas"
    case .agenda: "Agenda"
    case .jira: "Jira"
    case .pulls: "GitHub"
    case .slack: "Slack"
    default: module.rawValue
    }
  }

  /// The narrow bar's labels, `MODULES[id].label` (`lib/modules.ts`).
  static func label(_ module: ModuleID) -> String {
    switch module {
    case .email: "E-mail"
    case .tasks: "Tarefas"
    case .notes: "Notas rápidas"
    case .agenda: "Agenda"
    case .jira: "Jira"
    case .pulls: "Pull requests"
    case .slack: "Slack"
    default: module.rawValue
    }
  }

  /// SF Symbols standing in for `MODULE_ICON` (`MobileModuleNav.tsx:21-29`).
  static func systemImage(_ module: ModuleID) -> String {
    switch module {
    case .email: "envelope"
    case .tasks: "checklist"
    case .notes: "square.and.pencil"
    case .agenda: "calendar"
    case .jira: "rectangle.split.3x1"
    case .pulls: "arrow.triangle.pull"
    case .slack: "message"
    default: "square.grid.2x2"
    }
  }
}

/// The floating bar of the arrange mode (`DashboardGrid.tsx:359-382`).
struct GridArrangeBar: View {
  @Environment(\.theme) private var theme
  let windowSize: CGSize
  let isSaving: Bool
  let save: () -> Void
  let discard: () -> Void

  static func message(for size: CGSize) -> String {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    return "Arraste para mover, puxe o canto para redimensionar. Salvar guarda para \(width) × \(height)."
  }

  var body: some View {
    HStack(spacing: 12) {
      Text(Self.message(for: windowSize))
        .typeRole(.data)
        .foregroundStyle(theme.inkMid)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityAddTraits(.updatesFrequently)
      HStack(spacing: 8) {
        Button(isSaving ? "Salvando…" : "Salvar para esta tela", action: save)
          .pillButtonStyle(.primary, size: .small)
          .disabled(isSaving)
        // Esc leaves the mode the way "Descartar" does.
        IconButton("Descartar", systemImage: "xmark", variant: .outline, action: discard)
          .keyboardShortcut(.cancelAction)
      }
      .fixedSize()
    }
    .padding(.leading, 20)
    .padding(.trailing, 8)
    .padding(.vertical, 8)
    .glassSurface(.pill, elevation: .e4)
    .padding(.horizontal, 16)
    .padding(.bottom, 24)
  }
}

/// The narrow grid's module bar (`components/MobileModuleNav.tsx`).
struct GridModuleBar: View {
  @Environment(\.theme) private var theme
  let modules: [ModuleID]
  let active: ModuleID?
  let select: (ModuleID) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(modules, id: \.self) { module in
        item(module)
      }
    }
    .padding(.horizontal, 8)
    .glassSurface(.bar, elevation: .e4)
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("módulos")
  }

  private func item(_ module: ModuleID) -> some View {
    let selected = module == active
    let label = HomeModuleInfo.label(module)
    return Button {
      select(module)
    } label: {
      VStack(spacing: 4) {
        Image(systemName: HomeModuleInfo.systemImage(module))
          .font(.system(size: 18))
        Text(label)
          .typeRole(.caption)
          .lineLimit(1)
      }
      .foregroundStyle(selected ? theme.brand : theme.inkDim)
      .frame(maxWidth: .infinity, minHeight: 52)
      .overlay(alignment: .top) {
        if selected {
          Capsule()
            .fill(theme.brand)
            .frame(width: 24, height: 2)
            .padding(.top, 4)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// The narrow grid: one module at a time. The others stay in the hierarchy,
/// hidden, so their unsaved edits survive (`DashboardGrid.tsx:330-333`).
struct NarrowDashboardView: View {
  let modules: [ModuleID]
  let active: ModuleID?
  /// Panels scroll inside, so each gets a bounded height.
  let panelHeight: CGFloat
  let panel: (ModuleID) -> AnyView

  var body: some View {
    if NarrowDashboard.showsBar(modules: modules) {
      ZStack(alignment: .top) {
        ForEach(modules, id: \.self) { module in
          let shown = module == active
          card(module)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .zIndex(shown ? 1 : 0)
        }
      }
    } else {
      VStack(spacing: 16) {
        ForEach(modules, id: \.self) { module in
          card(module)
        }
      }
    }
  }

  private func card(_ module: ModuleID) -> some View {
    panel(module)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: panelHeight, alignment: .top)
      .clipShape(.rect(cornerRadius: Radius.medium))
      .glassSurface(.panel)
  }
}

/// Reports the window's content size, the native `window.innerWidth/innerHeight`:
/// the grid layout is chosen and saved per window size, as on the web.
struct WindowSizeReader: NSViewRepresentable {
  let onChange: @MainActor @Sendable (CGSize) -> Void

  func makeNSView(context: Context) -> ReaderView {
    let view = ReaderView()
    view.onChange = onChange
    return view
  }

  func updateNSView(_ view: ReaderView, context: Context) {
    view.onChange = onChange
  }

  final class ReaderView: NSView {
    var onChange: (@MainActor @Sendable (CGSize) -> Void)?
    private var reported: CGSize?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      report()
    }

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      report()
    }

    override func layout() {
      super.layout()
      report()
    }

    private func report() {
      guard let window, let onChange else { return }
      let size = window.contentRect(forFrameRect: window.frame).size
      guard size != reported else { return }
      reported = size
      // Not during layout: SwiftUI rejects state changes made while it lays out.
      Task { onChange(size) }
    }
  }
}
