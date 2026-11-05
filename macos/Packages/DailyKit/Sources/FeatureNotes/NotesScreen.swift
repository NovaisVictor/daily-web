import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Notas rápidas" (`components/NotesPanel.tsx`): the folder tree and search on
/// the left, the Markdown editor with its toolbar, preview and save status on
/// the right.
public struct NotesScreen: View {
  @State private var store: NotesStore
  @State private var editor = NoteEditorController()
  @State private var confirmation: ConfirmRequest?
  @Environment(\.theme) private var theme
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let navigator: AppNavigator
  private let shutdown: ShutdownTasks

  public init(environment: AppEnvironment) {
    self.init(
      store: NotesStore(client: environment.client, poller: environment.poller),
      navigator: environment.navigator,
      shutdown: environment.shutdown)
  }

  init(store: NotesStore, navigator: AppNavigator, shutdown: ShutdownTasks) {
    _store = State(initialValue: store)
    self.navigator = navigator
    self.shutdown = shutdown
  }

  private static let shutdownID = "notes"
  private static let route = AppRoute.module(.notes)

  /// Reads the list opening the note another screen asked for. The request is
  /// finished only once a list arrived: with it the note opened or is gone.
  private func loadRevealingPending() async {
    // Only the main window takes the request; it is the one the navigator moved.
    let id = isPrimaryWindow ? navigator.pendingItem(for: Self.route) : nil
    await store.load(activate: id)
    if let id, store.hasLoaded { navigator.finishPendingItem(id, for: Self.route) }
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader("Notas rápidas", count: store.notes.isEmpty ? nil : "\(store.notes.count)") {
        creationButtons
      }
      content
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .confirmDialog($confirmation)
    // A note another screen asked to show ("Abrir a nota", a notification).
    .task { await loadRevealingPending() }
    .onChange(of: navigator.pending) {
      guard isPrimaryWindow, navigator.pendingItem(for: Self.route) != nil else { return }
      Task { await loadRevealingPending() }
    }
    .onAppear {
      store.setVisible(true)
      // An unsent draft is lost when the process exits; the app waits for this
      // flush before quitting (the web needs `sendBeacon`, `NotesPanel.tsx:264-278`).
      shutdown.register(Self.shutdownID) { [store] in await store.flushPending() }
    }
    .onDisappear {
      store.setVisible(false)
      shutdown.unregister(Self.shutdownID)
      Task { await store.flushPending() }
    }
    .onChange(of: store.editorFocusRequest) {
      // The text view for the new note exists only after this update lands.
      Task {
        await Task.yield()
        editor.focus()
      }
    }
  }

  @ViewBuilder private var content: some View {
    if store.isLoading && !store.hasLoaded {
      LoadingState()
    } else if !store.hasLoaded {
      ErrorState("Falha ao carregar as notas", description: store.error) {
        Task { await loadRevealingPending() }
      }
    } else {
      if let error = store.error { PanelError(error) }
      if store.isEmpty {
        EmptyState("Nenhuma nota ainda.", description: "Crie a primeira.")
      } else {
        HSplitView {
          if store.isSidebarOpen {
            sidebar.frame(minWidth: 200, idealWidth: 260, maxWidth: 420)
          }
          editorColumn.frame(minWidth: 320)
        }
      }
    }
  }

  // MARK: - Header

  private var creationButtons: some View {
    HStack(spacing: 4) {
      iconButton("Nova pasta", systemImage: "folder.badge.plus") {
        Task { await store.createFolder(in: store.scope.folderID) }
      }
      iconButton("Nova nota", systemImage: "plus") {
        Task { await store.createNote() }
      }
    }
    .buttonStyle(.bordered)
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Says where "Nova nota" and "Nova pasta" land (`NotesPanel.tsx:717-735`).
      Text("Criar em: \(Text(store.creationContext).foregroundStyle(theme.inkMid))")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .lineLimit(1)
        .truncationMode(.middle)
      SearchField(
        text: Binding(get: { store.searchText }, set: { store.setSearchText($0) }),
        label: "Buscar notas",
        placeholder: "Buscar no título ou conteúdo"
      )
      if store.isSearching && store.scope != .all {
        Toggle("Só nesta pasta e subpastas", isOn: $store.onlyInFolder)
          .toggleStyle(.checkbox)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
      }
      if store.isSearching {
        NoteSearchResultsView(results: store.searchResults, activeID: store.activeID) { id in
          Task { await store.open(id) }
        }
      } else {
        NoteTreeView(store: store, onDeleteNote: confirmDelete(_:), onDeleteFolder: confirmDeleteFolder(_:))
      }
    }
    .padding(.trailing, 8)
  }

  // MARK: - Editor

  private var editorColumn: some View {
    VStack(alignment: .leading, spacing: 8) {
      toolbar
      noteBody
      statusLine
    }
    .padding(.leading, 8)
  }

  private var toolbar: some View {
    HStack(alignment: .top, spacing: 8) {
      iconButton(
        store.isSidebarOpen ? "Esconder a lista" : "Mostrar a lista", systemImage: "sidebar.left",
        isOn: store.isSidebarOpen
      ) {
        store.isSidebarOpen.toggle()
      }
      FlowLayout(spacing: 2) {
        ForEach(MarkdownAction.allCases) { action in
          iconButton(action.label, systemImage: action.systemImage) { editor.apply(action) }
            .disabled(store.isReading || store.activeNote == nil)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("formatação Markdown")
      iconButton(
        store.isReading ? "Editar" : "Visualizar", systemImage: store.isReading ? "pencil" : "eye",
        isOn: store.isReading
      ) {
        Task { await store.flushPending() }
        store.isReading.toggle()
      }
    }
    .buttonStyle(.borderless)
  }

  @ViewBuilder private var noteBody: some View {
    if let note = store.activeNote {
      let name = note.title.isEmpty ? "sem título" : note.title
      Group {
        if store.isReading {
          ScrollView {
            if store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text("Nada escrito ainda.")
                .foregroundStyle(theme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
              MarkdownPreview(source: store.draft)
            }
          }
          .contentMargins(12, for: .scrollContent)
          .accessibilityLabel("visualização de \(name)")
        } else {
          NoteEditor(
            noteID: note.id,
            text: store.draft,
            accessibilityLabel: "texto de \(name)",
            controller: editor,
            onChange: { store.edit($0) },
            onBlur: { Task { await store.flushPending() } }
          )
          .overlay(alignment: .topLeading) {
            if store.draft.isEmpty {
              Text("Escreva aqui, em Markdown. O que você digita é salvo sozinho.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.inkDim)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.surface1.opacity(0.6), in: .rect(cornerRadius: Radius.small))
      .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineSoft) }
    } else {
      Text("Escolha uma nota na lista.")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
        .overlay {
          RoundedRectangle(cornerRadius: Radius.small)
            .strokeBorder(theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
  }

  private var statusLine: some View {
    let save = Text(NotesStore.statusText(saveState: store.saveState, sync: nil)).foregroundStyle(theme.inkDim)
    var syncPart = Text(verbatim: "")
    if let sync = store.sync, sync.connected, store.saveState != .failed {
      let failed = !(sync.lastError ?? "").isEmpty
      syncPart = Text(verbatim: " · " + NotesStore.syncDescription(sync))
        .foregroundStyle(failed ? theme.warning : theme.inkDim)
    }
    return Text("\(save)\(syncPart)")
      .typeRole(.caption)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .accessibilityLabel(store.statusText)
      .accessibilityAddTraits(.updatesFrequently)
  }

  // MARK: - Confirmations

  private func confirmDelete(_ note: Note) {
    confirmation = ConfirmRequest(
      title: "Apagar a nota?",
      message: "\"\(note.title.isEmpty ? "sem título" : note.title)\" será removida. Isso não tem volta.",
      confirmLabel: "Apagar",
      destructive: true,
      onConfirm: { Task { await store.deleteNote(note.id) } }
    )
  }

  private func confirmDeleteFolder(_ id: String) {
    guard let prompt = store.deletionPrompt(forFolder: id) else { return }
    confirmation = ConfirmRequest(
      title: prompt.title,
      message: prompt.message,
      confirmLabel: prompt.confirmLabel,
      destructive: true,
      onConfirm: { Task { await store.deleteFolder(id) } }
    )
  }

  // MARK: - Pieces

  private func iconButton(
    _ label: String, systemImage: String, isOn: Bool? = nil, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .frame(width: 18, height: 18)
        .foregroundStyle(isOn == true ? theme.brand : theme.inkMid)
    }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isOn == true ? .isSelected : [])
  }
}

#Preview("Notas") {
  NotesScreen(
    store: NotesStore(client: NotesPreview.client, poller: Poller()), navigator: AppNavigator(),
    shutdown: ShutdownTasks()
  )
  .frame(width: 900, height: 600)
}

/// Sample notes for the preview; made-up text.
private enum NotesPreview {
  static let client = PreviewAPIClient(responses: ["GET /api/notes": Data(json.utf8)])

  static let json = """
    {"notes":[
      {"id":"n1","title":"Reunião de planejamento","body":"## Pauta\\n\\n- [x] metas\\n- [ ] **prazos**\\n\\nVeja [o quadro](https://example.com).","position":0,"updatedAt":"2026-11-04T12:00:00.000Z","folderId":"f2"},
      {"id":"n2","title":"Ideias","body":"Sem pasta ainda.","position":1,"updatedAt":"2026-11-04T12:00:00.000Z","folderId":null}
    ],
    "folders":[
      {"id":"f1","name":"Trabalho","parentId":null,"position":0,"updatedAt":"2026-11-04T12:00:00.000Z"},
      {"id":"f2","name":"Clientes","parentId":"f1","position":0,"updatedAt":"2026-11-04T12:00:00.000Z"}
    ],
    "sync":{"connected":true,"account":"ana@example.com","pending":1,"lastError":null,"lastSyncedAt":null}}
    """
}
