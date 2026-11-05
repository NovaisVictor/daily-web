import DailyAPI
import DailyCore
import DailyDesign
import DailyModels
import Foundation
import Observation
import os

/// A folder is a pair: two accounts each have their own "INBOX".
nonisolated struct FolderSelection: Hashable, Sendable {
  var account: String
  var path: String
}

/// One account and what is known of its folders (`MailboxGroup` in
/// `components/email/FolderTree.tsx`). Each carries its own state: a box that
/// is down cannot hold the others.
nonisolated struct MailboxGroup: Identifiable, Equatable, Sendable {
  var account: MailboxRef
  var mailboxes: [MailboxNode] = []
  /// Nothing stored yet: the first time this account is opened.
  var loading = true
  /// Reading the server over what is already on screen.
  var syncing = false
  var error: String?

  var id: String { account.id }
}

/// The open message: its body and the reply being written (`EmailDetail`).
nonisolated struct EmailDetailState: Equatable, Sendable {
  var key: String
  /// nil while loading.
  var text: String?
  var quoted = ""
  var showQuoted = false
  var error: String?
  var reply = ""
  var drafting = false
  var sending = false
  var sent = false
}

nonisolated enum CreateKind: Sendable, Equatable {
  case note
  case task
}

/// The state and actions of the e-mail screen, the web's `EmailPanel` with
/// `useMailboxGroups` and `useFolderMessages`.
@Observable
final class EmailStore {
  /// Above this, marking a folder read asks first: it cannot be undone message
  /// by message (`CONFIRMA_ACIMA_DE`).
  static let confirmFolderReadAbove = 20

  var filters = EmailFilters()
  /// nil shows the dashboard inbox (`state.email`).
  private(set) var folder: FolderSelection?
  private(set) var selection = EmailSelection.empty
  private(set) var openKey: String?
  private(set) var detail: EmailDetailState?
  var expanded: Set<String> = []
  /// Tags applied here: the server only confirms them on the next refresh.
  private(set) var appliedTags: [String: [String]] = [:]
  var batchError: String?
  /// What the last batch could not do, with a retry for just those.
  private(set) var unprocessed: [EmailBatchResult] = []
  private(set) var noteFolders: [NoteFolder] = []
  /// The message whose note or task is being created.
  private(set) var creating: String?
  /// `GET /api/email/folders` per account: tag menu and move destinations.
  private(set) var accountFolders: [String: [String]] = [:]
  private(set) var accountFoldersError: [String: String] = [:]
  var targetFolder = ""
  private(set) var groupStates: [String: MailboxGroup] = [:]
  private(set) var folderMessages: [FolderSelection: [EmailEnvelope]] = [:]
  private(set) var folderLoading = false
  private(set) var folderError: String?
  /// The conversation being dragged; the selected ones travel with it.
  private(set) var dragging: String?
  var confirmation: ConfirmRequest?
  var isMoveSheetPresented = false
  /// The panel's "Tela cheia": folder tree, list and reader over the window
  /// (`view.maximized`, `EmailPanel.tsx:1713-1737`). Kept here so moving the
  /// panel on Início does not close it.
  var isFullScreen = false
  var tagMenuThread: String?

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let dashboard: DashboardStore
  @ObservationIgnored let toasts: ToastCenter
  @ObservationIgnored private let navigator: AppNavigator
  @ObservationIgnored private let now: Now
  @ObservationIgnored private let timeZone: TimeZone
  @ObservationIgnored private var lastBatch: (action: EmailBatchAction, folder: String?)?
  @ObservationIgnored private var syncingAccounts: Set<String> = []
  @ObservationIgnored private var loadingFolders: Set<String> = []
  @ObservationIgnored private var folderGeneration = 0
  @ObservationIgnored private var bodyTask: Task<Void, Never>?
  @ObservationIgnored private var listingCache: (key: ListingKey, value: EmailListing)?

  private struct ListingKey: Equatable {
    var all: [EmailEnvelope]
    var filters: EmailFilters
    var day: Date
  }

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureEmail")

  init(
    client: any APIClient,
    dashboard: DashboardStore,
    toasts: ToastCenter,
    navigator: AppNavigator,
    now: @escaping Now = LiveTime.now,
    timeZone: TimeZone = .current
  ) {
    self.client = client
    self.dashboard = dashboard
    self.toasts = toasts
    self.navigator = navigator
    self.now = now
    self.timeZone = timeZone
  }

  // MARK: - Derived

  var mailboxes: [MailboxRef] { dashboard.state?.mailboxes ?? [] }

  /// The inbox panel result; only meaningful while no folder is open.
  var inbox: PanelResult<[EmailEnvelope]> {
    dashboard.state?.email ?? PanelResult(data: nil, error: nil)
  }

  var all: [EmailEnvelope] {
    if let folder { return folderMessages[folder] ?? [] }
    return inbox.data ?? []
  }

  var listing: EmailListing {
    let current = now()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let key = ListingKey(all: all, filters: filters, day: calendar.startOfDay(for: current))
    if let cached = listingCache, cached.key == key { return cached.value }
    let value = EmailListing.build(all: key.all, filters: filters, now: current, timeZone: timeZone)
    listingCache = (key, value)
    return value
  }

  func relativeTime(_ iso: String) -> String {
    EmailDates.relativeTime(iso, now: now(), timeZone: timeZone)
  }

  var groups: [MailboxGroup] {
    mailboxes.map { account in
      guard var state = groupStates[account.id] else { return MailboxGroup(account: account) }
      // The label follows the dashboard: the person may rename the box meanwhile.
      state.account = account
      return state
    }
  }

  /// The folder path of what is on screen, as the server names it.
  var folderPath: String { folder?.path ?? EmailEndpoints.inboxPath }

  var folderTitle: String {
    guard let folder else { return "Inbox" }
    let node = groupStates[folder.account]?.mailboxes.first { $0.path == folder.path }
    return node.map { $0.name.isEmpty ? $0.path : $0.name } ?? folder.path
  }

  /// The tree highlights the dashboard inbox as the first account's INBOX.
  var highlightedFolder: FolderSelection {
    folder ?? FolderSelection(account: mailboxes.first?.id ?? "", path: EmailEndpoints.inboxPath)
  }

  var openMessage: EmailEnvelope? {
    guard let openKey else { return nil }
    return all.first { $0.key == openKey }
  }

  /// The messages the selection reaches: the received ones of each selected
  /// conversation, in list order.
  var selectedTargets: [EmailTarget] {
    targets(ofThreads: Set(selection.selected))
  }

  private func targets(ofThreads ids: Set<String>) -> [EmailTarget] {
    var seen = Set<EmailTarget>()
    var result: [EmailTarget] = []
    for thread in listing.threads where ids.contains(thread.id) {
      for message in thread.received {
        let target = EmailTarget(message)
        if seen.insert(target).inserted { result.append(target) }
      }
    }
    return result
  }

  /// Where the selection can move: the folders of the accounts involved.
  var moveFolders: [String] {
    let accounts = orderedUnique(selectedTargets.map(\.account))
    return orderedUnique(accounts.flatMap { accountFolders[$0] ?? [] })
  }

  /// The chosen destination, or the first one when the choice is gone.
  var effectiveTargetFolder: String {
    let options = moveFolders
    return options.contains(targetFolder) ? targetFolder : (options.first ?? "")
  }

  func tags(of thread: EmailThread) -> [String] {
    var all = Set(appliedTags[thread.id] ?? [])
    for message in thread.messages { all.formUnion(message.labels) }
    return all.sorted()
  }

  func subject(account: String, id: String) -> String {
    let subject = all.first { $0.account == account && $0.id == id }?.subject ?? ""
    return subject.isEmpty ? "(sem assunto)" : subject
  }

  // MARK: - Selection

  func select(_ event: EmailSelection.Event) {
    selection = selection.reduced(event, order: listing.order)
    ensureFoldersForSelection()
  }

  /// The list changed under the selection: what is gone leaves it.
  func syncSelection() {
    let next = selection.reduced(.sync, order: listing.order)
    if next != selection { selection = next }
  }

  private func ensureFoldersForSelection() {
    for account in orderedUnique(selectedTargets.map(\.account)) {
      Task { await loadAccountFolders(account) }
    }
  }

  // MARK: - Folder tree (`useMailboxGroups`)

  /// The stored tree first, which opens at once, then the server read over it.
  func loadMailboxes() async {
    await withTaskGroup(of: Void.self) { group in
      for account in mailboxes {
        group.addTask { await self.loadMailboxes(of: account.id) }
      }
    }
  }

  private func loadMailboxes(of account: String) async {
    if groupStates[account] == nil { groupStates[account] = MailboxGroup(account: ref(account)) }
    do {
      let stored = try await client.send(EmailEndpoints.mailboxes(account: account, sync: false))
      groupStates[account]?.mailboxes = stored.mailboxes
    } catch {
      // The sync right after reports what is wrong; this read only saves time.
      Self.logger.error("Stored folders failed: \(String(describing: error), privacy: .public)")
    }
    groupStates[account]?.loading = false
    await syncMailboxes(account)
  }

  /// `sync=1`, also the "tentar de novo" of an account. One per account at a time.
  func syncMailboxes(_ account: String) async {
    guard !syncingAccounts.contains(account) else { return }
    syncingAccounts.insert(account)
    defer { syncingAccounts.remove(account) }
    if groupStates[account] == nil { groupStates[account] = MailboxGroup(account: ref(account)) }
    groupStates[account]?.syncing = true
    groupStates[account]?.error = nil
    do {
      let fresh = try await client.send(EmailEndpoints.mailboxes(account: account, sync: true))
      groupStates[account]?.mailboxes = fresh.mailboxes
      groupStates[account]?.error = nil
    } catch {
      Self.logger.error("Folder sync failed: \(String(describing: error), privacy: .public)")
      // What was on screen stays; the failure offers a retry.
      groupStates[account]?.error =
        error == .timedOut ? "a conta demorou demais para responder" : error.userMessage
    }
    groupStates[account]?.loading = false
    groupStates[account]?.syncing = false
  }

  private func ref(_ account: String) -> MailboxRef {
    mailboxes.first { $0.id == account } ?? MailboxRef(id: account, label: account)
  }

  // MARK: - Folder messages (`useFolderMessages`)

  /// Changing folders clears the selection: the batch must speak of the folder on screen.
  func openFolder(_ selection: FolderSelection) async {
    let isDashboardInbox = selection.path == EmailEndpoints.inboxPath && mailboxes.count == 1
    self.selection = .empty
    closeMessage()
    folder = isDashboardInbox ? nil : selection
    await loadFolder()
  }

  /// Rereads the open folder; what is cached shows meanwhile.
  func loadFolder() async {
    folderGeneration += 1
    let mine = folderGeneration
    guard let folder else {
      folderLoading = false
      folderError = nil
      return
    }
    folderError = nil
    folderLoading = folderMessages[folder] == nil
    do {
      let page = try await client.send(EmailEndpoints.messages(account: folder.account, folder: folder.path))
      folderMessages[folder] = page.messages
      // A late answer for a folder that is no longer open never writes.
      guard mine == folderGeneration else { return }
      folderError = nil
    } catch {
      guard mine == folderGeneration else { return }
      Self.logger.error("Folder read failed: \(String(describing: error), privacy: .public)")
      folderError = error == .timedOut ? "a pasta demorou demais para responder" : error.userMessage
    }
    if mine == folderGeneration { folderLoading = false }
  }

  // MARK: - Lookups

  func loadAccountFolders(_ account: String) async {
    guard accountFolders[account] == nil, !loadingFolders.contains(account) else { return }
    loadingFolders.insert(account)
    defer { loadingFolders.remove(account) }
    do {
      let response = try await client.send(EmailEndpoints.folders(account: account))
      accountFolders[account] = response.folders
      accountFoldersError[account] = nil
    } catch {
      Self.logger.error("Folder list failed: \(String(describing: error), privacy: .public)")
      accountFoldersError[account] = error.userMessage
    }
  }

  /// The notes folders, fetched once for every menu on screen.
  func loadNoteFolders() async {
    guard noteFolders.isEmpty else { return }
    do {
      noteFolders = try await client.send(EmailEndpoints.noteFolders).folders
    } catch {
      // The menu still offers "Sem pasta"; the log keeps why the rest is missing.
      Self.logger.error("Note folders failed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Optimistic patches

  private func patchSeen(_ targets: [EmailTarget], seen: Bool) -> (inout DashboardState) -> Void {
    let set = Set(targets)
    return { state in
      guard let list = state.email.data else { return }
      state.email.data = list.map { envelope in
        guard envelope.mailbox == .inbox, set.contains(EmailTarget(envelope)) else { return envelope }
        var copy = envelope
        copy.unread = !seen
        return copy
      }
    }
  }

  private func patchRemoved(_ targets: [EmailTarget]) -> (inout DashboardState) -> Void {
    let set = Set(targets)
    return { state in
      guard let list = state.email.data else { return }
      state.email.data = list.filter { !($0.mailbox == .inbox && set.contains(EmailTarget($0))) }
    }
  }

  /// The open folder's list gets the same change; returns how to undo it.
  private func patchFolder(_ targets: [EmailTarget], seen: Bool?, removed: Bool) -> () -> Void {
    guard let folder, let before = folderMessages[folder] else { return {} }
    let set = Set(targets)
    var next = before
    if removed {
      next.removeAll { set.contains(EmailTarget($0)) }
    } else if let seen {
      for index in next.indices where set.contains(EmailTarget(next[index])) { next[index].unread = !seen }
    }
    folderMessages[folder] = next
    return { [weak self] in
      guard let self, self.folderMessages[folder] == next else { return }
      self.folderMessages[folder] = before
    }
  }

  // MARK: - Batch

  /// `POST /api/email/batch` over the selection, or over `only`.
  func runBatch(_ action: EmailBatchAction, folder destination: String? = nil, only: [EmailTarget]? = nil) async {
    lastBatch = (action, destination)
    let targets = only ?? selectedTargets
    guard !targets.isEmpty else { return }
    // Taken before the optimistic change, which may remove the rows.
    let threadsBefore = listing.threads

    let change: (inout DashboardState) -> Void
    let undoFolder: () -> Void
    switch action {
    case .read, .tag:
      // Copying to a folder marks as read on the server; the screen follows.
      change = patchSeen(targets, seen: true)
      undoFolder = patchFolder(targets, seen: true, removed: false)
    case .unread:
      change = patchSeen(targets, seen: false)
      undoFolder = patchFolder(targets, seen: false, removed: false)
    case .move, .delete:
      change = patchRemoved(targets)
      undoFolder = patchFolder(targets, seen: nil, removed: true)
    }
    if action == .move || action == .delete, let openKey,
      targets.contains(where: { "\($0.account):\($0.id)" == openKey })
    {
      closeMessage()
    }

    var results: [EmailBatchResult] = []
    let endpoint = EmailEndpoints.batch(targets, action: action, folder: destination, folderPath: folderPath)
    let failure = await dashboard.mutate(change) { () async throws(APIError) in
      results = try await client.send(endpoint).results
    }
    if failure != nil {
      undoFolder()
      return
    }

    let failed = results.filter { !$0.ok }
    if !failed.isEmpty {
      batchError = nil
      unprocessed = failed
      // What was not done comes back selected: it is what one retries.
      let failedKeys = Set(failed.map { "\($0.account):\($0.id)" })
      let threads =
        threadsBefore
        .filter { thread in thread.received.contains { failedKeys.contains($0.key) } }
        .map(\.id)
      selection = EmailSelection(selected: threads, anchor: threads.first, cursor: threads.first)
      // Something was not done: the server knows the real state.
      await reloadAfterBatch()
      return
    }
    batchError = nil
    unprocessed = []
    selection = .empty
    await reloadAfterBatch()
  }

  private func reloadAfterBatch() async {
    // The open folder does not go through the dashboard cycle: it is reread here.
    if folder != nil { await loadFolder() }
    await dashboard.reload()
  }

  func retryUnprocessed() async {
    guard let lastBatch, !unprocessed.isEmpty else { return }
    let targets = unprocessed.map { EmailTarget(account: $0.account, id: $0.id) }
    unprocessed = []
    await runBatch(lastBatch.action, folder: lastBatch.folder, only: targets)
  }

  /// E and the "Excluir" button: the same question as a single row's trash.
  func requestDeleteSelected() {
    let count = selectedTargets.count
    guard count > 0 else { return }
    confirmation = ConfirmRequest(
      title: count == 1 ? "Excluir este e-mail?" : "Excluir estes \(count) e-mails?",
      message: "Os enviados ficam: sua cópia do que escreveu não é lixo da caixa.",
      confirmLabel: "Excluir",
      destructive: true,
      onConfirm: { [weak self] in Task { await self?.runBatch(.delete) } }
    )
  }

  /// M opens the destination sheet instead of moving at once.
  func requestMoveSelected() {
    guard !selection.selected.isEmpty, !moveFolders.isEmpty else { return }
    targetFolder = effectiveTargetFolder
    isMoveSheetPresented = true
  }

  func confirmMoveSelected() async {
    isMoveSheetPresented = false
    await runBatch(.move, folder: effectiveTargetFolder)
  }

  // MARK: - One conversation

  /// Tagging goes through the batch for the whole conversation, like Gmail.
  func applyTag(_ tag: String, to thread: EmailThread) async {
    let targets = thread.received.map(EmailTarget.init)
    tagMenuThread = nil
    let undoFolder = patchFolder(targets, seen: true, removed: false)
    var results: [EmailBatchResult] = []
    let endpoint = EmailEndpoints.batch(targets, action: .tag, folder: tag, folderPath: folderPath)
    let failure = await dashboard.mutate(patchSeen(targets, seen: true)) { () async throws(APIError) in
      results = try await client.send(endpoint).results
    }
    if failure != nil {
      undoFolder()
      return
    }
    if let failed = results.first(where: { !$0.ok }) {
      batchError = failed.error ?? "Falha ao aplicar etiqueta"
      await dashboard.reload()
      return
    }
    batchError = nil
    if !(appliedTags[thread.id] ?? []).contains(tag) { appliedTags[thread.id, default: []].append(tag) }
    await dashboard.reload()
  }

  /// The trash of one row asks with what will really go.
  func requestDelete(_ thread: EmailThread) {
    let received = thread.received
    guard !received.isEmpty else { return }
    confirmation = ConfirmRequest(
      title: received.count == 1
        ? "Excluir este e-mail?" : "Excluir esta conversa (\(received.count) mensagens recebidas)?",
      message: "Os enviados ficam: sua cópia do que escreveu não é lixo da caixa.",
      confirmLabel: "Excluir",
      destructive: true,
      onConfirm: { [weak self] in Task { await self?.delete(thread) } }
    )
  }

  func delete(_ thread: EmailThread) async {
    let targets = thread.received.map(EmailTarget.init)
    batchError = nil
    if let openKey, thread.received.contains(where: { $0.key == openKey }) { closeMessage() }
    let undoFolder = patchFolder(targets, seen: nil, removed: true)
    var results: [EmailBatchResult] = []
    let endpoint = EmailEndpoints.batch(targets, action: .delete, folder: nil, folderPath: folderPath)
    let failure = await dashboard.mutate(patchRemoved(targets)) { () async throws(APIError) in
      results = try await client.send(endpoint).results
    }
    if failure != nil {
      undoFolder()
      return
    }
    if let failed = results.first(where: { !$0.ok }) {
      batchError = failed.error ?? "Falha ao excluir"
      // It was not really deleted: the reload brings it back.
      await reloadAfterBatch()
    }
  }

  // MARK: - Drag

  /// Dragging a row drags the batch; a row outside the selection becomes it.
  func beginDrag(_ threadID: String) -> EmailDragToken {
    if !selection.selected.contains(threadID) { select(.click(threadID)) }
    dragging = threadID
    return EmailDragToken(threadID: threadID)
  }

  func endDrag() {
    dragging = nil
  }

  /// A drop on one of the action targets (`ActionDropTargets`): no question, as on the web.
  func dropOnAction(_ action: EmailBatchAction) async {
    dragging = nil
    await runBatch(action)
  }

  /// A drop on a folder of the tree (`soltarNaPasta`).
  func dropOnFolder(_ destination: FolderSelection) async {
    dragging = nil
    let targets = selectedTargets
    let accounts = Set(targets.map(\.account))
    if accounts.isEmpty { return }
    // IMAP moves inside one account; across accounts it would be copy and delete.
    if accounts.count > 1 {
      batchError = "Essas mensagens são de contas diferentes: mova uma conta por vez."
      return
    }
    // Checked before the path: another account's "INBOX" is not the folder on
    // screen, even when the dashboard inbox shows that account too.
    if !accounts.contains(destination.account) {
      batchError = "Só dá para mover entre pastas da mesma conta."
      return
    }
    if destination.path == folderPath {
      batchError = "A mensagem já está nessa pasta."
      return
    }
    await runBatch(.move, folder: destination.path, only: targets)
  }

  // MARK: - Folder read

  func requestMarkFolderRead(account: String, node: MailboxNode) {
    guard node.unread >= Self.confirmFolderReadAbove else {
      Task { await markFolderRead(account: account, node: node) }
      return
    }
    let name = node.name.isEmpty ? node.path : node.name
    confirmation = ConfirmRequest(
      title: "Marcar \(node.unread) mensagens como lidas?",
      message: "Vale para a pasta \(name) inteira, inclusive o que ainda não foi carregado aqui.",
      confirmLabel: "Marcar como lidas",
      onConfirm: { [weak self] in Task { await self?.markFolderRead(account: account, node: node) } }
    )
  }

  func markFolderRead(account: String, node: MailboxNode) async {
    batchError = nil
    do {
      _ = try await client.send(EmailEndpoints.folderRead(account: account, folder: node.path))
    } catch {
      Self.logger.error("Folder read mark failed: \(String(describing: error), privacy: .public)")
      batchError = error.userMessage
      return
    }
    // The count goes to zero on screen and the background sync confirms.
    if let index = groupStates[account]?.mailboxes.firstIndex(where: { $0.path == node.path }) {
      groupStates[account]?.mailboxes[index].unread = 0
    }
    await syncMailboxes(account)
    if folder == FolderSelection(account: account, path: node.path) { await loadFolder() }
    await dashboard.reload()
  }

  // MARK: - Notification target

  private static let route = AppRoute.module(.email)

  /// The message (`account:id`) a clicked notification points at, still waiting to be shown.
  var pendingItemID: String? { navigator.pendingItem(for: Self.route) }

  /// Shows the message a notification points at: back to the dashboard inbox,
  /// without the filters that hide it, its conversation selected and the
  /// message open. The request stays until the inbox arrives; with it, the
  /// message is shown or known to be gone.
  func revealPending() {
    guard let key = pendingItemID, let inbox = inbox.data else { return }
    navigator.finishPendingItem(key, for: Self.route)
    guard let message = inbox.first(where: { $0.key == key && $0.mailbox == .inbox }) else { return }
    if folder != nil {
      selection = .empty
      folder = nil
      // Drops the answer of the folder that was open, as `loadFolder` does.
      folderGeneration += 1
      folderLoading = false
      folderError = nil
    }
    if !listing.threads.contains(where: { thread in thread.messages.contains { $0.key == key } }) {
      clearAllFilters()
    }
    guard let thread = listing.threads.first(where: { thread in thread.messages.contains { $0.key == key } })
    else { return }
    select(.click(thread.id))
    if thread.messages.count > 1 { expanded.insert(thread.id) }
    if openKey != key { open(message) }
  }

  // MARK: - Open message (`EmailDetail`)

  /// A one-message conversation opens straight away; a longer one expands.
  func activate(_ thread: EmailThread) {
    if thread.messages.count == 1, let only = thread.messages.first {
      toggleOpen(only)
    } else if expanded.contains(thread.id) {
      expanded.remove(thread.id)
    } else {
      expanded.insert(thread.id)
    }
    if let account = thread.messages.first?.account {
      Task { await loadAccountFolders(account) }
    }
  }

  func toggleOpen(_ message: EmailEnvelope) {
    if openKey == message.key {
      closeMessage()
    } else {
      open(message)
    }
  }

  func open(_ message: EmailEnvelope) {
    bodyTask?.cancel()
    openKey = message.key
    detail = EmailDetailState(key: message.key)
    bodyTask = Task { await loadBody(message) }
  }

  func closeMessage() {
    bodyTask?.cancel()
    bodyTask = nil
    openKey = nil
    detail = nil
  }

  func loadBody(_ message: EmailEnvelope) async {
    let key = message.key
    let body: EmailBody
    do {
      body = try await client.send(EmailEndpoints.body(account: message.account, id: message.id, box: message.mailbox))
    } catch {
      guard detail?.key == key, error != .cancelled else { return }
      Self.logger.error("Body read failed: \(String(describing: error), privacy: .public)")
      detail?.text = ""
      detail?.error = error.userMessage
      return
    }
    guard detail?.key == key else { return }
    detail?.text = body.text
    detail?.quoted = body.quoted
    detail?.showQuoted = false
    // Only marked read once the body loaded: a message never seen because of
    // an error stays unread.
    guard message.unread else { return }
    let targets = [EmailTarget(message)]
    let undoFolder = patchFolder(targets, seen: true, removed: false)
    let endpoint = EmailEndpoints.mark(message, seen: true)
    let failure = await dashboard.mutate(patchSeen(targets, seen: true)) { () async throws(APIError) in
      _ = try await client.send(endpoint)
    }
    if failure != nil { undoFolder() }
  }

  func toggleQuoted() {
    detail?.showQuoted.toggle()
  }

  func setReply(_ text: String) {
    detail?.reply = text
    detail?.sent = false
  }

  func draftReply(_ message: EmailEnvelope) async {
    guard let instruction = detail?.reply, detail?.key == message.key else { return }
    detail?.drafting = true
    let result: Result<EmailDraftResponse, APIError>
    do {
      result = .success(try await client.send(EmailEndpoints.replyDraft(message, instruction: instruction)))
    } catch {
      result = .failure(error)
    }
    guard detail?.key == message.key else { return }
    detail?.drafting = false
    switch result {
    case .success(let draft):
      detail?.error = nil
      detail?.sent = false
      detail?.reply = draft.text
    case .failure(let error):
      // The 503 without an AI key carries the server's own sentence.
      Self.logger.error("Draft failed: \(String(describing: error), privacy: .public)")
      detail?.error = error.userMessage
    }
  }

  func sendReply(_ message: EmailEnvelope) async {
    guard let text = detail?.reply, detail?.key == message.key,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    detail?.sending = true
    let failure: APIError?
    do {
      _ = try await client.send(EmailEndpoints.reply(message, body: text))
      failure = nil
    } catch {
      failure = error
    }
    guard detail?.key == message.key else { return }
    detail?.sending = false
    if let failure {
      Self.logger.error("Reply failed: \(String(describing: failure), privacy: .public)")
      detail?.error = failure.userMessage
      return
    }
    detail?.error = nil
    detail?.sent = true
    detail?.reply = ""
    await dashboard.reload()
  }

  // MARK: - Note and task from an e-mail

  /// The conversation becomes a note or a task from its latest received message.
  func create(_ kind: CreateKind, from thread: EmailThread, noteFolderId: String?) async {
    guard let message = thread.received.last ?? thread.messages.first else { return }
    await create(kind, from: message, noteFolderId: noteFolderId)
  }

  func create(_ kind: CreateKind, from message: EmailEnvelope, noteFolderId: String?) async {
    guard creating == nil else { return }
    creating = message.key
    defer { creating = nil }
    batchError = nil
    let title = message.subject.isEmpty ? "(sem assunto)" : message.subject
    do {
      switch kind {
      case .note:
        let noteId = try await client.send(EmailEndpoints.toNote(message, noteFolderId: noteFolderId)).noteId
        // `EmailPanel.tsx:1196-1203`: the notice opens what was created.
        let navigator = self.navigator
        toasts.show(.success, "Nota criada a partir de “\(title)”.", actionTitle: "Abrir a nota") { [weak self] in
          // Full screen would cover what was created (`abrirPainelDoCriado`).
          self?.isFullScreen = false
          navigator.open(.module(.notes), itemID: noteId.isEmpty ? nil : noteId)
        }
      case .task:
        _ = try await client.send(EmailEndpoints.toTask(message))
        let navigator = self.navigator
        toasts.show(.success, "Tarefa criada a partir de “\(title)”.", actionTitle: "Abrir tarefas") { [weak self] in
          self?.isFullScreen = false
          navigator.open(.module(.tasks))
        }
        // The task joins the tasks list from the dashboard state.
        await dashboard.reload()
      }
    } catch {
      Self.logger.error("Create from e-mail failed: \(String(describing: error), privacy: .public)")
      batchError = error.userMessage
    }
  }

  // MARK: - Filters

  func clearFilter(_ kind: EmailFilters.Active.Kind) {
    switch kind {
    case .query: filters.query = ""
    case .unread: filters.onlyUnread = false
    case .account: filters.account = nil
    }
  }

  func clearAllFilters() {
    filters.query = ""
    filters.onlyUnread = false
    filters.account = nil
  }
}

private func orderedUnique(_ values: [String]) -> [String] {
  var seen = Set<String>()
  return values.filter { seen.insert($0).inserted }
}
