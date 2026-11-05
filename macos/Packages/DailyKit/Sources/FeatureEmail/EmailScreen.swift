import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The e-mail module: the folder tree beside the conversation list, as the
/// web's full-screen e-mail (`components/EmailPanel.tsx`).
public struct EmailScreen: View {
  @State private var store: EmailStore
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow

  public init(environment: AppEnvironment) {
    _store = State(initialValue: EmailStore.shared(in: environment))
  }

  init(store: EmailStore) {
    _store = State(initialValue: store)
  }

  public var body: some View {
    @Bindable var store = store
    HSplitView {
      ScrollView {
        EmailFolderTree(store: store)
          .padding(12)
      }
      .frame(minWidth: 200, idealWidth: 256, maxWidth: 340)
      EmailListPane(store: store)
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
    }
    // The web's full-screen e-mail is one card holding both panes
    // (`EmailPanel.tsx:1715-1736`); here that card is a glass panel.
    .clipShape(.rect(cornerRadius: Radius.medium))
    .glassSurface(.panel)
    .padding(16)
    .task(id: store.mailboxes.map(\.id)) { await store.loadMailboxes() }
    // A clicked notification: shown now, or once the inbox arrives.
    .task { revealPending() }
    .onChange(of: store.pendingItemID) { revealPending() }
    .onChange(of: store.inbox.data) { revealPending() }
    // Esc closes the open message from any pane, as the web's window listener
    // (`EmailPanel.tsx:1765-1771`); the list handles it first to clear a selection.
    .onExitCommand {
      if store.openKey != nil { store.closeMessage() }
    }
    // While the panel's full screen is open, its sheet owns the dialogs.
    .emailDialogs(store, isActive: !store.isFullScreen)
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  private func revealPending() {
    guard isPrimaryWindow else { return }
    store.revealPending()
  }
}

/// The header, filters, notices and the conversation list. Under 34rem the
/// chips, selects and batch buttons fold into the "…" menu, as the web does
/// under `lg` (`EmailPanel.tsx:949,1019,1135`).
struct EmailListPane: View {
  @Environment(\.theme) private var theme
  @Bindable var store: EmailStore
  /// "Abrir em tela cheia" / "Restaurar"; nil where there is no such mode.
  var fullScreen: EmailFullScreenToggle?
  var onOpenWindow: (() -> Void)?
  var padding: CGFloat = 16
  @State private var isNarrow = false

  /// `34rem`: where the filter bar stops fitting one line beside the search.
  nonisolated static let narrowWidth: CGFloat = 544

  var body: some View {
    let listing = store.listing
    let active = store.filters.active(mailboxes: store.mailboxes)
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(
        store.folderTitle,
        count: active.isEmpty ? nil : "\(listing.visible.count) de \(listing.all.count)"
      ) {
        headerActions
      }
      filterBar
      activeFilters(active)
      notices
      if store.dragging != nil, !store.selection.selected.isEmpty {
        EmailActionDropTargets(store: store, count: store.selection.selected.count)
      }
      content(listing)
    }
    .padding(padding)
    .onGeometryChange(for: Bool.self) { proxy in
      proxy.size.width < Self.narrowWidth
    } action: { narrow in
      isNarrow = narrow
    }
    .onChange(of: listing.order) {
      store.syncSelection()
      store.restoreOpenMessage()
    }
    // What the last launch left open (spec 015 FR-015-01).
    .task {
      await store.loadRestoredFolder()
      store.restoreOpenMessage()
    }
  }

  @ViewBuilder
  private var headerActions: some View {
    HStack(spacing: 8) {
      if isNarrow {
        let count = store.selection.selected.count
        if count > 0 {
          Text("\(count) \(count == 1 ? "conversa" : "conversas")")
            .font(.daily(size: 14).monospacedDigit())
            .foregroundStyle(theme.inkDim)
        }
      } else {
        EmailBatchBar(store: store)
        if let fullScreen {
          IconButton(fullScreen.buttonLabel, systemImage: fullScreen.systemImage) { fullScreen.toggle() }
        }
      }
      if isNarrow || onOpenWindow != nil {
        IconMenu("ações dos e-mails", systemImage: "ellipsis") {
          EmailPaneMenu(
            store: store, includesFilters: isNarrow, fullScreen: isNarrow ? fullScreen : nil,
            onOpenWindow: onOpenWindow)
        }
      }
    }
  }

  private var filterBar: some View {
    FilterBar("Filtrar e-mails") {
      SearchField(text: $store.filters.query, label: "buscar e-mails", placeholder: "assunto ou remetente")
      if !isNarrow {
        Chip("Não lidos", isOn: store.filters.onlyUnread) { store.filters.onlyUnread.toggle() }
        // One box needs no box filter.
        if store.mailboxes.count > 1 {
          ForEach(store.mailboxes) { box in
            Chip(box.label, isOn: store.filters.account == box.id) {
              store.filters.account = store.filters.account == box.id ? nil : box.id
            }
          }
        }
        PillSelect(
          label: "ordenar e-mails", selection: $store.filters.sort, options: EmailSort.allCases, title: \.label)
        PillSelect(
          label: "agrupar e-mails", selection: $store.filters.groupBy, options: EmailGroupBy.allCases,
          title: \.optionLabel)
      }
    }
  }

  @ViewBuilder
  private func activeFilters(_ active: [EmailFilters.Active]) -> some View {
    if !active.isEmpty {
      FlowLayout(spacing: 8) {
        ForEach(active) { filter in
          HStack(spacing: 4) {
            Text(filter.label).typeRole(.caption)
            IconButton("remover filtro \(filter.label)", systemImage: "xmark", size: .extraSmall) {
              store.clearFilter(filter.kind)
            }
          }
          .padding(.leading, 8)
          .padding(.trailing, 2)
          .padding(.vertical, 1)
          .background(theme.neutralTint, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.lineStrong) }
        }
        if active.count > 1 {
          Button("Limpar tudo", systemImage: "xmark") { store.clearAllFilters() }
            .pillButtonStyle(.ghost, size: .small)
        }
      }
    }
  }

  @ViewBuilder
  private var notices: some View {
    if store.folder == nil, let error = store.inbox.error {
      PanelError(error)
    }
    if let error = store.folderError {
      HStack(alignment: .firstTextBaseline) {
        PanelError(error)
        Button("tentar de novo") { Task { await store.loadFolder() } }
          .linkButtonStyle()
      }
    }
    if let error = store.batchError {
      PanelError(error)
    }
    if let created = store.created {
      EmailCreatedNotice(created: created) {
        store.openCreated()
      } onDismiss: {
        store.dismissCreated()
      }
    }
    if !store.unprocessed.isEmpty {
      HStack(alignment: .firstTextBaseline) {
        PanelError(unprocessedText)
        Button("tentar de novo") { Task { await store.retryUnprocessed() } }
          .linkButtonStyle()
      }
    }
  }

  private var unprocessedText: String {
    let lead =
      store.unprocessed.count == 1
      ? "Uma mensagem não foi processada: " : "\(store.unprocessed.count) mensagens não foram processadas: "
    let items = store.unprocessed.map { result in
      let subject = "“\(store.subject(account: result.account, id: result.id))”"
      return result.error.map { "\(subject) (\($0))" } ?? subject
    }
    return lead + items.joined(separator: "; ") + "."
  }

  @ViewBuilder
  private func content(_ listing: EmailListing) -> some View {
    let loading = store.folder == nil ? store.dashboard.state == nil : store.folderLoading
    if loading && listing.all.isEmpty {
      LoadingState()
    } else if store.folder != nil && store.folderError == nil && listing.all.isEmpty {
      // An empty folder is not a clean inbox: there is nothing to clean there.
      EmptyState("Nenhum e-mail nesta pasta.")
    } else if store.folder == nil && listing.all.isEmpty && store.inbox.error == nil {
      EmptyState("Caixa de entrada limpa.")
    } else if !listing.all.isEmpty && listing.visible.isEmpty {
      EmptyState("Nenhum e-mail com esses filtros.")
    } else if !listing.threads.isEmpty {
      EmailConversationList(store: store, listing: listing)
    } else {
      Spacer(minLength: 0)
    }
  }
}

/// "Nota criada a partir de …" with the way to what was created
/// (`EmailPanel.tsx:1191-1212`). Inline, as on the web: a toast would vanish
/// before the person decides to open it.
struct EmailCreatedNotice: View {
  @Environment(\.theme) private var theme
  let created: CreatedFromEmail
  let onOpen: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    let isNote = created.kind == .note
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(isNote ? "Nota criada" : "Tarefa criada") a partir de “\(created.title)”.")
        .fixedSize(horizontal: false, vertical: true)
      Button(isNote ? "Abrir a nota" : "Abrir tarefas", action: onOpen)
        .linkButtonStyle()
      Spacer(minLength: 8)
      Button("dispensar", action: onDismiss)
        .linkButtonStyle()
        .foregroundStyle(theme.inkDim)
    }
    .font(.daily(size: 14))
    .foregroundStyle(theme.brand)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.brandTint, in: .rect(cornerRadius: Radius.small))
    .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.brandEdge) }
    .accessibilityElement(children: .contain)
  }
}

/// The batch actions for the selection (`acoesEmLote`).
struct EmailBatchBar: View {
  @Environment(\.theme) private var theme
  @Bindable var store: EmailStore
  @Environment(\.emailPresenter) private var presenter

  var body: some View {
    let count = store.selection.selected.count
    if count > 0 {
      HStack(spacing: 8) {
        Text("\(count) \(count == 1 ? "conversa" : "conversas")")
          .font(.daily(size: 14).monospacedDigit())
          .foregroundStyle(theme.inkDim)
        // The only hint that E and M exist.
        HStack(spacing: 4) {
          ShortcutKey("E")
          Text("excluir")
          ShortcutKey("M")
          Text("mover")
        }
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        IconButton("Marcar lido", systemImage: "envelope.open", variant: .outline) {
          Task { await store.runBatch(.read) }
        }
        IconButton("Marcar não lido", systemImage: "envelope.badge", variant: .outline) {
          Task { await store.runBatch(.unread) }
        }
        let folders = store.moveFolders
        if !folders.isEmpty {
          PillSelect(
            label: "pasta de destino",
            selection: Binding(get: { store.effectiveTargetFolder }, set: { store.targetFolder = $0 }),
            options: folders, title: { $0 })
          IconButton("Mover", systemImage: "folder", variant: .outline) {
            Task { await store.runBatch(.move, folder: store.effectiveTargetFolder) }
          }
        }
        // The web fills this one (`IconAction variant="destructive"`, EmailPanel.tsx:993-998);
        // the app keeps one destructive glyph button, the danger-on-hover circle of the rows.
        IconButton("Excluir", systemImage: "trash", variant: .destructive) {
          store.requestDeleteSelected(presenter: presenter)
        }
      }
    }
  }
}

/// M asks where to move: moving takes the message out of its folder
/// (`moverAberto` dialog in `EmailPanel.tsx`).
struct EmailMoveSheet: View {
  @Bindable var store: EmailStore

  var body: some View {
    let count = store.selectedTargets.count
    VStack(alignment: .leading, spacing: 16) {
      Text(count == 1 ? "Mover este e-mail para:" : "Mover estes \(count) e-mails para:")
        .typeRole(.subhead)
      PillSelect(
        label: "pasta de destino do atalho M",
        selection: Binding(get: { store.effectiveTargetFolder }, set: { store.targetFolder = $0 }),
        options: store.moveFolders, title: { $0 })
      HStack {
        Spacer()
        Button {
          store.isMoveSheetPresented = false
        } label: {
          HStack(spacing: 6) {
            Text("Cancelar")
            ShortcutKey("Esc")
          }
        }
        .pillButtonStyle(.outline)
        .keyboardShortcut(.cancelAction)
        Button {
          Task { await store.confirmMoveSelected() }
        } label: {
          HStack(spacing: 6) {
            Text("Mover")
            ShortcutKey("Enter")
          }
        }
        .pillButtonStyle(.primary)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

extension View {
  /// The delete confirmation and the M move sheet. Only one presenter may own
  /// them at a time: a second sheet on the same window would be refused, and
  /// another window would show a question nobody asked there.
  func emailDialogs(_ store: EmailStore, isActive: Bool) -> some View {
    modifier(EmailDialogs(store: store, isActive: isActive))
  }
}

extension EnvironmentValues {
  /// The `emailDialogs` host a control sits in; the control passes it with its
  /// request so only that host presents the answer.
  @Entry var emailPresenter: UUID? = nil
}

private struct EmailDialogs: ViewModifier {
  @Bindable var store: EmailStore
  let isActive: Bool
  @State private var presenter = UUID()

  func body(content: Content) -> some View {
    let owns = isActive && store.presentsDialogs(presenter)
    content
      .environment(\.emailPresenter, presenter)
      .confirmDialog(owns ? $store.confirmation : .constant(nil))
      .sheet(isPresented: owns ? $store.isMoveSheetPresented : .constant(false)) {
        EmailMoveSheet(store: store)
      }
  }
}

#Preview("E-mail") {
  EmailScreen(store: EmailPreview.store())
    .frame(width: 1100, height: 700)
}
