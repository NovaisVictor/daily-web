import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// State and actions of the agents screen (`components/agents/AgentBoard.tsx`).
///
/// The board is not part of the dashboard state: it is read from
/// `GET /api/agents` every 2 s while the screen is visible, like
/// `useAgentPolling`, and the open task detail is read with it.
@Observable
final class AgentsStore {
  /// Kanban or workspace; the Kanban never shows "Sessões".
  let mode: AgentsMode
  /// The filters, which the web keeps in the URL.
  private(set) var query = AgentsEndpoints.BoardQuery()
  /// "Finalizadas" opened (`finished=show`).
  var showFinished = false

  private(set) var board: AgentsBoard?
  private(set) var error: String?
  private(set) var isLoading = false

  /// The task shown instead of the board; nil shows the board.
  private(set) var detail: AgentTaskDetailStore?

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let poller: Poller
  @ObservationIgnored let now: Now
  @ObservationIgnored private let reportWaiting: @MainActor ([DailyCore.AgentAttention]) async -> Void
  /// The desktop alerts switch behind "Ativar avisos"; nil hides the control.
  @ObservationIgnored private let alerts: AlertEngine?
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var isVisible = false
  /// Bumped on every filter change, so an older answer does not land on a newer query.
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var searchTask: Task<Void, Never>?

  /// The live panel's own scope, polled only while a task with a session is open.
  static let liveScope = "agentsLive"
  /// `SEARCH_DEBOUNCE_MS` (`BoardViews.tsx:89`).
  static let searchDebounce = Duration.milliseconds(250)

  init(
    client: any APIClient,
    poller: Poller,
    mode: AgentsMode = .workspace,
    alerts: AlertEngine? = nil,
    now: @escaping Now = LiveTime.now,
    sleep: @escaping Sleeper = LiveTime.sleep,
    reportWaiting: @escaping @MainActor ([DailyCore.AgentAttention]) async -> Void = { _ in }
  ) {
    self.mode = mode
    self.alerts = alerts
    self.client = client
    self.poller = poller
    self.now = now
    self.sleep = sleep
    self.reportWaiting = reportWaiting
  }

  convenience init(environment: AppEnvironment, mode: AgentsMode = .workspace) {
    let alerts = environment.alerts
    self.init(
      client: environment.client,
      poller: environment.poller,
      mode: mode,
      alerts: alerts,
      reportWaiting: { waiting in await alerts.updateAgentsFromScreen(waiting) })
  }

  // MARK: - Derived

  /// Root cards within the window (`AgentBoard.tsx:34`).
  var tasks: [AgentTask] {
    AgentsLogic.boardTasks(board?.tasks.items ?? [], days: query.days, now: now())
  }

  var sessions: [AgentSession] { board?.sessions.items ?? [] }

  var waitingOnYou: [AgentTask] { tasks.filter { AgentsLogic.needsYou($0) != nil } }

  var nextCursor: String? {
    query.tab == .sessions ? board?.sessions.nextCursor : board?.tasks.nextCursor
  }

  var activeFilterCount: Int { AgentsLogic.activeFilterCount(query) }

  var progress: [String: AgentSubtaskProgress] { board?.subtaskProgress ?? [:] }

  // MARK: - Visibility and polling

  /// Polls only while the screen is on screen (`useAgentPolling.ts`); coming
  /// back registers the scope again, which loads at once.
  func setVisible(_ visible: Bool) {
    guard visible != isVisible else { return }
    isVisible = visible
    if visible {
      poller.register(Poller.ScopeID.agents, foreground: Poller.Cadence.agents, background: nil) { [weak self] in
        await self?.poll()
      }
    } else {
      poller.unregister(Poller.ScopeID.agents)
    }
    detail?.isVisible = visible
  }

  func poll() async {
    await loadBoard()
    await detail?.load()
  }

  func loadBoard() async {
    generation += 1
    let current = generation
    let request = query
    isLoading = true
    defer { if current == generation { isLoading = false } }
    do {
      let next = try await client.send(AgentsEndpoints.board(request))
      guard current == generation else { return }
      board = next
      error = nil
      await reportAttention(for: request)
    } catch {
      guard current == generation else { return }
      Logger.agents.error("Board load failed: \(String(describing: error), privacy: .public)")
      if AgentsLogic.dropsData(error) { board = nil }
      self.error = AgentsLogic.pollMessage(error)
    }
  }

  /// The alert engine forgets keys it is not given again, so only the full,
  /// unfiltered board reports; a filtered one would re-alert on its way back.
  /// The activity window counts as a filter: a narrower one hides waiting
  /// tasks, a wider one shows tasks the default board would not alert on.
  private func reportAttention(for request: AgentsEndpoints.BoardQuery) async {
    guard request.tab == .tasks, request.status == nil, request.sessionID == nil, request.cursor == nil,
      request.days == AgentsLogic.defaultActivityWindow,
      request.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    guard let board else { return }
    await reportWaiting(AgentAttentionRules.waiting(board, now: now()))
  }

  // MARK: - Filters

  /// The Kanban has no "Sessões" (`AgentBoard.tsx:22`, `query.delete('tab')`).
  func setTab(_ tab: AgentsTab) {
    guard mode.showsTabs else { return }
    change { $0.tab = tab }
  }
  func setStatus(_ status: AgentTaskStatus?) { change { $0.status = status } }
  func setDays(_ days: Int) { change { $0.days = AgentsLogic.activityWindow(days) } }
  func setSort(_ sort: AgentsSort) { change { $0.sort = sort } }
  func setSessionID(_ id: String?) { change { $0.sessionID = id } }
  func setCursor(_ cursor: String?) { change(keepCursor: true) { $0.cursor = cursor } }

  /// "Ver tarefas da sessão" (`AgentBoard.tsx:73-77`).
  func showSession(_ id: String) {
    change {
      $0.sessionID = id
      $0.tab = .tasks
    }
  }

  /// What the search field shows; the query follows after a pause (`SearchField`, `BoardViews.tsx:84-118`).
  private(set) var searchText = ""

  func setSearchText(_ text: String) {
    searchText = String(text.prefix(200))
    searchTask?.cancel()
    let sleep = self.sleep
    searchTask = Task { [weak self] in
      do {
        try await sleep(Self.searchDebounce)
      } catch {
        // Cancelled by the next keystroke, which schedules its own search.
        return
      }
      guard let self, self.query.search != self.searchText else { return }
      self.change { $0.search = self.searchText }
    }
  }

  /// Every filter but paging goes back to the first page (`changeFilter`, `AgentBoard.tsx:27-32`).
  private func change(keepCursor: Bool = false, _ edit: (inout AgentsEndpoints.BoardQuery) -> Void) {
    var next = query
    edit(&next)
    if !keepCursor { next.cursor = nil }
    guard next != query else { return }
    query = next
    Task { await loadBoard() }
  }

  // MARK: - Desktop alerts

  /// What "Ativar avisos" shows (`PushToggle.tsx`). The native app has no push
  /// subscription per device: the switch is the app's one desktop alerts switch,
  /// the same as "Avisar no computador" in the notifications.
  enum AlertsState: Equatable {
    case unavailable
    case off
    case denied
    case on
  }

  /// Whether the system refused permission on the last attempt.
  private(set) var alertsDenied = false
  private(set) var isChangingAlerts = false
  /// "Avisos ativados neste dispositivo." and the like (`PushToggle.tsx:62-81`).
  private(set) var alertsNotice: String?

  var alertsState: AlertsState {
    guard let alerts else { return .unavailable }
    if alerts.isEnabled { return .on }
    return alertsDenied ? .denied : .off
  }

  /// Asks the system for permission and turns the alerts on when granted.
  func enableAlerts() async {
    guard let alerts, !alerts.isEnabled, !isChangingAlerts else { return }
    isChangingAlerts = true
    alertsNotice = nil
    defer { isChangingAlerts = false }
    await alerts.enable()
    alertsDenied = !alerts.isEnabled
    alertsNotice = alerts.isEnabled ? "Avisos ativados neste dispositivo." : nil
  }

  func disableAlerts() {
    guard let alerts, alerts.isEnabled else { return }
    alerts.disable()
    alertsDenied = false
    alertsNotice = "Avisos desativados neste dispositivo."
  }

  // MARK: - Detail

  func openTask(_ id: String) {
    let store = AgentTaskDetailStore(taskID: id, client: client, poller: poller, now: now) { [weak self] in
      self?.closeTask()
      Task { await self?.loadBoard() }
    }
    detail?.close()
    store.isVisible = isVisible
    detail = store
    Task { await store.load() }
  }

  /// A notification about a task waiting on the user opens that task. The
  /// detail loads by id on its own, so the item is finished at once.
  func openPendingTask(from navigator: AppNavigator) {
    guard let id = navigator.pendingItem(for: .agents) else { return }
    openTask(id)
    navigator.finishPendingItem(id, for: .agents)
  }

  func closeTask() {
    detail?.close()
    detail = nil
  }

  /// The detail's "Sessão {id}" link: the board filtered by that session.
  func openSessionTasks(_ id: String) {
    closeTask()
    showSession(id)
  }
}
