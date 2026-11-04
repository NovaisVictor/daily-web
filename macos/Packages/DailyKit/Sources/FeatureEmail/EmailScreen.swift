import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The e-mail module: the folder tree beside the conversation list, as the
/// web's full-screen e-mail (`components/EmailPanel.tsx`).
public struct EmailScreen: View {
  @State private var store: EmailStore

  public init(environment: AppEnvironment) {
    _store = State(
      initialValue: EmailStore(
        client: environment.client, dashboard: environment.dashboard, toasts: environment.toasts,
        navigator: environment.navigator))
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
    .task(id: store.mailboxes.map(\.id)) { await store.loadMailboxes() }
    .task { await store.loadNoteFolders() }
    // A clicked notification: shown now, or once the inbox arrives.
    .task { store.revealPending() }
    .onChange(of: store.pendingItemID) { store.revealPending() }
    .onChange(of: store.inbox.data) { store.revealPending() }
    .confirmDialog($store.confirmation)
    .sheet(isPresented: $store.isMoveSheetPresented) {
      EmailMoveSheet(store: store)
    }
  }
}

/// The header, filters, notices and the conversation list.
struct EmailListPane: View {
  @Environment(\.theme) private var theme
  @Bindable var store: EmailStore

  var body: some View {
    let listing = store.listing
    let active = store.filters.active(mailboxes: store.mailboxes)
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(
        store.folderTitle,
        count: active.isEmpty ? nil : "\(listing.visible.count) de \(listing.all.count)"
      ) {
        EmailBatchBar(store: store)
      }
      filterBar
      activeFilters(active)
      notices
      if store.dragging != nil, !store.selection.selected.isEmpty {
        EmailActionDropTargets(store: store, count: store.selection.selected.count)
      }
      content(listing)
    }
    .padding(16)
    .onChange(of: listing.order) { store.syncSelection() }
  }

  private var filterBar: some View {
    FilterBar("Filtrar e-mails") {
      SearchField(text: $store.filters.query, label: "buscar e-mails", placeholder: "assunto ou remetente")
      Chip("Não lidos", isOn: store.filters.onlyUnread) { store.filters.onlyUnread.toggle() }
      // One box needs no box filter.
      if store.mailboxes.count > 1 {
        ForEach(store.mailboxes) { box in
          Chip(box.label, isOn: store.filters.account == box.id) {
            store.filters.account = store.filters.account == box.id ? nil : box.id
          }
        }
      }
      Picker("ordenar e-mails", selection: $store.filters.sort) {
        ForEach(EmailSort.allCases) { Text($0.label).tag($0) }
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("ordenar e-mails")
      Picker("agrupar e-mails", selection: $store.filters.groupBy) {
        ForEach(EmailGroupBy.allCases) { Text($0.optionLabel).tag($0) }
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("agrupar e-mails")
    }
  }

  @ViewBuilder
  private func activeFilters(_ active: [EmailFilters.Active]) -> some View {
    if !active.isEmpty {
      FlowLayout(spacing: 8) {
        ForEach(active) { filter in
          HStack(spacing: 4) {
            Text(filter.label).font(.system(size: 12))
            Button {
              store.clearFilter(filter.kind)
            } label: {
              Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkDim)
            .accessibilityLabel("remover filtro \(filter.label)")
          }
          .padding(.leading, 8)
          .padding(.trailing, 6)
          .padding(.vertical, 2)
          .background(theme.neutralTint, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.lineStrong) }
        }
        if active.count > 1 {
          Button("Limpar tudo", systemImage: "xmark") { store.clearAllFilters() }
            .buttonStyle(.borderless)
            .controlSize(.small)
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
          .buttonStyle(.link)
      }
    }
    if let error = store.batchError {
      PanelError(error)
    }
    if !store.unprocessed.isEmpty {
      HStack(alignment: .firstTextBaseline) {
        PanelError(unprocessedText)
        Button("tentar de novo") { Task { await store.retryUnprocessed() } }
          .buttonStyle(.link)
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

/// The batch actions for the selection (`acoesEmLote`).
struct EmailBatchBar: View {
  @Environment(\.theme) private var theme
  @Bindable var store: EmailStore

  var body: some View {
    let count = store.selection.selected.count
    if count > 0 {
      HStack(spacing: 8) {
        Text("\(count) \(count == 1 ? "conversa" : "conversas")")
          .font(.system(size: 14).monospacedDigit())
          .foregroundStyle(theme.inkDim)
        // The only hint that E and M exist.
        HStack(spacing: 4) {
          ShortcutKey("E")
          Text("excluir")
          ShortcutKey("M")
          Text("mover")
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.inkDim)
        Button("Marcar lido", systemImage: "envelope.open") { Task { await store.runBatch(.read) } }
          .labelStyle(.iconOnly)
          .help("Marcar lido")
        Button("Marcar não lido", systemImage: "envelope.badge") { Task { await store.runBatch(.unread) } }
          .labelStyle(.iconOnly)
          .help("Marcar não lido")
        let folders = store.moveFolders
        if !folders.isEmpty {
          Picker(
            "pasta de destino",
            selection: Binding(get: { store.effectiveTargetFolder }, set: { store.targetFolder = $0 })
          ) {
            ForEach(folders, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
          .accessibilityLabel("pasta de destino")
          Button("Mover", systemImage: "folder") {
            Task { await store.runBatch(.move, folder: store.effectiveTargetFolder) }
          }
          .labelStyle(.iconOnly)
          .help("Mover")
        }
        Button("Excluir", systemImage: "trash", role: .destructive) { store.requestDeleteSelected() }
          .labelStyle(.iconOnly)
          .help("Excluir")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
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
        .font(.headline)
      Picker(
        "pasta de destino do atalho M",
        selection: Binding(get: { store.effectiveTargetFolder }, set: { store.targetFolder = $0 })
      ) {
        ForEach(store.moveFolders, id: \.self) { Text($0).tag($0) }
      }
      .labelsHidden()
      .accessibilityLabel("pasta de destino do atalho M")
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
        .keyboardShortcut(.cancelAction)
        Button {
          Task { await store.confirmMoveSelected() }
        } label: {
          HStack(spacing: 6) {
            Text("Mover")
            ShortcutKey("Enter")
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 380)
  }
}

#Preview("E-mail") {
  EmailScreen(store: EmailPreview.store())
    .frame(width: 1100, height: 700)
}
