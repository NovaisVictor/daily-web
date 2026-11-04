import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// The three lists of the panel (`ABAS`, `components/PullsPanel.tsx:98`).
/// "Acompanhados" is what you chose to follow; "Revisões" is what was asked of
/// you anywhere the token sees: they are not slices of the same collection.
enum PullsTab: String, CaseIterable, Identifiable {
  case tracked = "acompanhados"
  case reviews = "revisoes"
  case mine = "meus"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .tracked: "Acompanhados"
    case .reviews: "Revisões"
    case .mine: "Meus PRs"
    }
  }
}

/// How a pull request write ended: the dialog shows the message, or keeps the
/// form open with the server's refusal (`useWrite` in `PullActions.tsx`).
enum PullWriteOutcome: Equatable {
  case done(String)
  case refused(String)
}

/// The Jira sync popover (`View` in `PullJiraSync.tsx`).
enum JiraSyncTarget: Equatable {
  case failed(String)
  case confirm(JiraTransition)
}

/// State and actions of the pull requests screen. The lists come from the
/// shared dashboard state; the tracked repositories from their own route.
/// Writes on GitHub are not optimistic, as on the web: the dialog waits for
/// GitHub's answer, then the state is read again.
@Observable
final class PullsStore {
  static let noFilterMatch = "Nenhum resultado para os filtros."

  var tab: PullsTab = .tracked
  var filters = PullFilterState()
  /// The row a notification pointed at, highlighted until the next one.
  var highlighted: String?

  // MARK: Tracked repositories (`PullsPanel.tsx:140-205`)

  private(set) var repos: [String] = []
  private(set) var authors: [String: [String]] = [:]
  private(set) var reposLoaded = false
  var newRepo = ""
  var reposError: String?
  /// `RepoAuthors`' inline error, per repository.
  var authorErrors: [String: String] = [:]
  var authorDrafts: [String: String] = [:]

  @ObservationIgnored let client: any APIClient
  @ObservationIgnored let dashboard: DashboardStore
  @ObservationIgnored let focus: FocusScheduler?
  @ObservationIgnored let now: Now
  @ObservationIgnored private let logger = Logger(
    subsystem: "io.github.novaisvictor.dailyweb", category: "FeaturePulls")

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

  private static let off = PanelResult<PullsDigest>(data: nil, error: nil)

  var pulls: PanelResult<PullsDigest> { dashboard.state?.pulls ?? Self.off }
  var reviewRequests: PanelResult<ReviewRequestsDigest> {
    dashboard.state?.reviewRequests ?? PanelResult(data: nil, error: nil)
  }
  var myPulls: PanelResult<MyPullsDigest> { dashboard.state?.myPulls ?? PanelResult(data: nil, error: nil) }
  var isLoading: Bool { dashboard.state == nil }

  var allTracked: [PullRequestItem] { pulls.data?.items ?? [] }
  var allReviews: [PullRequestItem] { reviewRequests.data?.items ?? [] }
  var allMine: [PullRequestItem] { myPulls.data?.items ?? [] }

  var tracked: [PullRequestItem] { filtered(allTracked) }
  var reviews: [PullRequestItem] { filtered(allReviews) }
  var mine: [PullRequestItem] { filtered(allMine) }

  var trackedGroups: [RepoGroup] { PullGrouping.byRepo(tracked) }
  var mineGroups: [(group: MyPullGroup, items: [PullRequestItem])] { PullGrouping.myPulls(mine) }

  func count(_ tab: PullsTab) -> Int {
    switch tab {
    case .tracked: tracked.count
    case .reviews: reviews.count
    case .mine: mine.count
    }
  }

  private func filtered(_ items: [PullRequestItem]) -> [PullRequestItem] {
    let date = now()
    return items.filter { PullFiltering.matches($0, filters, now: date) }
  }

  /// Every item of the three lists feeds the filter options.
  var filterOptions: (repos: [PullFilterOption], authors: [PullFilterOption]) {
    PullFiltering.options(allTracked + allReviews + allMine)
  }

  /// The bar hides when there is nothing to filter and no filter on.
  var showsFilters: Bool {
    filters.isActive || !(allTracked.isEmpty && allReviews.isEmpty && allMine.isEmpty)
  }

  var activeFilters: [PullActiveFilter] { PullFiltering.activeFilters(filters) }

  /// The search is in plain sight; the count says only what the popover hides.
  var hiddenFilterCount: Int { activeFilters.filter { $0.id != .query }.count }

  func clear(_ kind: PullActiveFilter.Kind) {
    switch kind {
    case .query: filters.query = ""
    case .repo: filters.repo = PullFilterGroup(values: [], mode: filters.repo.mode)
    case .author: filters.author = PullFilterGroup(values: [], mode: filters.author.mode)
    case .state(let state): filters.state.removeAll { $0 == state }
    }
  }

  func clearFilters() { filters = .empty }

  func toggle(_ state: PullState) {
    if let index = filters.state.firstIndex(of: state) {
      filters.state.remove(at: index)
    } else {
      filters.state.append(state)
    }
  }

  /// "Acompanhados" says the filters found nothing only when there was
  /// something to filter (`PullsPanel.tsx:226-230`).
  var trackedEmptyText: String {
    filters.isActive && !allTracked.isEmpty ? Self.noFilterMatch : "Nada aberto nos repositórios acompanhados."
  }

  // MARK: - Focus

  /// Calendars the agenda reads; with none, "agendar foco" is hidden as on the web.
  var calendars: [AgendaCalendarRef] { dashboard.state?.agendaCalendars ?? [] }
  var focusEnabled: Bool { focus != nil && !calendars.isEmpty }

  static func focusSource(_ item: PullRequestItem) -> FocusSource {
    FocusSource(kind: .pull, ref: PullActionRules.ref(item), title: item.title, url: item.url)
  }

  func scheduleFocus(_ source: FocusSource, connectionId: String, start: Date, minutes: Int) async
    -> FocusScheduleResult
  {
    guard let focus else { return .invalid("Não foi possível criar o bloco de foco.") }
    return await focus.schedule(source, connectionId: connectionId, start: start, minutes: minutes)
  }

  // MARK: - Reveal

  /// A notification's `repo#number`: opens the list that has it, clearing the
  /// filters if they hide it.
  func reveal(_ itemID: String) {
    let ref: (PullRequestItem) -> Bool = { PullActionRules.ref($0) == itemID }
    let lists: [(PullsTab, [PullRequestItem])] = [(.tracked, allTracked), (.reviews, allReviews), (.mine, allMine)]
    guard let (tab, items) = lists.first(where: { $0.1.contains(where: ref) }) else {
      logger.info("Pull request to reveal is not in any list")
      return
    }
    self.tab = tab
    if let item = items.first(where: ref), !PullFiltering.matches(item, filters, now: now()) { clearFilters() }
    highlighted = itemID
  }

  // MARK: - Tracked repositories

  /// `GET /api/pulls/repos`, when the screen opens.
  func loadRepos() async {
    do {
      apply(try await client.send(PullsEndpoints.repos))
      reposLoaded = true
    } catch {
      logger.error("Loading tracked repos failed: \(String(describing: error), privacy: .public)")
      reposError = error.userMessage
    }
  }

  /// "Adicionar repositório"; true when the server took it.
  @discardableResult
  func addRepo() async -> Bool {
    reposError = nil
    let repo = newRepo.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      apply(try await client.send(PullsEndpoints.addRepo(repo)))
    } catch {
      logger.error("Adding a tracked repo failed: \(String(describing: error), privacy: .public)")
      reposError = error.userMessage
      return false
    }
    newRepo = ""
    await dashboard.reload()
    return true
  }

  /// The repo leaves the list at once and comes back if the server refuses.
  func removeRepo(_ repo: String) async {
    reposError = nil
    let before = (repos, authors)
    repos.removeAll { $0 == repo }
    authors[repo] = nil
    do {
      apply(try await client.send(PullsEndpoints.removeRepo(repo)))
    } catch {
      logger.error("Removing a tracked repo failed: \(String(describing: error), privacy: .public)")
      (repos, authors) = before
      reposError = error.userMessage
      return
    }
    await dashboard.reload()
  }

  /// `add` in `RepoAuthors.tsx`: validated here, so a bad login never reaches the server.
  @discardableResult
  func addAuthor(to repo: String) async -> Bool {
    let current = authors[repo] ?? []
    var login = (authorDrafts[repo] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if login.hasPrefix("@") { login.removeFirst() }
    guard GitHubNames.isLogin(login) else {
      authorErrors[repo] = "login do GitHub inválido"
      return false
    }
    if current.contains(where: { $0.lowercased() == login.lowercased() }) {
      authorDrafts[repo] = ""
      return true
    }
    guard current.count < GitHubNames.authorsPerRepoMax else {
      let max = GitHubNames.authorsPerRepoMax
      authorErrors[repo] = "limite de \(max) autores por repositório — remova um antes de adicionar outro"
      return false
    }
    guard await saveAuthors(repo: repo, current + [login]) else { return false }
    authorDrafts[repo] = ""
    return true
  }

  func removeAuthor(_ author: String, from repo: String) async {
    await saveAuthors(repo: repo, (authors[repo] ?? []).filter { $0 != author })
  }

  /// `PUT /api/pulls/repos/authors`, optimistic with rollback.
  @discardableResult
  func saveAuthors(repo: String, _ next: [String]) async -> Bool {
    authorErrors[repo] = nil
    let before = authors[repo]
    authors[repo] = next
    do {
      apply(try await client.send(PullsEndpoints.setAuthors(repo: repo, next)))
    } catch {
      logger.error("Saving followed authors failed: \(String(describing: error), privacy: .public)")
      authors[repo] = before
      authorErrors[repo] = error.userMessage
      return false
    }
    await dashboard.reload()
    return true
  }

  private func apply(_ response: PullReposResponse) {
    repos = response.repos
    authors = response.authors
  }

  // MARK: - Pull request writes

  func approve(_ item: PullRequestItem, comment: String) async -> PullWriteOutcome {
    let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = PullsEndpoints.ReviewBody(event: .approve, body: text.isEmpty ? nil : text)
    return await write("review") { [client] () async throws(APIError) in
      _ = try await client.send(PullsEndpoints.review(item, body))
      return "PR aprovado"
    }
  }

  /// The server refuses a request for changes without a comment; so does this.
  func requestChanges(_ item: PullRequestItem, comment: String) async -> PullWriteOutcome {
    let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .refused("Explique as mudanças solicitadas antes de enviar a revisão") }
    let body = PullsEndpoints.ReviewBody(event: .requestChanges, body: text)
    return await write("review") { [client] () async throws(APIError) in
      _ = try await client.send(PullsEndpoints.review(item, body))
      return "mudanças pedidas"
    }
  }

  func comment(_ item: PullRequestItem, text: String) async -> PullWriteOutcome {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return .refused("comentário vazio") }
    return await write("comment") { [client] () async throws(APIError) in
      _ = try await client.send(PullsEndpoints.comment(item, body: body))
      return "comentário publicado"
    }
  }

  func requestReviewers(_ item: PullRequestItem, chosen: [String], typed: String) async -> PullWriteOutcome {
    if let problem = PullActionRules.rerequestProblem(chosen: chosen, typed: typed) { return .refused(problem) }
    let reviewers = PullActionRules.reviewers(chosen: chosen, typed: typed)
    guard !reviewers.isEmpty else { return .refused("Selecione revisores válidos") }
    return await write("reviewers") { [client] () async throws(APIError) in
      _ = try await client.send(PullsEndpoints.requestReviewers(item, reviewers))
      return "revisão pedida de novo a \(reviewers.joined(separator: ", "))"
    }
  }

  /// Sends the head commit the user saw: if the PR moved since, GitHub refuses.
  func merge(_ item: PullRequestItem, method: MergeMethod) async -> PullWriteOutcome {
    guard let headSha = item.headSha else { return .refused("commit do PR inválido") }
    let base = item.baseRef ?? ""
    return await write("merge") { [client] () async throws(APIError) in
      _ = try await client.send(PullsEndpoints.merge(item, method: method, headSha: headSha))
      return "merge feito em \(base)"
    }
  }

  func rerun(_ item: PullRequestItem) async -> PullWriteOutcome {
    guard let headSha = item.headSha else { return .refused("commit do PR inválido") }
    return await write("rerun") { [client] () async throws(APIError) in
      let response = try await client.send(PullsEndpoints.rerun(item, headSha: headSha))
      return PullActionRules.rerunMessage(rerun: response.rerun, failed: response.failed.map(\.error))
    }
  }

  /// A refusal is shown as the server said it; success reads the state again.
  private func write(_ label: String, _ send: () async throws(APIError) -> String) async -> PullWriteOutcome {
    let message: String
    do {
      message = try await send()
    } catch {
      logger.error("Pull \(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      return .refused(error.userMessage)
    }
    await dashboard.reload()
    return .done(message)
  }

  // MARK: - Jira sync (`PullJiraSync.tsx`)

  /// `GET /api/pulls/jira-sync`. A transition this app cannot read (a status
  /// category or requirement added later) is refused like the web's `isTransition`.
  func jiraTarget(key: String, intent: JiraSyncIntent) async -> JiraSyncTarget {
    let transition: JiraTransition
    do {
      transition = try await client.send(PullsEndpoints.jiraSync(key: key, intent: intent)).transition
    } catch {
      logger.error("Jira sync lookup failed: \(String(describing: error), privacy: .public)")
      return .failed(error.userMessage)
    }
    guard transition.to.category.isKnown, transition.requires.isKnown else {
      return .failed("resposta inesperada do servidor")
    }
    return .confirm(transition)
  }

  /// Moves the card; nil on success, else Jira's refusal.
  func moveCard(key: String, transition: JiraTransition) async -> String? {
    do {
      _ = try await client.send(PullsEndpoints.transition(key: key, transitionId: transition.id))
    } catch {
      logger.error("Jira transition failed: \(String(describing: error), privacy: .public)")
      return error.userMessage
    }
    await dashboard.reload()
    return nil
  }
}
