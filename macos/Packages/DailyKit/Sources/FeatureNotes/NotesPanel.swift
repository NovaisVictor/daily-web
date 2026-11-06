import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Notas rápidas" (`components/NotesPanel.tsx`): the folder tree and search on
/// the left, the Markdown editor with its toolbar, preview and save status on
/// the right, and "Maximizar" opening the same editor in a large sheet. Drawn
/// without a frame: the Início host puts it on the panel surface, the notes
/// screen pads it.
public struct NotesPanel: View {
  @State private var store: NotesStore
  @State private var editor = NoteEditorController()
  @State private var maximizedEditor = NoteEditorController()
  @State private var confirmation: ConfirmRequest?
  /// The maximized sheet asks its own: a second sheet cannot open behind it.
  @State private var maximizedConfirmation: ConfirmRequest?
  @State private var isMaximized = false
  @State private var size = CGSize.zero
  @Environment(\.theme) private var theme
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let navigator: AppNavigator
  private let onOpenWindow: (() -> Void)?
  private let canMaximize: Bool

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// With `onOpenWindow`, the header's "…" offers "Abrir em nova janela".
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    self.init(
      store: NotesStore.shared(in: environment), navigator: environment.navigator, onOpenWindow: onOpenWindow,
      canMaximize: true)
  }

  init(store: NotesStore, navigator: AppNavigator, onOpenWindow: (() -> Void)?, canMaximize: Bool) {
    _store = State(initialValue: store)
    self.navigator = navigator
    self.onOpenWindow = onOpenWindow
    self.canMaximize = canMaximize
  }

  private static let route = AppRoute.module(.notes)
  /// Below this the list sits above the editor, as the web's grid does under `md`.
  static let splitWidth: CGFloat = 560

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
        headerActions
      }
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      size = $0
    }
    .confirmDialog($confirmation)
    .sheet(isPresented: maximizedBinding) { maximizedView }
    // A note another screen asked to show ("Abrir a nota", a notification).
    .task { await loadRevealingPending() }
    .onChange(of: navigator.pending) {
      guard isPrimaryWindow, navigator.pendingItem(for: Self.route) != nil else { return }
      Task { await loadRevealingPending() }
    }
    .onAppear { store.viewAppeared() }
    .onDisappear {
      store.viewDisappeared()
      Task { await store.flushPending() }
    }
    .onChange(of: store.editorFocusRequest) { focusEditor(maximized: isMaximized) }
    // Back from the sheet, writing goes on in the panel (`NotesPanel.tsx:851-857`).
    .onChange(of: isMaximized) { _, maximized in
      if !maximized { focusEditor(maximized: false) }
    }
    .onChange(of: store.activeID) { _, id in
      // The sheet shows the open note; with none left it has nothing to show.
      if id == nil { isMaximized = false }
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
        workspace
      }
    }
  }

  /// While maximized the list is the sheet's: two on the page would be two
  /// targets for the same action (`NotesPanel.tsx:812-814`).
  @ViewBuilder private var workspace: some View {
    let showsSidebar = store.isSidebarOpen && !isMaximized
    if size.width >= Self.splitWidth {
      HSplitView {
        if showsSidebar {
          sidebar(inSheet: false)
            .padding(.trailing, 8)
            .frame(minWidth: 180, idealWidth: max(180, size.width * 0.28), maxWidth: 420)
        }
        editorColumn(inSheet: false)
          .padding(.leading, showsSidebar ? 8 : 0)
          .frame(minWidth: 280)
      }
    } else {
      VStack(alignment: .leading, spacing: 12) {
        // `max-h-[45vh]`: the list never pushes the editor out of the panel.
        if showsSidebar { sidebar(inSheet: false).frame(maxHeight: max(160, size.height * 0.45)) }
        editorColumn(inSheet: false)
      }
    }
  }

  // MARK: - Header

  /// The creation buttons leave the card's header while maximized: the sheet
  /// has its own copy, and one at a time keeps one target per action.
  private var headerActions: some View {
    HStack(spacing: 4) {
      if !isMaximized { creationButtons }
      if let onOpenWindow {
        IconMenu("mais ações das notas", systemImage: "ellipsis") {
          Button("Abrir em nova janela", systemImage: "macwindow.badge.plus", action: onOpenWindow)
        }
      }
    }
  }

  private var creationButtons: some View {
    HStack(spacing: 4) {
      IconButton("Nova pasta", systemImage: "folder.badge.plus", variant: .outline) {
        Task { await store.createFolder(in: store.scope.folderID) }
      }
      IconButton("Nova nota", systemImage: "plus", variant: .outline) {
        Task { await store.createNote() }
      }
    }
  }

  // MARK: - Sidebar

  /// Search on top, the tree or the results below. `inSheet` adds the creation
  /// header the maximized sheet lacks (`NotesPanel.tsx:717-746`).
  private func sidebar(inSheet: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if inSheet { creationHeader }
      let search = Binding(get: { store.searchText }, set: { store.setSearchText($0) })
      SearchField(text: search, label: "Buscar notas", placeholder: "Buscar no título ou conteúdo")
        .singleLine(search)
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
        NoteTreeView(
          store: store,
          onDeleteNote: { confirmDelete($0, inSheet: inSheet) },
          onDeleteFolder: { confirmDeleteFolder($0, inSheet: inSheet) })
      }
    }
  }

  /// Says where "Nova nota" and "Nova pasta" land: the card's header is not
  /// reachable behind the sheet, and without this creating would be blind.
  private var creationHeader: some View {
    HStack(spacing: 8) {
      Text("Criar em: \(Text(store.creationContext).foregroundStyle(theme.inkMid))")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      creationButtons
    }
    .padding(.bottom, 8)
    .overlay(alignment: .bottom) { Rectangle().fill(theme.lineSoft).frame(height: 1) }
  }

  // MARK: - Editor

  private func editorColumn(inSheet: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      toolbar(inSheet: inSheet)
      if isMaximized && !inSheet {
        dashedNotice("Aberta em tela cheia.")
      } else {
        noteBody(inSheet: inSheet)
      }
      statusLine
    }
  }

  /// The panel's copy goes inert while the sheet is open: the text it would
  /// format is the sheet's (`NotesPanel.tsx:599-602`).
  private func toolbar(inSheet: Bool) -> some View {
    let controller = inSheet ? maximizedEditor : editor
    let inert = isMaximized && !inSheet
    return HStack(alignment: .top, spacing: 8) {
      iconButton(
        store.isSidebarOpen ? "Esconder a lista" : "Mostrar a lista", systemImage: "sidebar.left",
        isOn: store.isSidebarOpen
      ) {
        store.isSidebarOpen.toggle()
      }
      // Formatting wraps when the panel is narrow; reading and maximizing stay
      // in the top-right corner.
      FlowLayout(spacing: 2) {
        ForEach(MarkdownAction.allCases) { action in
          iconButton(action.label, systemImage: action.systemImage) { controller.apply(action) }
            .disabled(store.isReading || store.activeNote == nil || inert)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("formatação Markdown")
      HStack(spacing: 2) {
        iconButton(
          store.isReading ? "Editar" : "Visualizar", systemImage: store.isReading ? "pencil" : "eye",
          isOn: store.isReading
        ) {
          Task { await store.flushPending() }
          store.isReading.toggle()
        }
        .disabled(inert)
        if canMaximize { maximizeButton(inSheet: inSheet) }
      }
    }
  }

  @ViewBuilder private func maximizeButton(inSheet: Bool) -> some View {
    if inSheet {
      iconButton("Restaurar", systemImage: "arrow.down.right.and.arrow.up.left") { setMaximized(false) }
        .keyboardShortcut(.cancelAction)
    } else {
      iconButton("Maximizar", systemImage: "arrow.up.left.and.arrow.down.right") { setMaximized(!isMaximized) }
        .disabled(store.activeNote == nil)
    }
  }

  @ViewBuilder private func noteBody(inSheet: Bool) -> some View {
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
            controller: inSheet ? maximizedEditor : editor,
            onChange: { store.edit($0) },
            onBlur: { Task { await store.flushPending() } },
            onEscape: inSheet ? { setMaximized(false) } : nil
          )
          .overlay(alignment: .topLeading) {
            if store.draft.isEmpty {
              Text("Escreva aqui, em Markdown. O que você digita é salvo sozinho.")
                .font(.dailyMono(size: NoteEditor.fontSize))
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
      dashedNotice("Escolha uma nota na lista.")
    }
  }

  private func dashedNotice(_ text: String) -> some View {
    Text(text)
      .typeRole(.caption)
      .foregroundStyle(theme.inkDim)
      .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
      .overlay {
        RoundedRectangle(cornerRadius: Radius.small)
          .strokeBorder(theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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

  // MARK: - Maximized

  /// `open={maximizada && notaAtiva !== null}` (`NotesPanel.tsx:839`).
  private var maximizedBinding: Binding<Bool> {
    Binding(
      get: { isMaximized && store.activeNote != nil },
      set: { if !$0 { setMaximized(false) } }
    )
  }

  /// The pending text goes up before the switch: the editor changes place and
  /// the draft must not depend on which of the two was open.
  private func setMaximized(_ maximized: Bool) {
    Task { await store.flushPending() }
    isMaximized = maximized
  }

  /// The same editor and list in a large sheet: Esc and "Restaurar" return to
  /// the panel. Switching notes here closes nothing.
  private var maximizedView: some View {
    let title = store.activeNote.map { $0.title.isEmpty ? "sem título" : $0.title } ?? "sem título"
    return VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityAddTraits(.isHeader)
      // The card's warning too: a failure while creating here cannot show
      // only behind the sheet.
      if let error = store.error { PanelError(error) }
      HSplitView {
        if store.isSidebarOpen {
          sidebar(inSheet: true)
            .padding(.trailing, 8)
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
        }
        editorColumn(inSheet: true)
          .padding(.leading, store.isSidebarOpen ? 8 : 0)
          .frame(minWidth: 360)
      }
    }
    .padding(20)
    // `h-[calc(100dvh-2rem)] sm:max-w-[min(72rem,…)]`.
    .frame(minWidth: 760, idealWidth: 1152, minHeight: 520, idealHeight: 820)
    .accessibilityHint("Nota em tela cheia. Esc volta ao painel.")
    .confirmDialog($maximizedConfirmation)
    // Maximizing is for writing: focus goes to the text, not the first button.
    .onAppear { focusEditor(maximized: true) }
  }

  /// The text view of the note just shown exists only after this update lands.
  private func focusEditor(maximized: Bool) {
    let target = maximized ? maximizedEditor : editor
    Task {
      await Task.yield()
      target.focus()
    }
  }

  // MARK: - Confirmations

  private func confirmDelete(_ note: Note, inSheet: Bool) {
    ask(
      ConfirmRequest(
        title: "Apagar a nota?",
        message: "\"\(note.title.isEmpty ? "sem título" : note.title)\" será removida. Isso não tem volta.",
        confirmLabel: "Apagar",
        destructive: true,
        onConfirm: { Task { await store.deleteNote(note.id) } }
      ), inSheet: inSheet)
  }

  private func confirmDeleteFolder(_ id: String, inSheet: Bool) {
    guard let prompt = store.deletionPrompt(forFolder: id) else { return }
    ask(
      ConfirmRequest(
        title: prompt.title,
        message: prompt.message,
        confirmLabel: prompt.confirmLabel,
        destructive: true,
        onConfirm: { Task { await store.deleteFolder(id) } }
      ), inSheet: inSheet)
  }

  private func ask(_ request: ConfirmRequest, inSheet: Bool) {
    if inSheet { maximizedConfirmation = request } else { confirmation = request }
  }

  // MARK: - Pieces

  private func iconButton(
    _ label: String, systemImage: String, isOn: Bool? = nil, action: @escaping () -> Void
  ) -> some View {
    // `aria-pressed` keeps the rim on, as the ghost style's open state.
    IconButton(label, systemImage: systemImage, isActive: isOn == true, action: action)
      .accessibilityAddTraits(isOn == true ? .isSelected : [])
  }
}

#Preview("Painel · 420pt") {
  NotesPanel(
    store: NotesPreview.store(), navigator: AppEnvironment.preview().navigator, onOpenWindow: {},
    canMaximize: true
  )
  .padding(16)
  .frame(width: 420, height: 620)
  .glassSurface(.panel)
  .padding()
}

#Preview("Painel · 700pt") {
  NotesPanel(
    store: NotesPreview.store(), navigator: AppEnvironment.preview().navigator, onOpenWindow: {},
    canMaximize: true
  )
  .padding(16)
  .frame(width: 700, height: 520)
  .glassSurface(.panel)
  .padding()
}

/// Sample notes for the previews; made-up text.
enum NotesPreview {
  static func store() -> NotesStore {
    NotesStore(client: client, poller: Poller(), shutdown: ShutdownTasks())
  }

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
