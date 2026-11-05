import DailyCore
import DailyDesign
import SwiftUI

extension EmailStore {
  /// The one store of the module, shared by the screen and the Início panel
  /// (spec 011 FR-011-10).
  static func shared(in environment: AppEnvironment) -> EmailStore {
    environment.featureStores.store("email") {
      EmailStore(
        client: environment.client, dashboard: environment.dashboard, navigator: environment.navigator,
        viewState: environment.viewState, notesEvents: environment.notesEvents)
    }
  }
}

/// The web's e-mail card on Início (`components/EmailPanel.tsx`): filters,
/// list and reader, without the folder tree. "Tela cheia" lays the tree, the
/// list and the reader over the window (`EmailPanel.tsx:1713-1737`). The host
/// draws the card and its padding.
public struct EmailPanel: View {
  @Environment(\.theme) private var theme
  @State private var store: EmailStore
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// `onOpenWindow` adds "Abrir em nova janela" to the header's "…" menu.
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    _store = State(initialValue: EmailStore.shared(in: environment))
    self.onOpenWindow = onOpenWindow
  }

  init(store: EmailStore, onOpenWindow: (() -> Void)? = nil) {
    _store = State(initialValue: store)
    self.onOpenWindow = onOpenWindow
  }

  public var body: some View {
    @Bindable var store = store
    Group {
      if store.isFullScreen {
        // The content lives in the full screen: a second copy here would load the
        // same folder twice and repeat the whole list for VoiceOver (`EmailPanel.tsx:1655-1662`).
        VStack(alignment: .leading, spacing: 12) {
          SectionHeader(store.folderTitle) {
            IconButton(toggle.buttonLabel, systemImage: toggle.systemImage) { toggle.toggle() }
          }
          Text("A caixa está aberta em tela cheia.")
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
          Spacer(minLength: 0)
        }
      } else {
        EmailListPane(store: store, fullScreen: toggle, onOpenWindow: onOpenWindow, padding: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .emailDialogs(store, isActive: !store.isFullScreen)
    .sheet(isPresented: $store.isFullScreen) {
      EmailFullScreen(store: store)
    }
  }

  private var toggle: EmailFullScreenToggle {
    EmailFullScreenToggle(isFullScreen: store.isFullScreen) { [store] in store.isFullScreen.toggle() }
  }
}

/// The "Tela cheia" / "Restaurar" pair of the header (`EmailPanel.tsx:1005-1012,1111-1116`).
struct EmailFullScreenToggle {
  let isFullScreen: Bool
  let toggle: () -> Void

  /// The header button's name: the web's `IconAction` label.
  var buttonLabel: String { isFullScreen ? "Restaurar" : "Abrir em tela cheia" }
  /// The "…" menu item.
  var menuLabel: String { isFullScreen ? "Restaurar" : "Tela cheia" }
  var systemImage: String {
    isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
  }
}

/// The header's "…" menu (`ações dos e-mails`, `EmailPanel.tsx:1013-1118`). In a
/// narrow pane it carries the batch actions and the filters the bar folds away.
struct EmailPaneMenu: View {
  @Environment(\.emailPresenter) private var presenter
  @Bindable var store: EmailStore
  let includesFilters: Bool
  let fullScreen: EmailFullScreenToggle?
  let onOpenWindow: (() -> Void)?

  var body: some View {
    if includesFilters {
      batchSection
      Section("Filtros") {
        Toggle("Só não lidos", isOn: $store.filters.onlyUnread)
      }
      if store.mailboxes.count > 1 {
        Picker("Caixa", selection: $store.filters.account) {
          Text("Todas").tag(String?.none)
          ForEach(store.mailboxes) { box in
            Text(box.label).tag(String?.some(box.id))
          }
        }
        .pickerStyle(.inline)
      }
      Picker("Ordenar", selection: $store.filters.sort) {
        ForEach(EmailSort.allCases) { sort in Text(sort.label).tag(sort) }
      }
      .pickerStyle(.inline)
      Picker("Agrupar", selection: $store.filters.groupBy) {
        ForEach(EmailGroupBy.allCases) { by in Text(by.label).tag(by) }
      }
      .pickerStyle(.inline)
    }
    if let fullScreen {
      Divider()
      Button(fullScreen.menuLabel, action: fullScreen.toggle)
    }
    if let onOpenWindow {
      Divider()
      Button("Abrir em nova janela", action: onOpenWindow)
    }
  }

  @ViewBuilder
  private var batchSection: some View {
    let count = store.selection.selected.count
    if count > 0 {
      Section {
        Text("\(count) \(count == 1 ? "conversa" : "conversas")")
        Button("Marcar lido") { Task { await store.runBatch(.read) } }
        Button("Marcar não lido") { Task { await store.runBatch(.unread) } }
        // As on the wide bar: with no known folders there is nowhere to move to.
        let folders = store.moveFolders
        if !folders.isEmpty {
          Menu("Mover para") {
            ForEach(folders, id: \.self) { folder in
              Button(folder) { Task { await store.runBatch(.move, folder: folder) } }
            }
          }
        }
        Button("Excluir", role: .destructive) { store.requestDeleteSelected(presenter: presenter) }
      }
      Divider()
    }
  }
}

/// The panel in full screen: the folder tree at 16rem, then the list with the
/// reader, up to 84rem wide (`EmailPanel.tsx:1713-1737`).
struct EmailFullScreen: View {
  @Environment(\.theme) private var theme
  @Bindable var store: EmailStore

  var body: some View {
    HStack(spacing: 0) {
      ScrollView {
        EmailFolderTree(store: store)
          .padding(12)
      }
      .frame(width: 256)
      .overlay(alignment: .trailing) {
        Rectangle().fill(theme.lineSoft).frame(width: 1)
      }
      EmailListPane(
        store: store,
        fullScreen: EmailFullScreenToggle(isFullScreen: true) { store.isFullScreen = false }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 760, idealWidth: 1344, maxWidth: 1344, minHeight: 520, idealHeight: 860)
    .presentationSizing(.fitted)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("E-mail em tela cheia. Esc volta ao painel.")
    // The tree is only fetched here: the card does not need it (`EmailPanel.tsx:374-376`).
    .task(id: store.mailboxes.map(\.id)) { await store.loadMailboxes() }
    // The list takes Esc first to clear a selection; then the open message
    // closes, and then the full screen.
    .onExitCommand {
      if store.openKey != nil {
        store.closeMessage()
      } else {
        store.isFullScreen = false
      }
    }
    .emailDialogs(store, isActive: true)
  }
}

#Preview("Painel de e-mail, 420pt") {
  EmailPanel(store: EmailPreview.store(), onOpenWindow: {})
    .padding(18)
    .frame(width: 420, height: 560)
}

#Preview("Painel de e-mail, 700pt") {
  EmailPanel(store: EmailPreview.store(), onOpenWindow: {})
    .padding(18)
    .frame(width: 700, height: 560)
}

#Preview("E-mail em tela cheia") {
  EmailFullScreen(store: EmailPreview.store())
    .frame(width: 1100, height: 700)
}
