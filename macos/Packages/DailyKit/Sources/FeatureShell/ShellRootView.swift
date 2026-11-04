import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The main window: sidebar, detail, toolbar and the ⌘K palette. It holds no store;
/// the app passes values in and receives intents through closures.
public struct ShellRootView<Accessory: View>: View {
  private let registry: ModuleRegistry
  private let enabledModules: [ModuleID]
  @Binding private var selection: AppRoute?
  private let account: ShellAccount
  private let accountActions: ShellAccountActions
  private let isRefreshing: Bool
  private let onRefresh: () -> Void
  private let paletteCommands: [PaletteCommand]
  private let onOpenInNewWindow: ((AppRoute) -> Void)?
  private let accessory: Accessory

  @State private var isPalettePresented = false
  @Environment(\.theme) private var theme

  /// - Parameters:
  ///   - onOpenInNewWindow: opens one entry in a window of its own; nil hides the option.
  ///   - accessory: trailing toolbar content, such as the notifications bell.
  public init(
    registry: ModuleRegistry,
    enabledModules: [ModuleID],
    selection: Binding<AppRoute?>,
    account: ShellAccount,
    accountActions: ShellAccountActions,
    isRefreshing: Bool,
    onRefresh: @escaping () -> Void,
    paletteCommands: [PaletteCommand],
    onOpenInNewWindow: ((AppRoute) -> Void)? = nil,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.registry = registry
    self.enabledModules = enabledModules
    _selection = selection
    self.account = account
    self.accountActions = accountActions
    self.isRefreshing = isRefreshing
    self.onRefresh = onRefresh
    self.paletteCommands = paletteCommands
    self.onOpenInNewWindow = onOpenInNewWindow
    self.accessory = accessory()
  }

  private var sidebar: SidebarModel { SidebarModel(registry: registry, enabled: enabledModules) }

  public var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        ForEach(sidebar.sections) { section in
          Section {
            ForEach(section.entries) { entry in
              Label(entry.title, systemImage: entry.systemImage)
                .tag(entry.route)
                .contextMenu {
                  if let onOpenInNewWindow {
                    Button("Abrir em nova janela") { onOpenInNewWindow(entry.route) }
                  }
                }
            }
          } header: {
            if let title = section.title { Text(title) }
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      detail
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Buscar", systemImage: "magnifyingglass") { isPalettePresented = true }
          .help("Buscar")
        RefreshButton(isRefreshing: isRefreshing, action: onRefresh)
        accessory
        AccountMenu(account: account, actions: accountActions)
      }
    }
    .sheet(isPresented: $isPalettePresented) {
      CommandPalette(commands: paletteCommands) { isPalettePresented = false }
    }
    .focusedSceneValue(\.shellMenu, menuActions)
    .onChange(of: enabledModules, initial: true) {
      let resolved = sidebar.resolvedSelection(selection)
      if resolved != selection { selection = resolved }
    }
  }

  /// The menu bar's "Ir", "Atualizar agora" and "Abrir em nova janela" act on this window.
  private var menuActions: ShellMenuActions {
    ShellMenuActions(
      items: ShellShortcuts.goMenuItems(sidebar.orderedEntries),
      selection: selection,
      isRefreshing: isRefreshing,
      select: { selection = $0 },
      openPalette: { isPalettePresented.toggle() },
      refresh: { if !isRefreshing { onRefresh() } },
      openInNewWindow: onOpenInNewWindow
    )
  }

  @ViewBuilder private var detail: some View {
    if let selection, let entry = sidebar.entry(for: selection) {
      entry.makeView()
    } else {
      ContentUnavailableView("Escolha uma tela na barra lateral", systemImage: "sidebar.left")
        .foregroundStyle(theme.inkMid)
    }
  }
}

/// Labels from `components/shell/HeaderNotifications.tsx`.
struct RefreshButton: View {
  let isRefreshing: Bool
  let action: () -> Void

  private var label: String { isRefreshing ? "Atualizando…" : "Atualizar agora" }

  var body: some View {
    Button(action: action) {
      if isRefreshing {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "arrow.clockwise")
      }
    }
    .disabled(isRefreshing)
    .help(label)
    .accessibilityLabel(label)
  }
}

#Preview("Shell") {
  @Previewable @State var selection: AppRoute? = .today
  ShellRootView(
    registry: PreviewData.registry,
    enabledModules: ModuleID.known,
    selection: $selection,
    account: PreviewData.account,
    accountActions: PreviewData.accountActions,
    isRefreshing: false,
    onRefresh: {},
    paletteCommands: PreviewData.paletteCommands
  ) {
    Button("Notificações", systemImage: "bell") {}
  }
  .frame(width: 900, height: 600)
}

#Preview("Shell atualizando, módulos desligados") {
  @Previewable @State var selection: AppRoute? = nil
  ShellRootView(
    registry: PreviewData.registry,
    enabledModules: [.tasks, .agenda],
    selection: $selection,
    account: PreviewData.account,
    accountActions: PreviewData.accountActions,
    isRefreshing: true,
    onRefresh: {},
    paletteCommands: []
  ) {
    EmptyView()
  }
  .frame(width: 900, height: 600)
}
