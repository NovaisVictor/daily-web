import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// The notes screen's state (`components/NotesPanel.tsx`). Notes are not part of
/// the dashboard state: this store reads `GET /api/notes` and owns the result.
@Observable
final class NotesStore {
  enum SaveState: Equatable {
    case saved
    case saving
    case failed
  }

  /// How long the text rests before it goes up (`AUTOSAVE_MS`).
  static let autosaveDelay = Duration.milliseconds(700)
  /// Pause before the query becomes a search (`SEARCH_DEBOUNCE_MS`).
  static let searchDelay = Duration.milliseconds(250)

  private(set) var notes: [Note] = []
  private(set) var folders: [NoteFolder] = []
  private(set) var sync: NotesSyncStatus?
  private(set) var isLoading = true
  private(set) var hasLoaded = false
  /// The last failure, shown above the panel like the web's `erro`.
  private(set) var error: String?
  private(set) var saveState = SaveState.saved
  private(set) var activeID: String?
  /// The text being edited. It lives here and not in `notes` so typing never waits
  /// for a save, and a reload never writes the saved text over unsent keystrokes.
  private(set) var draft = ""

  var scope = NoteScope.all
  /// Open folders, plus `NoteTreeRow.noneKey` for "Sem pasta".
  var expanded: Set<String> = [NoteTreeRow.noneKey]
  /// The note or folder whose name is being edited.
  var renaming: String?
  var onlyInFolder = false
  var isReading = false
  var isSidebarOpen = true
  private(set) var searchText = ""
  /// `searchText` after the debounce.
  private(set) var query = ""
  /// Bumped when the editor should take focus (a note was just created).
  private(set) var editorFocusRequest = 0

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let poller: Poller
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var pending: (id: String, body: String)?
  @ObservationIgnored private var autosaveTask: Task<Void, Never>?
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  @ObservationIgnored private var isVisible = false
  @ObservationIgnored private var isPollingSync = false

  init(client: any APIClient, poller: Poller, sleep: @escaping Sleeper = LiveTime.sleep) {
    self.client = client
    self.poller = poller
    self.sleep = sleep
  }

  // MARK: - Derived

  var activeNote: Note? { activeID.flatMap { id in notes.first { $0.id == id } } }

  var rows: [NoteTreeRow] { NoteTreeRow.flatten(notes: notes, folders: folders, expanded: expanded) }

  var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var searchScopeIDs: [String?]? {
    guard onlyInFolder else { return nil }
    switch scope {
    case .folder(let id): return NotesTree.descendantIDs(folders, of: id)
    case .none: return [nil]
    case .all: return nil
    }
  }

  var searchResults: [NoteSearchResult] {
    NotesSearch.search(notes, folders: folders, query: query, scopeIDs: searchScopeIDs)
  }

  /// Where a new note or folder lands (`NotesPanel.tsx:720-723`).
  var creationContext: String {
    guard let id = scope.folderID else { return "Sem pasta" }
    let path = NotesTree.path(folders, to: id)
    return path.isEmpty ? "Sem pasta" : path.joined(separator: " / ")
  }

  var isEmpty: Bool { hasLoaded && notes.isEmpty && folders.isEmpty }

  /// "salvo · no Google Drive" (`NotesPanel.tsx:111-115` and `:684-694`).
  var statusText: String {
    Self.statusText(saveState: saveState, sync: sync)
  }

  static func statusText(saveState: SaveState, sync: NotesSyncStatus?) -> String {
    var text =
      switch saveState {
      case .saving: "salvando…"
      case .failed: "não salvo"
      case .saved: "salvo"
      }
    if let sync, sync.connected, saveState != .failed {
      text += " · " + syncDescription(sync)
    }
    return text
  }

  static func syncDescription(_ sync: NotesSyncStatus) -> String {
    if let lastError = sync.lastError, !lastError.isEmpty { return "Drive: \(lastError)" }
    if sync.pending > 0 { return "enviando ao Drive…" }
    return "no Google Drive"
  }

  // MARK: - Loading

  /// Reads the list. `activate` leaves that note open at the end; the draft only
  /// changes when the open note does.
  func load(activate: String? = nil) async {
    if activate != nil { await flushPending() }
    defer { isLoading = false }
    let response: NotesResponse
    do {
      response = try await client.send(NotesEndpoints.list)
    } catch {
      fail("Load notes", error)
      return
    }
    hasLoaded = true
    notes = response.notes
    folders = response.folders
    error = nil
    setSync(response.sync)

    let target = activate.flatMap { id in response.notes.first { $0.id == id } }
    let stays = activeID.map { id in response.notes.contains { $0.id == id } } ?? false
    if let next = target ?? (stays ? nil : response.notes.first) {
      activeID = next.id
      draft = next.body
    } else if !stays {
      activeID = nil
      draft = ""
    }
    if let target {
      // Opening a note leaves the search and shows its folder.
      setSearchText("")
      query = ""
      expanded.insert(target.folderId ?? NoteTreeRow.noneKey)
    }
  }

  // MARK: - Editing

  func open(_ id: String) async {
    guard id != activeID else { return }
    await flushPending()
    guard let note = notes.first(where: { $0.id == id }) else { return }
    activeID = id
    draft = note.body
  }

  /// A keystroke: the text stays local and goes up after `autosaveDelay` of quiet.
  func edit(_ text: String) {
    guard let activeID else { return }
    draft = text
    saveState = .saving
    pending = (activeID, text)
    autosaveTask?.cancel()
    let sleep = self.sleep
    autosaveTask = Task { [weak self] in
      do {
        try await sleep(Self.autosaveDelay)
      } catch {
        // Cancelled by the next keystroke or by a flush, which takes over the save.
        return
      }
      await self?.flushPending()
    }
  }

  /// Sends whatever is waiting now, cancelling the wait.
  func flushPending() async {
    autosaveTask?.cancel()
    autosaveTask = nil
    guard let target = pending else { return }
    pending = nil
    await save(target.id, body: target.body)
  }

  private func save(_ id: String, title: String? = nil, body: String? = nil) async {
    saveState = .saving
    do {
      let response = try await client.send(NotesEndpoints.update(id: id, title: title, body: body))
      error = nil
      saveState = .saved
      replace(response.note)
    } catch {
      fail("Save note", error)
      saveState = .failed
    }
  }

  /// An empty title keeps the old name (`NotesPanel.tsx:438-445`).
  func renameNote(_ id: String, to title: String) async {
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = notes.firstIndex(where: { $0.id == id }), !clean.isEmpty, clean != notes[index].title
    else { return }
    let previous = notes[index].title
    notes[index].title = clean
    saveState = .saving
    do {
      let response = try await client.send(NotesEndpoints.update(id: id, title: clean))
      error = nil
      saveState = .saved
      replace(response.note)
    } catch {
      if let index = notes.firstIndex(where: { $0.id == id }), notes[index].title == clean {
        notes[index].title = previous
      }
      fail("Rename note", error)
      saveState = .failed
    }
  }

  // MARK: - Notes

  func createNote() async {
    await flushPending()
    let endpoint = NotesEndpoints.create(title: "Nota \(notes.count + 1)", folderId: scope.folderID)
    let note: Note
    do {
      note = try await client.send(endpoint).note
    } catch {
      fail("Create note", error)
      return
    }
    error = nil
    notes.append(note)
    activeID = note.id
    draft = note.body
    expanded.insert(note.folderId ?? NoteTreeRow.noneKey)
    editorFocusRequest += 1
  }

  /// Called after the confirmation.
  func deleteNote(_ id: String) async {
    if pending?.id == id {
      pending = nil
      autosaveTask?.cancel()
      autosaveTask = nil
    }
    do {
      _ = try await client.send(NotesEndpoints.delete(id: id))
    } catch {
      // The web shows its own text here, not the server's (`NotesPanel.tsx:421`).
      Logger.notes.error("Delete note failed: \(error.userMessage, privacy: .public)")
      self.error = "Falha ao apagar a nota"
      return
    }
    error = nil
    notes.removeAll { $0.id == id }
    if activeID == id {
      activeID = notes.first?.id
      draft = notes.first?.body ?? ""
      if activeID == nil { saveState = .saved }
    }
  }

  /// Moves a note to a folder (nil: "Sem pasta"). Applied at once, undone on error.
  @discardableResult
  func moveNote(_ id: String, to folderId: String?) async -> Bool {
    guard let note = notes.first(where: { $0.id == id }), note.folderId != folderId else { return false }
    // The pending text goes up first: the move answers the whole note.
    await flushPending()
    let previous = note.folderId
    update(id) { $0.folderId = folderId }
    do {
      let response = try await client.send(NotesEndpoints.move(id: id, folderId: folderId))
      error = nil
      replace(response.note)
      expanded.insert(folderId ?? NoteTreeRow.noneKey)
      return true
    } catch {
      update(id) { if $0.folderId == folderId { $0.folderId = previous } }
      fail("Move note", error)
      return false
    }
  }

  /// A note dropped on another: it lands in that note's folder, just before it.
  func dropNote(_ id: String, before targetID: String) async {
    guard id != targetID, let target = notes.first(where: { $0.id == targetID }),
      let note = notes.first(where: { $0.id == id })
    else { return }
    if note.folderId != target.folderId {
      guard await moveNote(id, to: target.folderId) else { return }
    }
    var ids = notes.map(\.id)
    ids.removeAll { $0 == id }
    guard let index = ids.firstIndex(of: targetID) else { return }
    ids.insert(id, at: index)
    await reorder(ids)
  }

  /// Swaps a note with its previous (`offset` -1) or next (+1) sibling in the folder.
  func shiftNote(_ id: String, by offset: Int) async {
    guard let note = notes.first(where: { $0.id == id }) else { return }
    let siblings = notes.filter { $0.folderId == note.folderId }.map(\.id)
    guard let position = siblings.firstIndex(of: id), siblings.indices.contains(position + offset) else { return }
    let neighbour = siblings[position + offset]
    var ids = notes.map(\.id)
    guard let a = ids.firstIndex(of: id), let b = ids.firstIndex(of: neighbour) else { return }
    ids.swapAt(a, b)
    await reorder(ids)
  }

  func canShiftNote(_ id: String, by offset: Int) -> Bool {
    guard let note = notes.first(where: { $0.id == id }) else { return false }
    let siblings = notes.filter { $0.folderId == note.folderId }.map(\.id)
    guard let position = siblings.firstIndex(of: id) else { return false }
    return siblings.indices.contains(position + offset)
  }

  /// `PUT /api/notes` with the whole order. Applied at once, undone on error.
  func reorder(_ ids: [String]) async {
    await flushPending()
    let previousOrder = notes.map(\.id)
    guard ids != previousOrder else { return }
    let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    notes.sort { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
    do {
      let response = try await client.send(NotesEndpoints.reorder(ids: ids))
      error = nil
      notes = response.notes
    } catch {
      let previous = Dictionary(previousOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      notes.sort { (previous[$0.id] ?? Int.max) < (previous[$1.id] ?? Int.max) }
      fail("Reorder notes", error)
    }
  }

  // MARK: - Folders

  func createFolder(in parentId: String?) async {
    let folder: NoteFolder
    do {
      folder = try await client.send(NotesEndpoints.createFolder(name: "Nova pasta", parentId: parentId)).folder
    } catch {
      fail("Create folder", error)
      return
    }
    error = nil
    folders.append(folder)
    if let parentId { expanded.insert(parentId) }
    // Born with the name in edit: nobody wants to keep "Nova pasta".
    renaming = folder.id
  }

  func renameFolder(_ id: String, to name: String) async {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = folders.firstIndex(where: { $0.id == id }), !clean.isEmpty, clean != folders[index].name
    else { return }
    let previous = folders[index].name
    folders[index].name = clean
    do {
      let response = try await client.send(NotesEndpoints.renameFolder(id: id, name: clean))
      error = nil
      replace(response.folder)
    } catch {
      if let index = folders.firstIndex(where: { $0.id == id }), folders[index].name == clean {
        folders[index].name = previous
      }
      fail("Rename folder", error)
    }
  }

  /// Refuses locally what the server would refuse (`lib/notesTree.ts:114-131`),
  /// with the server's words; otherwise applies at once and undoes on error.
  func moveFolder(_ id: String, to parentId: String?) async {
    guard let index = folders.firstIndex(where: { $0.id == id }), folders[index].parentId != parentId else { return }
    if let refusal = NotesTree.refuseMove(folders, id: id, to: parentId) {
      error = refusal.message
      return
    }
    let previous = folders[index].parentId
    folders[index].parentId = parentId
    do {
      let response = try await client.send(NotesEndpoints.moveFolder(id: id, parentId: parentId))
      error = nil
      replace(response.folder)
      if let parentId { expanded.insert(parentId) }
    } catch {
      if let index = folders.firstIndex(where: { $0.id == id }), folders[index].parentId == parentId {
        folders[index].parentId = previous
      }
      fail("Move folder", error)
    }
  }

  /// Called after the confirmation. The notes inside go to "Sem pasta".
  func deleteFolder(_ id: String) async {
    let inside = Set(NotesTree.descendantIDs(folders, of: id))
    do {
      _ = try await client.send(NotesEndpoints.deleteFolder(id: id))
    } catch {
      Logger.notes.error("Delete folder failed: \(error.userMessage, privacy: .public)")
      self.error = "Falha ao apagar a pasta"
      return
    }
    error = nil
    folders.removeAll { inside.contains($0.id) }
    for index in notes.indices where notes[index].folderId.map(inside.contains) ?? false {
      notes[index].folderId = nil
    }
    if let current = scope.folderID, inside.contains(current) { scope = .all }
  }

  func deletionPrompt(forFolder id: String) -> (title: String, message: String, confirmLabel: String)? {
    guard let folder = folders.first(where: { $0.id == id }) else { return nil }
    return NotesTree.deletionPrompt(for: folder, folders: folders, notes: notes)
  }

  // MARK: - Tree navigation

  func toggle(_ key: String) {
    if expanded.remove(key) == nil { expanded.insert(key) }
  }

  // MARK: - Search

  func setSearchText(_ text: String) {
    searchText = text
    searchTask?.cancel()
    let sleep = self.sleep
    searchTask = Task { [weak self] in
      do {
        try await sleep(Self.searchDelay)
      } catch {
        // A newer keystroke replaced this wait.
        return
      }
      self?.query = text
    }
  }

  // MARK: - Drive status

  /// The screen is on screen or not; the Drive status is polled only while it is.
  func setVisible(_ visible: Bool) {
    isVisible = visible
    updateSyncPolling()
  }

  func pollSync() async {
    do {
      setSync(try await client.send(NotesEndpoints.sync).sync)
    } catch {
      // A status read; the next round tries again, as on the web.
      Logger.notes.debug("Notes sync status failed: \(error.userMessage, privacy: .public)")
    }
  }

  private func setSync(_ value: NotesSyncStatus) {
    sync = value
    updateSyncPolling()
  }

  private func updateSyncPolling() {
    let wanted = isVisible && sync?.connected == true
    guard wanted != isPollingSync else { return }
    isPollingSync = wanted
    if wanted {
      poller.register(
        Poller.ScopeID.notesSync, foreground: Poller.Cadence.notesSync, background: nil
      ) { [weak self] in
        await self?.pollSync()
      }
    } else {
      poller.unregister(Poller.ScopeID.notesSync)
    }
  }

  // MARK: - Helpers

  private func replace(_ note: Note) {
    guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
    notes[index] = note
  }

  private func replace(_ folder: NoteFolder) {
    guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
    folders[index] = folder
  }

  private func update(_ id: String, _ change: (inout Note) -> Void) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    change(&notes[index])
  }

  private func fail(_ action: String, _ error: APIError) {
    Logger.notes.error("\(action, privacy: .public) failed: \(error.userMessage, privacy: .public)")
    self.error = error.userMessage
  }
}

nonisolated extension Logger {
  static let notes = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureNotes")
}
