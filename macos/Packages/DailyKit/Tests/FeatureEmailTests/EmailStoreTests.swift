import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Synchronization
import Testing

@testable import FeatureEmail

/// The server side of a test: what `GET /api/state` answers and how every
/// other call is answered.
nonisolated final class FakeServer: Sendable {
  typealias Route = @Sendable (FakeAPIClient.Call) throws(APIError) -> Data?
  private let state: Mutex<(dashboard: DashboardState, route: Route)>

  init(_ dashboard: DashboardState) {
    state = Mutex((dashboard, { _ in nil }))
  }

  func setState(_ dashboard: DashboardState) { state.withLock { $0.dashboard = dashboard } }
  func route(_ route: @escaping Route) { state.withLock { $0.route = route } }

  func answer(_ call: FakeAPIClient.Call) throws(APIError) -> Data {
    let (dashboard, route) = state.withLock { ($0.dashboard, $0.route) }
    if call.path == "/api/state" { return FakeAPIClient.json(dashboard) }
    return try route(call) ?? FakeAPIClient.ok
  }
}

@MainActor
@Suite struct EmailStoreTests {
  let client = FakeAPIClient()
  let toasts = quietToasts()
  let navigator = AppNavigator()
  let dashboard: DashboardStore
  let store: EmailStore
  let server: FakeServer
  let failure = APIError.server(status: 500, message: "falhou", code: nil, retry: nil)

  static let inbox = [
    envelope("1", subject: "Relatório", unread: true, date: "2026-10-04T10:00:00", folder: "INBOX"),
    envelope("2", subject: "Agenda", unread: true, date: "2026-10-04T09:00:00", folder: "INBOX"),
    envelope("3", account: "mail-2", accountLabel: "Pessoal", subject: "Viagem", date: "2026-10-04T08:00:00"),
  ]

  static func state(_ inbox: [EmailEnvelope] = inbox) -> DashboardState {
    DashboardState(
      updatedAt: "x", modules: [.email],
      mailboxes: [MailboxRef(id: "mail-1", label: "Trabalho"), MailboxRef(id: "mail-2", label: "Pessoal")],
      email: PanelResult(data: inbox, error: nil))
  }

  init() {
    let server = FakeServer(Self.state())
    self.server = server
    client.respond { call throws(APIError) in try server.answer(call) }
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    store = EmailStore(
      client: client, dashboard: dashboard, toasts: toasts, navigator: navigator,
      now: { localDate("2026-10-04T15:00:00") },
      timeZone: saoPaulo)
    dashboard.apply(Self.state())
  }

  var unread: [String: Bool] {
    Dictionary(uniqueKeysWithValues: (dashboard.state?.email.data ?? []).map { ($0.id, $0.unread) })
  }

  func batchBody(_ ids: [(String, String)], _ action: String, folder: String? = nil, path: String = "INBOX") -> String {
    let targets = ids.map { #"{"account":"\#($0.0)","id":"\#($0.1)"}"# }.joined(separator: ",")
    let folderPart = folder.map { #""folder":"\#($0)","# } ?? ""
    return #"{"action":"\#(action)",\#(folderPart)"folderPath":"\#(path)","targets":[\#(targets)]}"#
  }

  nonisolated static func results(_ items: [EmailBatchResult]) -> Data {
    FakeAPIClient.json(EmailBatchResponse(results: items))
  }

  // MARK: - Batch

  @Test func batchReadMarksAtOnceThenReloads() async {
    server.route { call in
      call.path == "/api/email/batch"
        ? Self.results([.init(account: "mail-1", id: "1", ok: true), .init(account: "mail-1", id: "2", ok: true)])
        : nil
    }
    var read = Self.inbox
    read[0].unread = false
    read[1].unread = false
    server.setState(Self.state(read))
    store.select(.click("mail-1:1"))
    store.select(.click("mail-1:2", shift: true))

    await store.runBatch(.read)

    #expect(
      client.calls.filter { $0.path == "/api/email/batch" }
        == [.init("POST", "/api/email/batch", body: batchBody([("mail-1", "1"), ("mail-1", "2")], "read"))])
    #expect(unread == ["1": false, "2": false, "3": false])
    #expect(store.selection == .empty)
    #expect(store.unprocessed.isEmpty)
    #expect(client.calls.last?.path == "/api/state")
  }

  @Test func partialFailureKeepsTheFailedSelectedAndRetriesOnlyThem() async {
    server.route { call in
      call.path == "/api/email/batch"
        ? Self.results([
          .init(account: "mail-1", id: "1", ok: true),
          .init(account: "mail-1", id: "2", ok: false, error: "id inválido"),
        ]) : nil
    }
    store.select(.all)
    await store.runBatch(.delete)

    #expect(store.unprocessed == [.init(account: "mail-1", id: "2", ok: false, error: "id inválido")])
    #expect(store.selection.selected == ["mail-1:2"])
    // The reload brings the server's truth back.
    #expect(dashboard.state?.email.data?.count == 3)

    server.route { call in
      call.path == "/api/email/batch" ? Self.results([.init(account: "mail-1", id: "2", ok: true)]) : nil
    }
    await store.retryUnprocessed()
    #expect(
      client.calls.filter { $0.path == "/api/email/batch" }.last?.body == batchBody([("mail-1", "2")], "delete"))
    #expect(store.unprocessed.isEmpty)
  }

  @Test func serverErrorRollsBackAndToasts() async {
    let failure = self.failure
    server.route { call throws(APIError) in
      if call.path == "/api/email/batch" { throw failure }
      return nil
    }
    store.select(.click("mail-1:1"))
    await store.runBatch(.read)

    #expect(unread == ["1": true, "2": true, "3": false])
    #expect(toasts.toasts.map(\.text) == ["falhou"])
    #expect(store.selection.selected == ["mail-1:1"])
    #expect(!client.calls.contains { $0.path == "/api/state" })
  }

  @Test func deleteAsksFirst() async {
    store.select(.click("mail-1:1"))
    store.select(.click("mail-1:2", meta: true))
    store.requestDeleteSelected()
    guard let request = store.confirmation else {
      Issue.record("No confirmation")
      return
    }
    #expect(request.title == "Excluir estes 2 e-mails?")
    #expect(request.message == "Os enviados ficam: sua cópia do que escreveu não é lixo da caixa.")
    #expect(request.confirmLabel == "Excluir")
    #expect(request.destructive)
    #expect(!client.calls.contains { $0.path == "/api/email/batch" })

    request.onConfirm()
    await settle()
    let batches = client.calls.filter { $0.path == "/api/email/batch" }
    #expect(batches.map(\.body) == [batchBody([("mail-1", "1"), ("mail-1", "2")], "delete")])
  }

  @Test func deleteWithoutSelectionDoesNothing() {
    store.requestDeleteSelected()
    #expect(store.confirmation == nil)
  }

  /// The screen and the Início panels (any window) share the store: only the
  /// host whose control asked presents the question.
  @Test func onlyTheAskingHostPresentsTheDialogs() {
    let screen = UUID()
    let panel = UUID()
    #expect(store.presentsDialogs(screen) && store.presentsDialogs(panel))

    store.select(.click("mail-1:1"))
    store.requestDeleteSelected(presenter: panel)
    #expect(store.confirmation != nil)
    #expect(store.presentsDialogs(panel))
    #expect(!store.presentsDialogs(screen))

    let big = MailboxNode(
      path: "Arquivo", name: "Arquivo", delimiter: "/", parent: nil, specialUse: nil, total: 30, unread: 25)
    store.requestMarkFolderRead(account: "mail-1", node: big, presenter: screen)
    #expect(store.presentsDialogs(screen))
    #expect(!store.presentsDialogs(panel))

    // A request without a host lets any of them present it.
    store.requestDeleteSelected()
    #expect(store.presentsDialogs(screen) && store.presentsDialogs(panel))
  }

  @Test func theMoveSheetBelongsToTheAskingHost() async {
    server.route { call in
      call.path == "/api/email/folders" ? FakeAPIClient.json(EmailFoldersResponse(folders: ["Arquivo"])) : nil
    }
    let screen = UUID()
    let panel = UUID()
    store.select(.click("mail-1:1"))
    await settle()
    store.requestMoveSelected(presenter: screen)
    #expect(store.isMoveSheetPresented)
    #expect(store.presentsDialogs(screen))
    #expect(!store.presentsDialogs(panel))
  }

  @Test func moveSheetNeedsDestinations() async {
    server.route { call in
      call.path == "/api/email/folders"
        ? FakeAPIClient.json(EmailFoldersResponse(folders: ["Arquivo", "Clientes"])) : nil
    }
    store.requestMoveSelected()
    #expect(!store.isMoveSheetPresented)

    store.select(.click("mail-1:1"))
    await settle()
    #expect(client.actionCalls.contains(.init("GET", "/api/email/folders", query: "account=mail-1")))
    #expect(store.moveFolders == ["Arquivo", "Clientes"])
    store.requestMoveSelected()
    #expect(store.isMoveSheetPresented)

    store.targetFolder = "Clientes"
    await store.confirmMoveSelected()
    #expect(!store.isMoveSheetPresented)
    #expect(
      client.calls.filter { $0.path == "/api/email/batch" }.last?.body
        == batchBody([("mail-1", "1")], "move", folder: "Clientes"))
  }

  // MARK: - Drag

  @Test func dragOfAnUnselectedRowSelectsItAndDropsOnAnAction() async {
    store.select(.click("mail-1:2"))
    _ = store.beginDrag("mail-1:1")
    #expect(store.selection.selected == ["mail-1:1"])
    #expect(store.dragging == "mail-1:1")

    await store.dropOnAction(.unread)
    #expect(store.dragging == nil)
    #expect(client.calls.first { $0.path == "/api/email/batch" }?.body == batchBody([("mail-1", "1")], "unread"))
  }

  @Test func dropOnFolderRefusesWhatIMAPCannotMove() async {
    store.select(.all)
    _ = store.beginDrag("mail-1:1")
    await store.dropOnFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    #expect(store.batchError == "Essas mensagens são de contas diferentes: mova uma conta por vez.")

    store.select(.click("mail-1:1"))
    await store.dropOnFolder(FolderSelection(account: "mail-2", path: "Arquivo"))
    #expect(store.batchError == "Só dá para mover entre pastas da mesma conta.")

    await store.dropOnFolder(FolderSelection(account: "mail-1", path: "INBOX"))
    #expect(store.batchError == "A mensagem já está nessa pasta.")
    #expect(client.actionCalls.filter { $0.path == "/api/email/batch" }.isEmpty)

    await store.dropOnFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    #expect(
      client.calls.first { $0.path == "/api/email/batch" }?.body
        == batchBody([("mail-1", "1")], "move", folder: "Arquivo"))
    #expect(dashboard.state?.email.data?.map(\.id) == ["1", "2", "3"])
  }

  @Test func dropOnFolderComparesTheAccountNotOnlyThePath() async {
    let inFolder = [envelope("7", subject: "Pasta", folder: "Arquivo")]
    server.route { call in
      call.path == "/api/email/messages"
        ? FakeAPIClient.json(EmailMessagesResponse(messages: inFolder, uidvalidity: "1", reindexed: false)) : nil
    }
    // The dashboard inbox holds both accounts: another account's INBOX is not "here".
    store.select(.click("mail-1:1"))
    await store.dropOnFolder(FolderSelection(account: "mail-2", path: "INBOX"))
    #expect(store.batchError == "Só dá para mover entre pastas da mesma conta.")
    store.select(.click("mail-2:3"))
    await store.dropOnFolder(FolderSelection(account: "mail-2", path: "INBOX"))
    #expect(store.batchError == "A mensagem já está nessa pasta.")

    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    store.select(.click("mail-1:7"))
    await store.dropOnFolder(FolderSelection(account: "mail-2", path: "Arquivo"))
    #expect(store.batchError == "Só dá para mover entre pastas da mesma conta.")
    #expect(client.actionCalls.filter { $0.path == "/api/email/batch" }.isEmpty)
  }

  // MARK: - Notification target

  @Test func revealsTheMessageANotificationPointsAt() async {
    let inFolder = [envelope("7", subject: "Pasta", folder: "Arquivo")]
    server.route { call in
      call.path == "/api/email/messages"
        ? FakeAPIClient.json(EmailMessagesResponse(messages: inFolder, uidvalidity: "1", reindexed: false)) : nil
    }
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    store.filters.account = "mail-1"
    navigator.open(.module(.email), itemID: "mail-2:3")
    store.revealPending()
    #expect(store.folder == nil)
    #expect(store.filters.account == nil)
    #expect(store.selection.selected == ["mail-2:3"])
    #expect(store.openKey == "mail-2:3")
    #expect(navigator.pending == nil)
  }

  @Test func keepsTheEmailRequestUntilTheInboxArrives() {
    dashboard.apply(
      DashboardState(
        updatedAt: "x", modules: [.email], mailboxes: [MailboxRef(id: "mail-1", label: "Trabalho")],
        email: PanelResult(data: nil, error: "IMAP fora do ar")))
    navigator.open(.module(.email), itemID: "mail-1:2")
    store.revealPending()
    #expect(store.pendingItemID == "mail-1:2")
    #expect(store.openKey == nil)

    dashboard.apply(Self.state())
    store.revealPending()
    #expect(store.openKey == "mail-1:2")
    #expect(navigator.pending == nil)
  }

  @Test func finishesAnEmailRequestForAMessageThatIsGone() {
    navigator.open(.module(.email), itemID: "mail-1:99")
    store.revealPending()
    #expect(store.openKey == nil)
    #expect(store.selection == .empty)
    #expect(navigator.pending == nil)
  }

  // MARK: - Folders

  @Test func mailboxesShowStoredThenSynced() async {
    let stored = [
      MailboxNode(path: "INBOX", name: "Inbox", delimiter: "/", parent: nil, specialUse: nil, total: 1, unread: 0)
    ]
    let synced =
      stored + [
        MailboxNode(path: "Arquivo", name: "Arquivo", delimiter: "/", parent: nil, specialUse: nil, total: 3, unread: 2)
      ]
    let failure = self.failure
    server.route { call throws(APIError) in
      guard call.path == "/api/email/mailboxes" else { return nil }
      if call.query.hasPrefix("account=mail-2") {
        if call.query.hasSuffix("sync=1") { throw .timedOut }
        throw failure
      }
      return FakeAPIClient.json(
        MailboxesResponse(mailboxes: call.query.hasSuffix("sync=1") ? synced : stored, syncedAt: nil, cached: true))
    }
    await store.loadMailboxes()

    let groups = store.groups
    #expect(groups.map(\.account.label) == ["Trabalho", "Pessoal"])
    #expect(groups[0].mailboxes.map(\.path) == ["INBOX", "Arquivo"])
    #expect(groups[0].error == nil && !groups[0].loading && !groups[0].syncing)
    #expect(groups[1].error == "a conta demorou demais para responder")
    #expect(
      Set(client.actionCalls.map(\.query)) == [
        "account=mail-1", "account=mail-1&sync=1", "account=mail-2", "account=mail-2&sync=1",
      ])
  }

  @Test func openingTheOnlyInboxShowsTheDashboard() async {
    var single = Self.state()
    single.mailboxes = [MailboxRef(id: "mail-1", label: "Trabalho")]
    dashboard.apply(single)
    await store.openFolder(FolderSelection(account: "mail-1", path: "INBOX"))
    #expect(store.folder == nil)
    #expect(client.actionCalls.isEmpty)
    #expect(store.folderTitle == "Inbox")
  }

  @Test func openFolderReadsItsMessages() async {
    let inFolder = [envelope("7", subject: "Pasta", folder: "Arquivo")]
    server.route { call in
      call.path == "/api/email/messages"
        ? FakeAPIClient.json(EmailMessagesResponse(messages: inFolder, uidvalidity: "1", reindexed: false)) : nil
    }
    store.select(.click("mail-1:1"))
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    #expect(store.selection == .empty)
    #expect(client.actionCalls.last == .init("GET", "/api/email/messages", query: "account=mail-1&folder=Arquivo"))
    #expect(store.all == inFolder)
    #expect(store.folderPath == "Arquivo")
    #expect(!store.folderLoading)
  }

  @Test func folderErrorIsShownAndFolderBatchRollsBack() async {
    let inFolder = [envelope("7", subject: "Pasta", unread: true, folder: "Arquivo")]
    let failure = self.failure
    server.route { call throws(APIError) in
      if call.path == "/api/email/messages" {
        return FakeAPIClient.json(EmailMessagesResponse(messages: inFolder, uidvalidity: "1", reindexed: false))
      }
      if call.path == "/api/email/batch" { throw failure }
      return nil
    }
    await store.openFolder(FolderSelection(account: "mail-1", path: "Arquivo"))
    store.select(.all)
    await store.runBatch(.delete)
    #expect(store.all == inFolder)
    #expect(
      client.calls.first { $0.path == "/api/email/batch" }?.body
        == batchBody([("mail-1", "7")], "delete", path: "Arquivo"))

    server.route { _ throws(APIError) in throw .timedOut }
    await store.loadFolder()
    #expect(store.folderError == "a pasta demorou demais para responder")
  }

  @Test func markFolderReadAsksAboveTwenty() async {
    let big = MailboxNode(
      path: "Arquivo", name: "Arquivo", delimiter: "/", parent: nil, specialUse: nil, total: 30, unread: 25)
    store.requestMarkFolderRead(account: "mail-1", node: big)
    #expect(store.confirmation?.title == "Marcar 25 mensagens como lidas?")
    #expect(
      store.confirmation?.message
        == "Vale para a pasta Arquivo inteira, inclusive o que ainda não foi carregado aqui.")
    #expect(store.confirmation?.confirmLabel == "Marcar como lidas")
    #expect(client.actionCalls.isEmpty)

    await store.markFolderRead(account: "mail-1", node: big)
    #expect(
      client.actionCalls.first
        == .init("POST", "/api/email/folder/read", body: #"{"account":"mail-1","folder":"Arquivo"}"#))

    let failure = APIError.server(status: 404, message: "pasta não encontrada", code: nil, retry: nil)
    server.route { call throws(APIError) in
      if call.path == "/api/email/folder/read" { throw failure }
      return nil
    }
    await store.markFolderRead(account: "mail-1", node: big)
    #expect(store.batchError == "pasta não encontrada")
  }

  // MARK: - One conversation

  @Test func tagAppliesToTheConversation() async {
    server.route { call in
      call.path == "/api/email/batch" ? Self.results([.init(account: "mail-1", id: "1", ok: true)]) : nil
    }
    guard let thread = store.listing.threads.first(where: { $0.id == "mail-1:1" }) else {
      Issue.record("No thread")
      return
    }
    await store.applyTag("Clientes", to: thread)
    #expect(
      client.calls.first { $0.path == "/api/email/batch" }?.body
        == batchBody([("mail-1", "1")], "tag", folder: "Clientes"))
    #expect(store.tags(of: thread) == ["Clientes"])

    server.route { call in
      call.path == "/api/email/batch"
        ? Self.results([.init(account: "mail-1", id: "1", ok: false, error: "pasta de destino não encontrada")]) : nil
    }
    await store.applyTag("Outra", to: thread)
    #expect(store.batchError == "pasta de destino não encontrada")
    #expect(store.tags(of: thread) == ["Clientes"])
  }

  @Test func deletingOneConversationAsksWithItsSize() async {
    let thread = EmailThread(
      id: "mail-1:1", subject: "x",
      messages: [envelope("1"), envelope("2"), envelope("3", mailbox: .sent)], participants: [], unreadCount: 0,
      lastDate: "")
    store.requestDelete(thread)
    #expect(store.confirmation?.title == "Excluir esta conversa (2 mensagens recebidas)?")

    server.route { call in
      call.path == "/api/email/batch" ? Self.results([.init(account: "mail-1", id: "1", ok: false)]) : nil
    }
    await store.delete(thread)
    #expect(store.batchError == "Falha ao excluir")
    #expect(
      client.calls.first { $0.path == "/api/email/batch" }?.body
        == batchBody([("mail-1", "1"), ("mail-1", "2")], "delete"))
  }

  // MARK: - Open message

  @Test func openingLoadsTheBodyThenMarksRead() async {
    server.route { call in
      call.path == "/api/email/mail-1/1/body"
        ? FakeAPIClient.json(EmailBody(text: "Oi https://x.com", quoted: "> antes", cached: true)) : nil
    }
    let message = Self.inbox[0]
    store.open(message)
    await store.loadBody(message)

    #expect(store.detail?.text == "Oi https://x.com")
    #expect(store.detail?.quoted == "> antes")
    #expect(client.actionCalls.contains(.init("GET", "/api/email/mail-1/1/body", query: "box=inbox")))
    #expect(
      client.actionCalls.contains(
        .init("POST", "/api/email/mark", body: #"{"account":"mail-1","folder":"INBOX","id":"1","seen":true}"#)))
    #expect(unread["1"] == false)
  }

  @Test func markFailureRollsBack() async {
    let failure = self.failure
    server.route { call throws(APIError) in
      if call.path == "/api/email/mark" { throw failure }
      if call.path.hasSuffix("/body") { return FakeAPIClient.json(EmailBody(text: "t", quoted: "", cached: true)) }
      return nil
    }
    let message = Self.inbox[0]
    store.open(message)
    await store.loadBody(message)
    #expect(unread["1"] == true)
    #expect(toasts.toasts.map(\.text) == ["falhou"])
  }

  @Test func bodyErrorIsShown() async {
    server.route { call throws(APIError) in
      if call.path.hasSuffix("/body") { throw .server(status: 502, message: "IMAP fora do ar", code: nil, retry: nil) }
      return nil
    }
    let message = Self.inbox[2]
    store.open(message)
    await store.loadBody(message)
    #expect(store.detail?.error == "IMAP fora do ar")
    #expect(!client.actionCalls.contains { $0.path == "/api/email/mark" })
  }

  @Test func draftShowsTheServerMessageWithoutAKey() async {
    server.route { call throws(APIError) in
      if call.path == "/api/email/reply/draft" {
        throw .server(status: 503, message: "ANTHROPIC_API_KEY não configurada", code: nil, retry: nil)
      }
      return nil
    }
    let message = Self.inbox[2]
    store.open(message)
    store.setReply("confirmo terça")
    await store.draftReply(message)
    #expect(store.detail?.error == "ANTHROPIC_API_KEY não configurada")
    #expect(store.detail?.drafting == false)
    #expect(store.detail?.reply == "confirmo terça")
    #expect(
      client.actionCalls.last?.body
        == #"{"account":"mail-2","from":"Milton Yoshida","id":"3","instruction":"confirmo terça","subject":"Viagem"}"#)

    server.route { call in
      call.path == "/api/email/reply/draft" ? FakeAPIClient.json(EmailDraftResponse(text: "Confirmo terça.")) : nil
    }
    await store.draftReply(message)
    #expect(store.detail?.reply == "Confirmo terça.")
    #expect(store.detail?.error == nil)
  }

  @Test func sendReplyClearsTheBox() async {
    let message = Self.inbox[2]
    store.open(message)
    store.setReply("   ")
    await store.sendReply(message)
    #expect(!client.actionCalls.contains { $0.path == "/api/email/reply" })

    store.setReply("Combinado")
    await store.sendReply(message)
    #expect(
      client.actionCalls.contains(
        .init("POST", "/api/email/reply", body: #"{"account":"mail-2","body":"Combinado","id":"3"}"#)))
    #expect(store.detail?.sent == true)
    #expect(store.detail?.reply == "")
  }

  // MARK: - Note and task

  @Test func createsNoteAndTask() async {
    server.route { call in
      switch call.path {
      case "/api/email/to-note": FakeAPIClient.json(EmailToNoteResponse(noteId: "n1"))
      case "/api/email/to-task": FakeAPIClient.json(EmailToTaskResponse(taskId: "t1"))
      default: nil
      }
    }
    let message = Self.inbox[0]
    await store.create(.note, from: message, noteFolderId: "f1")
    await store.create(.task, from: message, noteFolderId: nil)
    #expect(
      client.actionCalls.map(\.body) == [
        #"{"account":"mail-1","folder":"INBOX","folderId":"f1","id":"1"}"#,
        #"{"account":"mail-1","folder":"INBOX","id":"1"}"#,
      ])
    #expect(
      toasts.toasts.map(\.text) == ["Nota criada a partir de “Relatório”.", "Tarefa criada a partir de “Relatório”."])
    #expect(toasts.toasts.map(\.actionTitle) == ["Abrir a nota", "Abrir tarefas"])
    #expect(store.creating == nil)

    // Opening what was created leaves full screen, which would cover it.
    store.isFullScreen = true
    toasts.toasts[0].action?()
    #expect(navigator.route == .module(.notes))
    #expect(navigator.pendingItem(for: .module(.notes)) == "n1")
    #expect(!store.isFullScreen)
    store.isFullScreen = true
    toasts.toasts[1].action?()
    #expect(navigator.route == .module(.tasks))
    #expect(!store.isFullScreen)
    #expect(navigator.pending == nil)

    server.route { call throws(APIError) in
      if call.path == "/api/email/to-task" {
        throw .server(status: 404, message: "mensagem não encontrada", code: nil, retry: nil)
      }
      return nil
    }
    await store.create(.task, from: message, noteFolderId: nil)
    #expect(store.batchError == "mensagem não encontrada")
  }

  // MARK: - Filters

  @Test func clearingFilters() {
    store.filters = EmailFilters(query: "x", onlyUnread: true, account: "mail-1")
    store.clearFilter(.unread)
    #expect(store.filters.onlyUnread == false && store.filters.query == "x")
    store.clearAllFilters()
    #expect(store.filters == EmailFilters())
  }
}
