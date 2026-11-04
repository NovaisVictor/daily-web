import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// The panel's lists (`ABAS`, `components/JiraPanel.tsx:118-124`).
enum JiraTab: String, CaseIterable, Identifiable {
  case open = "abertas"
  case delivered = "entregues"
  case approved = "aprovados"
  case problems = "problemas"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .open: "Em aberto"
    case .delivered: "Entregues"
    case .approved: "Aprovados"
    case .problems: "Problemas"
    }
  }
}

/// The time slice of the two closed lists (`Periodo`). Both lists already
/// cover the week, so switching never asks the server.
enum JiraPeriod: String, CaseIterable, Identifiable {
  case today = "hoje"
  case week = "semana"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .today: "Hoje"
    case .week: "7 dias"
    }
  }
}

/// `Filter`, `components/JiraPanel.tsx:98-111`.
enum JiraRoleFilter: String, CaseIterable, Identifiable {
  case assignee
  case both
  case reporter

  var id: String { rawValue }

  func label(person: Bool) -> String {
    switch self {
    case .assignee: person ? "Responsável" : "Minhas"
    case .both: "Ambas"
    case .reporter: "Relator"
    }
  }
}

/// What a tree branch shows before the user opens or closes it by hand
/// (`Abertura`): only the path to the objective, or everything when a filter
/// already chose what to see.
enum JiraOpening {
  case path
  case all
}

/// The lists on screen: the user's own, or a followed person's.
struct JiraSource: Equatable {
  var jira: PanelResult<[JiraItem]>
  var delivered: PanelResult<[JiraDatedItem]>
  var approved: PanelResult<[JiraDatedItem]>
  var problems: PanelResult<[JiraProblemItem]>
  var ancestors: [JiraItem]

  /// `VISTA_VAZIA`: a person's view before it loads.
  static let empty = JiraSource(
    jira: PanelResult(data: [], error: nil), delivered: PanelResult(data: [], error: nil),
    approved: PanelResult(data: [], error: nil), problems: PanelResult(data: [], error: nil), ancestors: [])
}

/// State and actions of the Jira screen (`components/JiraPanel.tsx` and
/// `components/jira/**`). The lists live in the shared dashboard state; a
/// followed person's lists come from `GET /api/jira/people/{accountId}`. Every
/// write accepted by Jira is followed by a dashboard read, the web's `onChanged`.
@Observable
final class JiraStore {
  // MARK: View state (the web keeps it in the URL)

  var tab: JiraTab = .open
  var period: JiraPeriod = .today
  var filters = JiraFilterState()
  var role: JiraRoleFilter = .assignee
  var order: JiraOrder = .default
  /// "Lista simples" instead of the hierarchy.
  var grouped = false
  /// Branches opened or closed by hand, by issue key.
  var branches: [String: Bool] = [:]
  /// The issue a notification pointed at, highlighted once revealed.
  var revealed: String?

  // MARK: Person

  private(set) var personID: String?
  private(set) var personViews: [String: JiraPersonView] = [:]
  private(set) var personLoading = false
  private(set) var personError: String?
  @ObservationIgnored private var personRequest = 0

  var peopleSearchOpen = false
  var peopleQuery = ""
  private(set) var peopleResults: [JiraPerson] = []
  private(set) var peopleSearching = false
  var peopleError: String?

  // MARK: Watch

  var watchKey = ""
  private(set) var watchSaving = false
  var watchError: String?

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let dashboard: DashboardStore
  @ObservationIgnored let focus: FocusScheduler?
  @ObservationIgnored let now: Now
  @ObservationIgnored private let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureJira")

  init(
    client: any APIClient, dashboard: DashboardStore, focus: FocusScheduler? = nil, now: @escaping Now = LiveTime.now
  ) {
    self.client = client
    self.dashboard = dashboard
    self.focus = focus
    self.now = now
  }

  convenience init(environment: AppEnvironment) {
    self.init(client: environment.client, dashboard: environment.dashboard, focus: environment.focus)
  }

  // MARK: - Reading

  var state: DashboardState? { dashboard.state }
  var people: [JiraPerson] { state?.jiraFollowedPeople ?? [] }

  /// The person on screen. One no longer followed falls back to the user, as
  /// the web validates the URL's person against the list.
  var activePerson: JiraPerson? {
    guard let personID else { return nil }
    return people.first { $0.accountId == personID }
  }

  /// First name, for the empty texts (`nome`).
  var personFirstName: String {
    activePerson?.displayName.split(separator: " ").first.map(String.init) ?? ""
  }

  var source: JiraSource {
    if let person = activePerson {
      guard let view = personViews[person.accountId] else { return .empty }
      return JiraSource(
        jira: view.jira, delivered: view.delivered, approved: view.approved, problems: view.problems,
        ancestors: view.ancestors)
    }
    guard let state else { return .empty }
    return JiraSource(
      jira: state.jira, delivered: state.jiraDelivered, approved: state.jiraApproved, problems: state.jiraProblems,
      ancestors: state.jiraAncestors)
  }

  /// Booting with no state yet, or a person's view on its way.
  var loading: Bool { activePerson == nil ? state == nil : personLoading }

  var all: [JiraItem] { source.jira.data ?? [] }

  /// Everything known about each issue, to climb from it to the initiative.
  var known: [String: JiraItem] {
    let source = self.source
    var byKey: [String: JiraItem] = [:]
    let items =
      source.ancestors + (source.delivered.data ?? []).map(\.item) + (source.approved.data ?? []).map(\.item)
      + (source.problems.data ?? []).map(\.item) + (source.jira.data ?? [])
    for item in items { byKey[item.key] = item }
    return byKey
  }

  private func slice<T>(_ items: [T], item: (T) -> JiraItem, known: [String: JiraItem]) -> [T] {
    items.filter { JiraFilters.matches(item($0), filters, byKey: known) }
  }

  /// "Em aberto" after filters and role. What waits for the user's approval
  /// crosses the role filter: hiding it would hide what asks for a decision.
  func visible(known: [String: JiraItem]) -> [JiraItem] {
    slice(all, item: { $0 }, known: known).filter {
      role == .both || $0.role == JiraRole(rawValue: role.rawValue) || $0.role == .both || $0.awaitingApproval
    }
  }

  private func inPeriod(_ items: [JiraDatedItem]) -> [JiraDatedItem] {
    period == .today ? items.filter(\.today) : items
  }

  var deliveredInPeriod: [JiraDatedItem] { inPeriod(source.delivered.data ?? []) }
  var approvedInPeriod: [JiraDatedItem] { inPeriod(source.approved.data ?? []) }

  func delivered(known: [String: JiraItem]) -> [JiraDatedItem] {
    slice(deliveredInPeriod, item: \.item, known: known)
  }

  func approved(known: [String: JiraItem]) -> [JiraDatedItem] {
    slice(approvedInPeriod, item: \.item, known: known)
  }

  func problems(known: [String: JiraItem]) -> [JiraProblemItem] {
    order.sort(slice(source.problems.data ?? [], item: \.item, known: known), item: \.item)
  }

  /// The tree of a tab. The path comes from everything known, not only the
  /// fetched ancestors; what links to nothing in the tab is pruned.
  func tree(_ items: [JiraItem], known: [String: JiraItem]) -> [JiraProjectGroup] {
    order.sortTree(JiraTree.build(items, ancestors: Array(known.values)))
  }

  func situations(_ items: [JiraItem]) -> [JiraStatusGroup] {
    JiraTree.byStatusCategory(order.sort(items))
  }

  /// The options speak of the open tab, before the slice.
  func filterOptions(known: [String: JiraItem]) -> JiraFilters.Options {
    let base: [JiraItem] =
      switch tab {
      case .delivered: deliveredInPeriod.map(\.item)
      case .approved: approvedInPeriod.map(\.item)
      case .problems: (source.problems.data ?? []).map(\.item)
      case .open: all
      }
    return JiraFilters.options(base, byKey: known, filters: filters)
  }

  /// `rotuloDe`: an issue key with its summary when known.
  func label(for key: String, known: [String: JiraItem]) -> String {
    known[key].map { "\(key) \($0.summary)" } ?? key
  }

  func activeFilters(known: [String: JiraItem]) -> [JiraActiveFilter] {
    var result = JiraFilters.active(filters) { label(for: $0, known: known) }
    if tab == .open, role != .assignee {
      result.append(JiraActiveFilter(id: .role, label: role.label(person: activePerson != nil)))
    }
    return result
  }

  var opening: JiraOpening { filters.isActive ? .all : .path }

  func isOpen(_ node: JiraNode) -> Bool {
    branches[node.issue.key] ?? (opening == .all || node.origin == .ancestor)
  }

  func toggle(_ node: JiraNode) {
    branches[node.issue.key] = !isOpen(node)
  }

  /// Issues followed by choice. One being removed already left this list
  /// through the optimistic `unwatch`.
  var watched: PanelResult<[JiraItem]> {
    state?.jiraWatched ?? PanelResult(data: [], error: nil)
  }

  /// The pull requests citing each issue (`pullsByJiraKey`, `lib/pullJira.ts:44-55`);
  /// a PR in both lists counts once.
  var pullsByKey: [String: [PullRequestItem]] {
    let items = (state?.pulls.data?.items ?? []) + (state?.reviewRequests.data?.items ?? [])
    var byKey: [String: [PullRequestItem]] = [:]
    for item in items {
      for ref in item.jira ?? [] where !(byKey[ref.key] ?? []).contains(where: { $0.url == item.url }) {
        byKey[ref.key, default: []].append(item)
      }
    }
    return byKey
  }

  var standupSource: StandupSource {
    StandupSource(
      open: state?.jira.data ?? [], delivered: state?.jiraDelivered.data ?? [],
      approved: state?.jiraApproved.data ?? [], myPulls: state?.myPulls.data?.items ?? [])
  }

  var calendars: [AgendaCalendarRef] { state?.agendaCalendars ?? [] }
  var focusEnabled: Bool { focus != nil && !calendars.isEmpty }

  // MARK: - Filters

  func clear(_ filter: JiraActiveFilter.Kind) {
    switch filter {
    case .query: filters.query = ""
    case .field(let field): filters.clear(field)
    case .role: role = .assignee
    }
  }

  func clearFilters() {
    filters = JiraFilterState()
    role = .assignee
  }

  // MARK: - Reveal

  /// Shows the issue a notification pointed at: its tab, with the filters
  /// that would hide it cleared and its branch path opened.
  func reveal(_ key: String) {
    let source = self.source
    let tabs: [(JiraTab, [JiraItem])] = [
      (.open, source.jira.data ?? []),
      (.problems, (source.problems.data ?? []).map(\.item)),
      (.delivered, (source.delivered.data ?? []).map(\.item)),
      (.approved, (source.approved.data ?? []).map(\.item)),
    ]
    guard let found = tabs.first(where: { $0.1.contains { $0.key == key } })?.0 else { return }
    tab = found
    let inPeriod = (found == .delivered ? deliveredInPeriod : found == .approved ? approvedInPeriod : [])
    if found == .delivered || found == .approved, !inPeriod.contains(where: { $0.key == key }) {
      period = .week
    }
    clearFilters()
    let known = self.known
    if let item = known[key] {
      for ancestor in JiraFilters.lineage(of: item, in: known) { branches[ancestor.key] = true }
    }
    revealed = key
  }

  // MARK: - Person

  /// `setPessoa`: the filters belong to whoever is on screen, so switching starts clean.
  func selectPerson(_ accountId: String?) {
    filters = JiraFilterState()
    role = .assignee
    branches = [:]
    personID = accountId
    personError = nil
  }

  /// `useJiraPersonView`: fetched on choosing the person and again on every
  /// new dashboard state, keeping the last answer meanwhile.
  func loadPersonView() async {
    guard let accountId = activePerson?.accountId else {
      personLoading = false
      personError = nil
      return
    }
    personRequest += 1
    let mine = personRequest
    personLoading = true
    personError = nil
    do {
      let view = try await client.send(JiraEndpoints.personView(accountId))
      guard mine == personRequest else { return }
      personViews[accountId] = view
    } catch {
      guard mine == personRequest else { return }
      if case .cancelled = error { return }
      logger.error("Person view failed: \(String(describing: error), privacy: .public)")
      personError = error.userMessage
    }
    personLoading = false
  }

  /// The person search, after the web's 300 ms pause; fewer than two
  /// characters clears it.
  func searchPeople(_ raw: String) async {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else {
      peopleResults = []
      peopleError = nil
      peopleSearching = false
      return
    }
    peopleSearching = true
    peopleError = nil
    defer { peopleSearching = false }
    do {
      peopleResults = try await client.send(JiraEndpoints.searchPeople(query)).people
    } catch {
      if case .cancelled = error { return }
      logger.error("People search failed: \(String(describing: error), privacy: .public)")
      peopleError = error.userMessage
    }
  }

  /// Search results not followed yet.
  var peopleCandidates: [JiraPerson] {
    peopleResults.filter { result in !people.contains { $0.accountId == result.accountId } }
  }

  func closePeopleSearch() {
    peopleSearchOpen = false
    peopleQuery = ""
    peopleResults = []
  }

  func follow(_ accountId: String) async {
    closePeopleSearch()
    peopleError = nil
    do {
      let response = try await client.send(JiraEndpoints.follow(accountId))
      dashboard.patch { $0.jiraFollowedPeople = response.people }
      await dashboard.reload()
      selectPerson(accountId)
    } catch {
      logger.error("Follow failed: \(String(describing: error), privacy: .public)")
      peopleError = Self.message(error, fallback: "Falha ao acompanhar pessoa")
    }
  }

  func unfollow(_ accountId: String) async {
    do {
      let response = try await client.send(JiraEndpoints.unfollow(accountId))
      if personID == accountId { selectPerson(nil) }
      dashboard.patch { $0.jiraFollowedPeople = response.people }
      await dashboard.reload()
    } catch {
      logger.error("Unfollow failed: \(String(describing: error), privacy: .public)")
      peopleError = Self.message(error, fallback: "Falha ao remover pessoa")
    }
  }

  // MARK: - Watch

  /// `acompanhar`: the server answers the whole dashboard, applied as is.
  func watch() async {
    let key = watchKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !key.isEmpty, !watchSaving else { return }
    watchSaving = true
    defer { watchSaving = false }
    do {
      let fresh = try await client.send(JiraEndpoints.watch(key))
      watchError = nil
      watchKey = ""
      dashboard.apply(fresh)
    } catch {
      logger.error("Watch failed: \(String(describing: error), privacy: .public)")
      watchError = Self.message(error, fallback: "Falha ao acompanhar")
    }
  }

  /// `parar`: leaves the list at once, a decision that is all local; back on failure.
  @discardableResult
  func unwatch(_ key: String) async -> APIError? {
    let client = self.client
    var fresh: DashboardState?
    let error = await dashboard.mutate { state in
      state.jiraWatched.data?.removeAll { $0.key == key }
    } commit: { () async throws(APIError) in
      fresh = try await client.send(JiraEndpoints.unwatch(key))
    }
    if error != nil {
      watchError = "Falha ao remover do acompanhamento"
      return error
    }
    watchError = nil
    if let fresh { dashboard.apply(fresh) }
    return nil
  }

  // MARK: - Issue actions (`components/jira/actions/**`)

  /// `onChanged`: read the state again after a write Jira accepted.
  func changed() async {
    await dashboard.reload()
  }

  private func call<Response>(_ endpoint: Endpoint<Response>, _ label: String) async -> Result<Response, APIError> {
    do {
      return .success(try await client.send(endpoint))
    } catch {
      logger.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      return .failure(error)
    }
  }

  /// A write that, once accepted, reloads the dashboard.
  private func write<Response>(_ endpoint: Endpoint<Response>, _ label: String) async -> Result<Response, APIError> {
    let result = await call(endpoint, label)
    if case .success = result { await changed() }
    return result
  }

  func transitions(_ key: String) async -> Result<[JiraTransition], APIError> {
    await call(JiraEndpoints.transitions(key), "Transitions").map(\.transitions)
  }

  func transition(_ key: String, to transition: JiraTransition) async -> APIError? {
    await write(JiraEndpoints.transition(key, id: transition.id), "Transition").failure
  }

  /// `CommentForm.submit`: an answer without the comment id is refused as the web does.
  func comment(_ key: String, text: String) async -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch await write(JiraEndpoints.comment(key, body: trimmed), "Comment") {
    case .success(let response):
      return response.comment.id.isEmpty ? "resposta inesperada do servidor" : nil
    case .failure(let error):
      return error.userMessage
    }
  }

  func approvals(_ key: String) async -> Result<[JiraPendingApproval], APIError> {
    await call(JiraEndpoints.approvals(key), "Approvals").map(\.approvals)
  }

  func decide(_ key: String, approval: JiraPendingApproval, decision: JiraEndpoints.Decision) async -> APIError? {
    await write(JiraEndpoints.decide(key, approvalId: approval.id, decision: decision), "Approval").failure
  }

  /// Flag or unflag; `warning` when the flag changed but its comment did not.
  func setFlag(_ key: String, flagging: Bool, text: String) async -> Result<JiraFlagResponse, APIError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let body: JiraEndpoints.FlagBody =
      flagging ? .flag(reason: trimmed) : .unflag(note: trimmed.isEmpty ? nil : trimmed)
    return await write(JiraEndpoints.flag(key, body), "Flag")
  }

  func priorities(_ key: String) async -> Result<JiraPriorityOptions, APIError> {
    await call(JiraEndpoints.priorities(key), "Priorities")
  }

  func edit(_ key: String, _ change: JiraEndpoints.FieldChange) async -> APIError? {
    await write(JiraEndpoints.edit(key, change), "Edit").failure
  }

  func createStory(_ key: String, summary: String, description: String) async -> Result<JiraCreatedStory, APIError> {
    let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = JiraEndpoints.StoryBody(
      summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
      description: trimmedDescription.isEmpty ? nil : description)
    return await write(JiraEndpoints.createStory(key, body), "Create story")
  }

  func epics(project: String) async -> Result<[JiraParent], APIError> {
    await call(JiraEndpoints.epics(project: project), "Epics").map(\.epics)
  }

  func setParent(_ key: String, epic: String) async -> APIError? {
    await write(JiraEndpoints.setParent(key, epic: epic), "Parent").failure
  }

  func startDateSuggestion(_ key: String) async -> Result<JiraStartDateSuggestion, APIError> {
    await call(JiraEndpoints.startDate(key), "Start date suggestion")
  }

  func setStartDate(_ key: String, date: String) async -> APIError? {
    await write(JiraEndpoints.setStartDate(key, date: date), "Start date").failure
  }

  /// Batches of `startDateBatch` keys, stopping at the first failure.
  func startDateSuggestions(_ keys: [String]) async -> Result<[JiraStartDateKeySuggestion], APIError> {
    var all: [JiraStartDateKeySuggestion] = []
    for batch in Self.batches(keys) {
      switch await call(JiraEndpoints.startDateSuggestions(batch), "Start date suggestions") {
      case .success(let response): all += response.suggestions
      case .failure(let error): return .failure(error)
      }
    }
    return .success(all)
  }

  /// Writes in batches; the results gathered before a failure are kept with
  /// its error. Reloads when any date was written.
  func writeStartDates(_ items: [JiraEndpoints.StartDateItem]) async -> (
    results: [JiraStartDateResult], error: APIError?
  ) {
    var results: [JiraStartDateResult] = []
    var failure: APIError?
    for batch in Self.batches(items) {
      switch await call(JiraEndpoints.writeStartDates(batch), "Start dates") {
      case .success(let response): results += response.results
      case .failure(let error): failure = error
      }
      if failure != nil { break }
    }
    if results.contains(where: { $0.outcome == .written }) { await changed() }
    return (results, failure)
  }

  static func batches<T>(_ list: [T]) -> [[T]] {
    stride(from: 0, to: list.count, by: JiraEndpoints.startDateBatch).map {
      Array(list[$0..<min($0 + JiraEndpoints.startDateBatch, list.count)])
    }
  }

  // MARK: - Focus

  func scheduleFocus(_ source: FocusSource, connectionId: String, start: Date, minutes: Int) async
    -> FocusScheduleResult
  {
    guard let focus else { return .invalid("Não foi possível criar o bloco de foco.") }
    return await focus.schedule(source, connectionId: connectionId, start: start, minutes: minutes)
  }

  /// The server's own text for a refusal; `fallback` when it sent none.
  static func message(_ error: APIError, fallback: String) -> String {
    if case .server(_, let message, _, _) = error, message.isEmpty { return fallback }
    return error.userMessage
  }
}

extension Result {
  var failure: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
