import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureNotes

@MainActor
@Suite struct NotesStoreTests {
  let clock = VirtualClock()
  let client: FakeAPIClient
  let poller: Poller
  let store: NotesStore

  nonisolated static let notes = [
    note("n1", "Primeira", "um", folder: nil),
    note("n2", "Segunda", "dois", folder: "f1"),
    note("n3", "Terceira", "três", folder: nil),
  ]
  nonisolated static let folders = [folder("f1", name: "Trabalho"), folder("f2", parent: "f1", name: "Clientes")]

  init() {
    let clock = self.clock
    client = FakeAPIClient(handler: Self.server())
    poller = Poller(sleep: { try await clock.sleep($0) })
    store = NotesStore(client: client, poller: poller, sleep: { try await clock.sleep($0) })
  }

  /// A server that answers the list and echoes writes back.
  nonisolated static func server(
    sync: NotesSyncStatus = disconnected,
    failing: (@Sendable (FakeAPIClient.Call) -> APIError?)? = nil
  ) -> FakeAPIClient.Handler {
    { call throws(APIError) in
      if let error = failing?(call) { throw error }
      switch (call.method, call.path) {
      case ("GET", "/api/notes"):
        return FakeAPIClient.json(NotesResponse(notes: notes, folders: folders, sync: sync))
      case ("GET", "/api/notes/sync"):
        return FakeAPIClient.json(NotesSyncResponse(sync: sync))
      case ("POST", "/api/notes"):
        let body = decode(call.body)
        return FakeAPIClient.json(
          NoteResponse(note: note("new", body["title"] as? String ?? "", "", folder: body["folderId"] as? String)))
      case ("PUT", "/api/notes"):
        let ids = decode(call.body)["ids"] as? [String] ?? []
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return FakeAPIClient.json(NoteListResponse(notes: ids.compactMap { byID[$0] }))
      case ("POST", "/api/notes/folders"):
        let body = decode(call.body)
        return FakeAPIClient.json(
          NoteFolderResponse(folder: folder("nova", parent: body["parentId"] as? String, name: "Nova pasta")))
      case ("PATCH", let path) where path.hasPrefix("/api/notes/folders/"):
        let id = String(path.dropFirst("/api/notes/folders/".count))
        var current = folders.first { $0.id == id } ?? folder(id)
        let body = decode(call.body)
        if let name = body["name"] as? String { current.name = name }
        if body.keys.contains("parentId") { current.parentId = body["parentId"] as? String }
        return FakeAPIClient.json(NoteFolderResponse(folder: current))
      case ("PATCH", let path):
        let id = String(path.dropFirst("/api/notes/".count))
        var current = notes.first { $0.id == id } ?? note(id)
        let body = decode(call.body)
        if let title = body["title"] as? String { current.title = title }
        if let text = body["body"] as? String { current.body = text }
        if body.keys.contains("folderId") { current.folderId = body["folderId"] as? String }
        return FakeAPIClient.json(NoteResponse(note: current))
      default:
        return FakeAPIClient.ok
      }
    }
  }

  nonisolated static func decode(_ body: String?) -> [String: Any] {
    guard let body else { return [:] }
    do {
      return try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] ?? [:]
    } catch {
      preconditionFailure("Request body is not JSON: \(error)")
    }
  }

  private func loaded() async -> NotesStore {
    await store.load()
    return store
  }

  // MARK: - Loading

  @Test func loadsTheListAndOpensTheFirstNote() async {
    let store = await loaded()
    #expect(client.calls.map(\.description) == ["GET /api/notes -"])
    #expect(store.notes.map(\.id) == ["n1", "n2", "n3"])
    #expect(store.folders.count == 2)
    #expect(store.activeID == "n1")
    #expect(store.draft == "um")
    #expect(store.hasLoaded)
  }

  @Test func loadFailureKeepsTheServerMessage() async {
    client.respond { _ throws(APIError) in throw serverError("Falha ao carregar as notas", status: 500) }
    await store.load()
    #expect(!store.hasLoaded)
    #expect(store.error == "Falha ao carregar as notas")
  }

  @Test func reloadKeepsTheDraftOfTheOpenNote() async {
    let store = await loaded()
    store.edit("um e mais")
    await store.load()
    #expect(store.activeID == "n1")
    #expect(store.draft == "um e mais")
  }

  @Test func activatingANoteOpensItAndShowsItsFolder() async {
    let store = await loaded()
    await store.load(activate: "n2")
    #expect(store.activeID == "n2")
    #expect(store.draft == "dois")
    #expect(store.expanded.contains("f1"))
  }

  // MARK: - Autosave

  @Test func autosaveWaitsForTypingToStop() async {
    let store = await loaded()
    store.edit("u")
    await clock.advance(by: .milliseconds(500))
    store.edit("um!")
    #expect(store.saveState == .saving)
    await clock.advance(by: .milliseconds(699))
    #expect(client.writes.isEmpty)

    await clock.advance(by: .milliseconds(1))
    #expect(client.writes.map(\.description) == [#"PATCH /api/notes/n1 {"body":"um!"}"#])
    #expect(store.saveState == .saved)
    #expect(store.notes.first?.body == "um!")
  }

  @Test func openingAnotherNoteFlushesThePendingText() async {
    let store = await loaded()
    store.edit("um!")
    await store.open("n3")
    #expect(client.writes.map(\.description) == [#"PATCH /api/notes/n1 {"body":"um!"}"#])
    #expect(store.activeID == "n3")
    #expect(store.draft == "três")

    await clock.advance(by: .seconds(1))
    #expect(client.writes.count == 1)
  }

  @Test func flushSendsAtOnceAndOnlyOnce() async {
    let store = await loaded()
    store.edit("um!")
    await store.flushPending()
    await store.flushPending()
    await clock.advance(by: .seconds(1))
    #expect(client.writes.count == 1)
  }

  @Test func failedSaveShowsTheServerLimitMessage() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { call in
        call.method == "PATCH" ? serverError("a nota aceita até 100000 caracteres") : nil
      }))
    store.edit(String(repeating: "x", count: 100_001))
    await clock.advance(by: NotesStore.autosaveDelay)
    #expect(store.saveState == .failed)
    #expect(store.error == "a nota aceita até 100000 caracteres")
    #expect(store.statusText == "não salvo")
  }

  // MARK: - Notes

  @Test func createsANoteInTheScopeFolder() async {
    let store = await loaded()
    await store.createNote()
    store.scope = .folder("f1")
    await store.createNote()
    #expect(
      client.writes.map(\.description) == [
        #"POST /api/notes {"folderId":null,"title":"Nota 4"}"#,
        #"POST /api/notes {"folderId":"f1","title":"Nota 5"}"#,
      ])
    #expect(store.activeID == "new")
    #expect(store.draft == "")
    #expect(store.editorFocusRequest == 2)
  }

  @Test func createLimitShowsTheServerMessage() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { $0.method == "POST" ? serverError("o limite é de 100 notas") : nil }))
    await store.createNote()
    #expect(store.error == "o limite é de 100 notas")
    #expect(store.notes.count == 3)
  }

  @Test func renamesWithATrimmedTitleAndIgnoresAnEmptyOne() async {
    let store = await loaded()
    await store.renameNote("n1", to: "   ")
    await store.renameNote("n1", to: "  Nova  ")
    #expect(client.writes.map(\.description) == [#"PATCH /api/notes/n1 {"title":"Nova"}"#])
    #expect(store.notes.first?.title == "Nova")
  }

  @Test func failedRenameRollsBack() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { $0.method == "PATCH" ? serverError("o título aceita até 120 caracteres") : nil }))
    await store.renameNote("n1", to: String(repeating: "t", count: 121))
    #expect(store.notes.first?.title == "Primeira")
    #expect(store.error == "o título aceita até 120 caracteres")
  }

  @Test func movesSendExplicitNullForSemPasta() async {
    let store = await loaded()
    await store.moveNote("n2", to: nil)
    await store.moveNote("n1", to: "f2")
    #expect(
      client.writes.map(\.description) == [
        #"PATCH /api/notes/n2 {"folderId":null}"#,
        #"PATCH /api/notes/n1 {"folderId":"f2"}"#,
      ])
    #expect(store.notes.first { $0.id == "n1" }?.folderId == "f2")
    #expect(store.expanded.contains("f2"))
  }

  @Test func failedMoveRollsBack() async {
    let store = await loaded()
    client.respond(Self.server(failing: { $0.method == "PATCH" ? serverError("pasta não encontrada") : nil }))
    await store.moveNote("n1", to: "f1")
    #expect(store.notes.first { $0.id == "n1" }?.folderId == nil)
    #expect(store.error == "pasta não encontrada")
  }

  @Test func moveFlushesThePendingTextFirst() async {
    let store = await loaded()
    store.edit("um!")
    await store.moveNote("n1", to: "f1")
    #expect(
      client.writes.map(\.description) == [
        #"PATCH /api/notes/n1 {"body":"um!"}"#,
        #"PATCH /api/notes/n1 {"folderId":"f1"}"#,
      ])
  }

  @Test func dropOnANoteReordersWithTheWholeList() async {
    let store = await loaded()
    await store.dropNote("n3", before: "n1")
    #expect(client.writes.map(\.description) == [#"PUT /api/notes {"ids":["n3","n1","n2"]}"#])
    #expect(store.notes.map(\.id) == ["n3", "n1", "n2"])
  }

  @Test func dropInAnotherFolderMovesThenReorders() async {
    let store = await loaded()
    await store.dropNote("n3", before: "n2")
    #expect(
      client.writes.map(\.description) == [
        #"PATCH /api/notes/n3 {"folderId":"f1"}"#,
        #"PUT /api/notes {"ids":["n1","n3","n2"]}"#,
      ])
  }

  @Test func shiftSwapsWithTheSiblingInTheSameFolder() async {
    let store = await loaded()
    #expect(!store.canShiftNote("n1", by: -1))
    #expect(store.canShiftNote("n1", by: 1))
    #expect(!store.canShiftNote("n2", by: 1))
    await store.shiftNote("n1", by: 1)
    #expect(client.writes.map(\.description) == [#"PUT /api/notes {"ids":["n3","n2","n1"]}"#])
  }

  @Test func failedReorderRestoresTheOrder() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { $0.method == "PUT" ? serverError("ids precisa ser uma lista de textos") : nil }))
    await store.dropNote("n3", before: "n1")
    #expect(store.notes.map(\.id) == ["n1", "n2", "n3"])
    #expect(store.error == "ids precisa ser uma lista de textos")
  }

  @Test func deletesAndOpensTheNextNote() async {
    let store = await loaded()
    store.edit("pendente")
    await store.deleteNote("n1")
    await clock.advance(by: .seconds(1))
    #expect(client.writes.map(\.description) == ["DELETE /api/notes/n1 -"])
    #expect(store.activeID == "n2")
    #expect(store.draft == "dois")
  }

  @Test func failedDeleteUsesTheWebText() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { $0.method == "DELETE" ? serverError("nota não encontrada", status: 404) : nil }))
    await store.deleteNote("n1")
    #expect(store.error == "Falha ao apagar a nota")
    #expect(store.notes.count == 3)
  }

  @Test func idsAreEncodedAsOnePathSegment() async {
    let store = await loaded()
    await store.deleteNote("a/b")
    #expect(client.writes.last?.path == "/api/notes/a%2Fb")
  }

  // MARK: - Folders

  @Test func createsAFolderAndStartsRenamingIt() async {
    let store = await loaded()
    await store.createFolder(in: nil)
    await store.createFolder(in: "f1")
    #expect(
      client.writes.map(\.description) == [
        #"POST /api/notes/folders {"name":"Nova pasta","parentId":null}"#,
        #"POST /api/notes/folders {"name":"Nova pasta","parentId":"f1"}"#,
      ])
    #expect(store.renaming == "nova")
    #expect(store.expanded.contains("f1"))
  }

  @Test func renamesAndMovesFolders() async {
    let store = await loaded()
    await store.renameFolder("f2", to: " Contas ")
    #expect(store.folders.first { $0.id == "f2" }?.name == "Contas")
    await store.moveFolder("f2", to: nil)
    #expect(
      client.writes.map(\.description) == [
        #"PATCH /api/notes/folders/f2 {"name":"Contas"}"#,
        #"PATCH /api/notes/folders/f2 {"parentId":null}"#,
      ])
    #expect(store.folders.first { $0.id == "f2" }?.parentId == nil)
  }

  @Test func refusedFolderMoveNeverReachesTheServer() async {
    let store = await loaded()
    await store.moveFolder("f1", to: "f2")
    #expect(client.writes.isEmpty)
    #expect(store.error == "uma pasta não pode ir para dentro de si mesma")
  }

  @Test func failedFolderRenameAndMoveRollBack() async {
    let store = await loaded()
    client.respond(
      Self.server(failing: { $0.method == "PATCH" ? serverError("o nome da pasta aceita até 60 caracteres") : nil }))
    await store.renameFolder("f1", to: String(repeating: "n", count: 61))
    await store.moveFolder("f2", to: nil)
    #expect(store.folders.first { $0.id == "f1" }?.name == "Trabalho")
    #expect(store.folders.first { $0.id == "f2" }?.parentId == "f1")
    #expect(store.error == "o nome da pasta aceita até 60 caracteres")
  }

  @Test func deletingAFolderSendsItsNotesToSemPasta() async {
    let store = await loaded()
    store.scope = .folder("f2")
    await store.deleteFolder("f1")
    #expect(client.writes.map(\.description) == ["DELETE /api/notes/folders/f1 -"])
    #expect(store.folders.isEmpty)
    #expect(store.notes.allSatisfy { $0.folderId == nil })
    #expect(store.scope == .all)
  }

  // MARK: - Search

  @Test func searchWaitsForAPauseInTyping() async {
    let store = await loaded()
    store.setSearchText("ter")
    await clock.advance(by: .milliseconds(200))
    store.setSearchText("terc")
    await clock.advance(by: .milliseconds(249))
    #expect(!store.isSearching)
    await clock.advance(by: .milliseconds(1))
    #expect(store.query == "terc")
    #expect(store.searchResults.map(\.id) == ["n3"])
  }

  @Test func searchCanBeLimitedToTheScopeFolder() async {
    let store = await loaded()
    store.setSearchText("a")
    await clock.advance(by: NotesStore.searchDelay)
    store.scope = .folder("f1")
    #expect(store.searchResults.count == 3)
    store.onlyInFolder = true
    #expect(store.searchResults.map(\.id) == ["n2"])
  }

  // MARK: - Drive status

  @Test func describesTheDriveCopy() {
    let connected = NotesSyncStatus(connected: true, account: "a", pending: 0, lastError: nil, lastSyncedAt: nil)
    #expect(NotesStore.statusText(saveState: .saved, sync: connected) == "salvo · no Google Drive")
    var sending = connected
    sending.pending = 2
    #expect(NotesStore.statusText(saveState: .saving, sync: sending) == "salvando… · enviando ao Drive…")
    var broken = connected
    broken.lastError = "cota excedida"
    #expect(NotesStore.statusText(saveState: .saved, sync: broken) == "salvo · Drive: cota excedida")
    #expect(NotesStore.statusText(saveState: .failed, sync: broken) == "não salvo")
    #expect(NotesStore.statusText(saveState: .saved, sync: disconnected) == "salvo")
  }

  @Test func pollsTheDriveOnlyWhileVisibleAndConnected() async {
    let connected = NotesSyncStatus(connected: true, account: "a", pending: 1, lastError: nil, lastSyncedAt: nil)
    client.respond(Self.server(sync: connected))
    poller.start()
    await store.load()
    #expect(!poller.registeredScopes.contains(Poller.ScopeID.notesSync))

    store.setVisible(true)
    #expect(poller.registeredScopes.contains(Poller.ScopeID.notesSync))
    await clock.advance(by: .seconds(20))
    let polls = client.calls.filter { $0.path == "/api/notes/sync" }.count
    #expect(polls == 3)

    store.setVisible(false)
    #expect(!poller.registeredScopes.contains(Poller.ScopeID.notesSync))
    await clock.advance(by: .seconds(30))
    #expect(client.calls.filter { $0.path == "/api/notes/sync" }.count == polls)
    poller.stop()
  }

  @Test func doesNotPollWhenTheDriveIsNotConnected() async {
    let store = await loaded()
    store.setVisible(true)
    #expect(!poller.registeredScopes.contains(Poller.ScopeID.notesSync))
  }
}
