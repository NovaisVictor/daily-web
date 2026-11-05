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

/// What "Criar nota" / "Criar tarefa" just made, for the notice above the list
/// (`criado`, `EmailPanel.tsx:1191-1212`).
nonisolated struct CreatedFromEmail: Equatable, Sendable {
  var kind: CreateKind
  var title: String
  /// The note or task id; empty when the server did not say.
  var id: String
}

/// The right-click menu's header and choices (`menuDoLote`).
nonisolated struct EmailContextMenuSummary: Equatable, Sendable {
  /// Conversations the menu acts on.
  var count: Int
  /// Where they can move: the folders of the accounts involved.
  var moveFolders: [String]
  /// Whether the clicked row's whole group is already marked.
  var wholeGroup: Bool
}

/// The state and actions of the e-mail screen, the web's `EmailPanel` with
/// `useMailboxGroups` and `useFolderMessages`.
@Observable
final class EmailStore {
  /// Above this, marking a folder read asks first: it cannot be undone message
  /// by message (`CONFIRMA_ACIMA_DE`).
  static let confirmFolderReadAbove = 20

  /// Remembered per account (spec 015 FR-015-01), as the web keeps them in the URL.
  var filters: EmailFilters {
    get { filterValues }
    set {
      let old = filterValues
      filterValues = newValue
      rememberFilters(changedFrom: old)
    }
  }
  private var filterValues = EmailFilters()
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
  /// The notice of what was just created, until dismissed or replaced.
  private(set) var created: CreatedFromEmail?
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
  /// The view hosting the dialogs whose control asked for `confirmation` or the
  /// move sheet. The screen and the Início panels, in any window, share this
  /// store, so only that view presents them; nil lets any host.
  private(set) var dialogPresenter: UUID?
  /// The panel's "Tela cheia": folder tree, list and reader over the window
  /// (`view.maximized`, `EmailPanel.tsx:1713-1737`). Kept here so moving the
  /// panel on Início does not close it. Not remembered across launches: the
  /// store is shared, so a restored full screen would open its sheet over
  /// Início at launch even when only the e-mail screen was in use.
  var isFullScreen = false
  /// Bumped each time the remembered view is read, so the views read the
  /// restored folder again after an account switch.
  private(set) var restoreGeneration = 0
  var tagMenuThread: String?

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let dashboard: DashboardStore
  @ObservationIgnored private let navigator: AppNavigator
  @ObservationIgnored private let now: Now
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private let timeZone: TimeZone
  @ObservationIgnored private var lastBatch: (action: EmailBatchAction, folder: String?)?
  @ObservationIgnored private var syncingAccounts: Set<String> = []
  @ObservationIgnored private var loadingFolders: Set<String> = []
  @ObservationIgnored private var folderGeneration = 0
  @ObservationIgnored private var bodyTask: Task<Void, Never>?
  @ObservationIgnored private var listingCache: (key: ListingKey, value: EmailListing)?
  @ObservationIgnored private let viewState: ViewStateStore?
  @ObservationIgnored private let notesEvents: NotesEvents?
  /// The folder restored at launch, read once a view asks for it.
  @ObservationIgnored private var restoredFolderPending = false
  /// The message open at the last launch, opened once its list arrives.
  @ObservationIgnored private var restoredOpenKey: String?
  /// A restored account filter or folder not yet checked against the mailboxes.
  @ObservationIgnored private var restoredNeedsValidation = false
  /// The search written to disk once typing rests.
  @ObservationIgnored private var queryWrite: Task<Void, Never>?

  /// How long the search rests before it is remembered: every keystroke would
  /// otherwise write to disk.
  static let queryWriteDelay = Duration.milliseconds(400)

  static let viewStateModule = "email"

  /// The `ViewStateStore` fields: the web's `useEmailView` keys.
  enum Field {
    static let folderAccount = "folderAccount"
    static let folder = "folder"
    static let open = "open"
    static let query = "query"
    static let onlyUnread = "onlyUnread"
    static let account = "account"
    static let sort = "sort"
    static let group = "group"
  }

  private struct ListingKey: Equatable {
    var all: [EmailEnvelope]
    var filters: EmailFilters
    var day: Date
  }

  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureEmail")

  init(
    client: any APIClient,
    dashboard: DashboardStore,
    navigator: AppNavigator,
    viewState: ViewStateStore? = nil,
    notesEvents: NotesEvents? = nil,
    now: @escaping Now = LiveTime.now,
    sleep: @escaping Sleeper = LiveTime.sleep,
    timeZone: TimeZone = .current
  ) {
    self.client = client
    self.dashboard = dashboard
    self.navigator = navigator
    self.viewState = viewState
    self.notesEvents = notesEvents
    self.now = now
    self.sleep = sleep
    self.timeZone = timeZone
    restoreViewState()
    // Built before the sign-in, the store read another account's view, or none.
    viewState?.observe(self) { [weak self] in self?.restoreViewState() }
  }

  // MARK: - Remembered view (spec 015 FR-015-01)

  /// What the last launch left: folder, open message and filters. Also runs
  /// when another account signs in, so it replaces the whole view. Sets the
  /// backing values directly, so restoring writes nothing back.
  private func restoreViewState() {
    guard let viewState else { return }
    let module = Self.viewStateModule
    queryWrite?.cancel()
    queryWrite = nil
    bodyTask?.cancel()
    bodyTask = nil
    selection = .empty
    openKey = nil
    detail = nil
    folderGeneration += 1
    folderError = nil
    folderLoading = false
    folder = nil
    restoredFolderPending = false
    var restored = EmailFilters()
    restored.query = viewState.string(module: module, field: Field.query) ?? ""
    restored.onlyUnread = viewState.bool(module: module, field: Field.onlyUnread) ?? false
    restored.account = viewState.string(module: module, field: Field.account)
    if let raw = viewState.string(module: module, field: Field.sort), let sort = EmailSort(rawValue: raw) {
      restored.sort = sort
    }
    if let raw = viewState.string(module: module, field: Field.group), let group = EmailGroupBy(rawValue: raw) {
      restored.groupBy = group
    }
    filterValues = restored
    if let account = viewState.string(module: module, field: Field.folderAccount),
      let path = viewState.string(module: module, field: Field.folder)
    {
      folder = FolderSelection(account: account, path: path)
      restoredFolderPending = true
      // The list shows "carregando" instead of an empty folder until the read.
      folderLoading = true
    }
    restoredOpenKey = viewState.string(module: module, field: Field.open)
    restoredNeedsValidation = restored.account != nil || folder != nil
    restoreGeneration += 1
  }

  /// Writes only what changed: each field is its own key, and rewriting the
  /// others would put back values another window changed meanwhile.
  private func rememberFilters(changedFrom old: EmailFilters) {
    guard let viewState else { return }
    let module = Self.viewStateModule
    let value = filterValues
    if value.query != old.query { rememberQuery() }
    if value.onlyUnread != old.onlyUnread {
      viewState.set(value.onlyUnread, module: module, field: Field.onlyUnread)
    }
    if value.account != old.account { viewState.set(value.account, module: module, field: Field.account) }
    if value.sort != old.sort { viewState.set(value.sort.rawValue, module: module, field: Field.sort) }
    if value.groupBy != old.groupBy { viewState.set(value.groupBy.rawValue, module: module, field: Field.group) }
  }

  /// The search goes to disk once typing rests for `queryWriteDelay`.
  private func rememberQuery() {
    queryWrite?.cancel()
    let sleep = self.sleep
    queryWrite = Task { [weak self] in
      do {
        try await sleep(Self.queryWriteDelay)
      } catch {
        // Cancelled: a newer keystroke, or another account's view, replaced this write.
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.queryWrite = nil
      self.viewState?.set(self.filterValues.query, module: Self.viewStateModule, field: Field.query)
    }
  }

  /// Drops a remembered account filter or folder whose mailbox is gone, and
  /// forgets it on disk too. Waits for the server's mailboxes: the cached state
  /// may predate a mailbox added since.
  func validateRestoredView() {
    guard restoredNeedsValidation, dashboard.lastUpdated != nil, let state = dashboard.state else { return }
    restoredNeedsValidation = false
    let known = Set(state.mailboxes.map(\.id))
    if let account = filterValues.account, !known.contains(account) {
      filters.account = nil
    }
    if let folder, !known.contains(folder.account) {
      Self.logger.info("Dropping a remembered folder of a mailbox that is gone")
      self.folder = nil
      rememberFolder()
      restoredFolderPending = false
      // Drops the answer of the folder that was asked for, as `loadFolder` does.
      folderGeneration += 1
      folderLoading = false
      folderError = nil
    }
  }

  /// When the server last answered the dashboard; the views follow it to
  /// check and open what the last launch left.
  var dashboardUpdated: Date? { dashboard.lastUpdated }

  private func rememberFolder() {
    viewState?.set(folder?.account, module: Self.viewStateModule, field: Field.folderAccount)
    viewState?.set(folder?.path, module: Self.viewStateModule, field: Field.folder)
  }

  private func rememberOpenKey() {
    viewState?.set(openKey, module: Self.viewStateModule, field: Field.open)
  }

  /// Reads the folder the last launch left open; later calls do nothing.
  func loadRestoredFolder() async {
    guard restoredFolderPending else { return }
    restoredFolderPending = false
    await loadFolder()
    restoreOpenMessage()
  }

  /// Opens the message the last launch left open once its list is on screen.
  /// It is forgotten only once a list fresh from the server lacks it: an inbox
  /// still loading, failing or read from the cache proves nothing.
  func restoreOpenMessage() {
    guard let key = restoredOpenKey else { return }
    let list: [EmailEnvelope]
    let isFresh: Bool
    if let folder {
      // A folder's list only ever comes from the server.
      guard let messages = folderMessages[folder] else { return }
      list = messages
      isFresh = true
    } else {
      guard let messages = inbox.data else { return }
      list = messages
      isFresh = dashboard.lastUpdated != nil && inbox.error == nil
    }
    guard let message = list.first(where: { $0.key == key }) else {
      if isFresh {
        restoredOpenKey = nil
        rememberOpenKey()
      }
      return
    }
    restoredOpenKey = nil
    if let thread = listing.threads.first(where: { thread in thread.messages.contains { $0.key == key } }),
      thread.messages.count > 1
    {
      expanded.insert(thread.id)
    }
    open(message)
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

  /// What the right-click menu of `thread` speaks of: the selection as the
  /// click leaves it (`.context`). Worked out from the event rather than read
  /// back, so the menu is right even when it is built before the click's
  /// selection reached the store.
  func contextMenuSummary(for thread: EmailThread, in group: EmailThreadGroup) -> EmailContextMenuSummary {
    let after = selection.reduced(.context(thread.id), order: listing.order)
    let selected = Set(after.selected)
    let accounts = orderedUnique(targets(ofThreads: selected).map(\.account))
    return EmailContextMenuSummary(
      count: after.selected.count,
      moveFolders: orderedUnique(accounts.flatMap { accountFolders[$0] ?? [] }),
      wholeGroup: group.threads.allSatisfy { selected.contains($0.id) }
    )
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
    rememberFolder()
    restoredFolderPending = false
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

  /// The notes folders, read each time "Criar a partir deste e-mail" opens
  /// (`onOpen` of `CreateFromEmailMenu.tsx`): a folder made in the notes panel
  /// meanwhile shows up. What was read before stays while the new list comes.
  func loadNoteFolders() async {
    do {
      noteFolders = try await client.send(EmailEndpoints.noteFolders).folders
    } catch {
      // The picker still offers "Sem pasta"; the log keeps why the rest is missing.
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

  /// Whether the dialogs hosted by `presenter` show what the store asks.
  func presentsDialogs(_ presenter: UUID) -> Bool {
    dialogPresenter == nil || dialogPresenter == presenter
  }

  /// E and the "Excluir" button: the same question as a single row's trash.
  func requestDeleteSelected(presenter: UUID? = nil) {
    let count = selectedTargets.count
    guard count > 0 else { return }
    dialogPresenter = presenter
    confirmation = ConfirmRequest(
      title: count == 1 ? "Excluir este e-mail?" : "Excluir estes \(count) e-mails?",
      message: "Os enviados ficam: sua cópia do que escreveu não é lixo da caixa.",
      confirmLabel: "Excluir",
      destructive: true,
      onConfirm: { [weak self] in Task { await self?.runBatch(.delete) } }
    )
  }

  /// M opens the destination sheet instead of moving at once.
  func requestMoveSelected(presenter: UUID? = nil) {
    guard !selection.selected.isEmpty, !moveFolders.isEmpty else { return }
    targetFolder = effectiveTargetFolder
    dialogPresenter = presenter
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
  func requestDelete(_ thread: EmailThread, presenter: UUID? = nil) {
    let received = thread.received
    guard !received.isEmpty else { return }
    dialogPresenter = presenter
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

  func requestMarkFolderRead(account: String, node: MailboxNode, presenter: UUID? = nil) {
    guard node.unread >= Self.confirmFolderReadAbove else {
      Task { await markFolderRead(account: account, node: node) }
      return
    }
    let name = node.name.isEmpty ? node.path : node.name
    dialogPresenter = presenter
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
      rememberFolder()
      restoredFolderPending = false
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
    restoredOpenKey = nil
    openKey = message.key
    rememberOpenKey()
    detail = EmailDetailState(key: message.key)
    bodyTask = Task { await loadBody(message) }
  }

  func closeMessage() {
    bodyTask?.cancel()
    bodyTask = nil
    restoredOpenKey = nil
    openKey = nil
    rememberOpenKey()
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
    created = nil
    let title = message.subject.isEmpty ? "(sem assunto)" : message.subject
    do {
      switch kind {
      case .note:
        let noteId = try await client.send(EmailEndpoints.toNote(message, noteFolderId: noteFolderId)).noteId
        created = CreatedFromEmail(kind: .note, title: title, id: noteId)
        // The notes panel reads its list once: without the notice the note
        // would only show after a manual reload (FR-015-07, NT-19).
        notesEvents?.post(NotesEvents.Change(activate: noteId.isEmpty ? nil : noteId))
      case .task:
        let taskId = try await client.send(EmailEndpoints.toTask(message)).taskId
        created = CreatedFromEmail(kind: .task, title: title, id: taskId)
        // The task joins the tasks list from the dashboard state.
        await dashboard.reload()
      }
    } catch {
      Self.logger.error("Create from e-mail failed: \(String(describing: error), privacy: .public)")
      batchError = error.userMessage
    }
  }

  /// "Abrir a nota" / "Abrir tarefas" of the notice (`abrirPainelDoCriado`).
  func openCreated() {
    guard let created else { return }
    // Full screen would cover what was created.
    isFullScreen = false
    switch created.kind {
    case .note:
      // Only the navigation: the notes panel reveals the pending note with a
      // read of its own, and `create` already told the notes once.
      navigator.open(.module(.notes), itemID: created.id.isEmpty ? nil : created.id)
    case .task:
      navigator.open(.module(.tasks))
    }
  }

  /// The notice's "dispensar".
  func dismissCreated() {
    created = nil
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
