import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureJira

@MainActor
@Suite struct JiraStoreTests {
  static let person = JiraPerson(accountId: "acc-1", displayName: "Bruno Teste")

  // MARK: Watch

  @Test func watchingSendsTheUppercasedKeyAndAppliesTheAnswer() async {
    let harness = Harness(makeState())
    let fresh = makeState(watched: [makeIssue("XY-5")])
    let freshData = FakeAPIClient.json(fresh)
    harness.serve(state: fresh) { _ in freshData }
    harness.store.watchKey = "  xy-5 "
    await harness.store.watch()
    #expect(harness.client.writes.map(\.description) == [#"POST /api/jira/watch {"key":"XY-5"}"#])
    #expect(harness.dashboard.state?.jiraWatched.data?.map(\.key) == ["XY-5"])
    #expect(harness.store.watchKey.isEmpty)
    #expect(harness.store.watchError == nil)
  }

  @Test func aRefusedWatchShowsTheServersMessage() async {
    let harness = Harness()
    harness.failWrites("Too many watched issues")
    harness.store.watchKey = "XY-5"
    await harness.store.watch()
    #expect(harness.store.watchError == "Too many watched issues")
    #expect(harness.store.watchKey == "XY-5")
  }

  @Test func anEmptyKeyIsNotSent() async {
    let harness = Harness()
    harness.store.watchKey = "  "
    await harness.store.watch()
    #expect(harness.client.writes.isEmpty)
  }

  @Test func unwatchingLeavesAtOnceAndAppliesTheAnswer() async {
    let harness = Harness(makeState(watched: [makeIssue("XY-5"), makeIssue("XY-6")]))
    let gate = Gate()
    let freshData = FakeAPIClient.json(makeState(watched: [makeIssue("XY-6")]))
    harness.serve(state: makeState(watched: [makeIssue("XY-6")])) { _ in
      await gate.wait()
      return freshData
    }
    let running = Task { await harness.store.unwatch("XY-5") }
    await settle()
    #expect(harness.dashboard.state?.jiraWatched.data?.map(\.key) == ["XY-6"])
    gate.open()
    #expect(await running.value == nil)
    #expect(harness.client.writes.map(\.description) == [#"DELETE /api/jira/watch {"key":"XY-5"}"#])
    #expect(harness.dashboard.state?.jiraWatched.data?.map(\.key) == ["XY-6"])
  }

  @Test func aFailedUnwatchRollsBack() async {
    let harness = Harness(makeState(watched: [makeIssue("XY-5")]))
    harness.failWrites("issue não encontrada")
    let error = await harness.store.unwatch("XY-5")
    #expect(error == .server(status: 400, message: "issue não encontrada", code: nil, retry: nil))
    #expect(harness.dashboard.state?.jiraWatched.data?.map(\.key) == ["XY-5"])
    #expect(harness.store.watchError == "Falha ao remover do acompanhamento")
    #expect(harness.toasts.toasts.map(\.text) == ["issue não encontrada"])
  }

  // MARK: People

  @Test func followingPatchesThePeopleAndShowsThePerson() async {
    let harness = Harness()
    let response = FakeAPIClient.json(JiraPeopleResponse(people: [Self.person]))
    harness.serve(state: makeState(people: [Self.person])) { _ in response }
    harness.store.peopleSearchOpen = true
    harness.store.filters.query = "x"
    await harness.store.follow("acc-1")
    #expect(harness.client.writes.map(\.description) == [#"POST /api/jira/people {"accountId":"acc-1"}"#])
    #expect(harness.store.activePerson == Self.person)
    #expect(!harness.store.peopleSearchOpen)
    #expect(harness.store.filters == JiraFilterState())
  }

  @Test func aRefusedFollowKeepsTheServersMessage() async {
    let harness = Harness()
    harness.failWrites("limite de 10 pessoas acompanhadas")
    await harness.store.follow("acc-1")
    #expect(harness.store.peopleError == "limite de 10 pessoas acompanhadas")
    #expect(harness.store.activePerson == nil)
  }

  @Test func unfollowingTheActivePersonGoesBackToTheUser() async {
    let harness = Harness(makeState(people: [Self.person]))
    let response = FakeAPIClient.json(JiraPeopleResponse(people: []))
    harness.serve(state: makeState()) { _ in response }
    harness.store.selectPerson("acc-1")
    await harness.store.unfollow("acc-1")
    #expect(harness.client.writes.map(\.description) == [#"DELETE /api/jira/people {"accountId":"acc-1"}"#])
    #expect(harness.store.activePerson == nil)
    #expect(harness.dashboard.state?.jiraFollowedPeople == [])
  }

  @Test func searchNeedsTwoCharacters() async {
    let harness = Harness(makeState(people: [Self.person]))
    let response = FakeAPIClient.json(
      JiraPeopleResponse(people: [Self.person, JiraPerson(accountId: "b", displayName: "B")]))
    harness.serve(state: makeState(people: [Self.person])) { _ in response }
    await harness.store.searchPeople("a")
    #expect(harness.client.calls.isEmpty)
    await harness.store.searchPeople(" an ")
    #expect(harness.client.writes.map(\.description) == ["GET /api/jira/people/search?q=an -"])
    // Already followed people are not offered again.
    #expect(harness.store.peopleCandidates.map(\.accountId) == ["b"])
  }

  @Test func thePersonViewReplacesTheListsAndItsErrorShows() async {
    let harness = Harness(makeState(jira: [makeIssue("ME-1")], people: [Self.person]))
    let view = JiraPersonView(
      jira: PanelResult(data: [makeIssue("HE-1")], error: nil), delivered: PanelResult(data: [], error: nil),
      approved: PanelResult(data: [], error: nil), problems: PanelResult(data: [], error: nil), ancestors: [])
    let viewData = FakeAPIClient.json(view)
    harness.serve(state: makeState(jira: [makeIssue("ME-1")], people: [Self.person])) { _ in viewData }
    harness.store.selectPerson("acc-1")
    #expect(harness.store.all.isEmpty)
    await harness.store.loadPersonView()
    #expect(harness.client.writes.map(\.description) == ["GET /api/jira/people/acc-1 -"])
    #expect(harness.store.all.map(\.key) == ["HE-1"])
    #expect(harness.store.personFirstName == "Bruno")

    harness.failWrites("Jira não conectado")
    await harness.store.loadPersonView()
    #expect(harness.store.personError == "Jira não conectado")
    // The last good answer stays on screen.
    #expect(harness.store.all.map(\.key) == ["HE-1"])
  }

  @Test func theScreenAndThePanelAskForAPersonViewOnce() async {
    let harness = Harness(makeState(jira: [makeIssue("ME-1")], people: [Self.person]))
    let view = JiraPersonView(
      jira: PanelResult(data: [makeIssue("HE-1")], error: nil), delivered: PanelResult(data: [], error: nil),
      approved: PanelResult(data: [], error: nil), problems: PanelResult(data: [], error: nil), ancestors: [])
    let viewData = FakeAPIClient.json(view)
    let gate = Gate()
    harness.serve(state: makeState(jira: [makeIssue("ME-1")], people: [Self.person])) { _ in
      await gate.wait()
      return viewData
    }
    harness.store.selectPerson("acc-1")
    let screen = Task { await harness.store.loadPersonView() }
    await settle()
    let panel = Task { await harness.store.loadPersonView() }
    await settle()
    // The view that started the request goes away; the other still gets the answer.
    screen.cancel()
    gate.open()
    await panel.value
    #expect(harness.client.writes.map(\.description) == ["GET /api/jira/people/acc-1 -"])
    #expect(harness.store.all.map(\.key) == ["HE-1"])
    #expect(!harness.store.personLoading)
  }

  @Test func theScreenAndThePanelShareOneStore() {
    let environment = AppEnvironment.preview(state: makeState())
    let screenStore = JiraStore.shared(in: environment)
    #expect(JiraStore.shared(in: environment) === screenStore)
    environment.featureStores.removeAll()
    #expect(JiraStore.shared(in: environment) !== screenStore)
  }

  // MARK: Lists

  @Test func roleFilterLetsPendingApprovalsThrough() {
    let harness = Harness(
      makeState(jira: [
        makeIssue("A-1"), makeIssue("A-2", role: .reporter), makeIssue("A-3", role: .both),
        makeIssue("A-4", role: .reporter, approval: true),
      ]))
    let known = harness.store.known
    #expect(harness.store.visible(known: known).map(\.key) == ["A-1", "A-3", "A-4"])
    harness.store.role = .reporter
    #expect(harness.store.visible(known: known).map(\.key) == ["A-2", "A-3", "A-4"])
    harness.store.role = .both
    #expect(harness.store.visible(known: known).count == 4)
    #expect(harness.store.activeFilters(known: known).map(\.label) == ["Ambas"])
  }

  @Test func periodSlicesTheClosedLists() {
    var state = makeState()
    state.jiraDelivered = PanelResult(
      data: [JiraDatedItem(item: makeIssue("A-1"), today: true), JiraDatedItem(item: makeIssue("A-2"), today: false)],
      error: nil)
    let harness = Harness(state)
    #expect(harness.store.delivered(known: harness.store.known).map(\.key) == ["A-1"])
    harness.store.period = .week
    #expect(harness.store.delivered(known: harness.store.known).map(\.key) == ["A-1", "A-2"])
  }

  @Test func revealSwitchesTabClearsFiltersAndOpensThePath() {
    var state = makeState(problems: [
      JiraProblemItem(item: makeIssue("A-1", parent: "A-0"), problems: [.storyWithoutEpic])
    ])
    state.jiraAncestors = [makeIssue("A-0", kind: "Epic", level: 1)]
    let harness = Harness(state)
    harness.store.filters.query = "nada"
    harness.store.reveal("A-1")
    #expect(harness.store.tab == .problems)
    #expect(harness.store.filters == JiraFilterState())
    #expect(harness.store.branches["A-0"] == true)
    #expect(harness.store.revealed == "A-1")
  }

  @Test func aPendingKeyWaitsForTheStateAndIsFinishedOnceRevealed() {
    let state = makeState(jira: [makeIssue("A-1")])
    let harness = Harness(state, loaded: false)
    let navigator = AppNavigator()
    navigator.open(.module(.jira), itemID: "A-1")
    harness.store.revealPending(from: navigator)
    #expect(navigator.pendingItem(for: .module(.jira)) == "A-1")
    #expect(harness.store.revealed == nil)
    harness.dashboard.apply(state)
    harness.store.revealPending(from: navigator)
    #expect(harness.store.revealed == "A-1")
    #expect(navigator.pending == nil)
  }

  @Test func aPendingKeyAbsentFromTheLoadedListsIsFinished() {
    let harness = Harness(makeState(jira: [makeIssue("A-1")]))
    let navigator = AppNavigator()
    navigator.open(.module(.jira), itemID: "Z-9")
    harness.store.revealPending(from: navigator)
    #expect(harness.store.revealed == nil)
    #expect(navigator.pending == nil)
  }

  @Test func revealLeavesAFollowedPersonsViewForTheUsersLists() async {
    let harness = Harness(makeState(jira: [makeIssue("ME-1")], people: [Self.person]))
    let view = JiraPersonView(
      jira: PanelResult(data: [makeIssue("P-1")], error: nil), delivered: PanelResult(data: [], error: nil),
      approved: PanelResult(data: [], error: nil), problems: PanelResult(data: [], error: nil), ancestors: [])
    let viewData = FakeAPIClient.json(view)
    harness.serve(state: makeState(jira: [makeIssue("ME-1")], people: [Self.person])) { _ in viewData }
    harness.store.selectPerson("acc-1")
    await harness.store.loadPersonView()
    #expect(harness.store.all.map(\.key) == ["P-1"])
    let navigator = AppNavigator()
    navigator.open(.module(.jira), itemID: "ME-1")
    harness.store.revealPending(from: navigator)
    #expect(harness.store.activePerson == nil)
    #expect(harness.store.revealed == "ME-1")
    #expect(navigator.pending == nil)
  }

  // MARK: Issue writes

  @Test func aTransitionPostsAndReloads() async {
    let harness = Harness()
    let transition = JiraTransition(
      id: "31", name: "Iniciar", to: .init(name: "Em andamento", category: .indeterminate), requires: .nothing)
    #expect(await harness.store.transition("TT-1", to: transition) == nil)
    #expect(
      harness.client.calls.map(\.description) == [
        #"POST /api/jira/issues/TT-1/transitions {"transitionId":"31"}"#, "GET /api/state -",
      ])
  }

  @Test func aRefusedWriteReturnsJirasPhraseWithoutReloading() async {
    let harness = Harness()
    harness.failWrites("Campo obrigatório: Resolução")
    let transition = JiraTransition(
      id: "31", name: "Concluir", to: .init(name: "Feito", category: .done), requires: .nothing)
    let error = await harness.store.transition("TT-1", to: transition)
    #expect(error?.userMessage == "Campo obrigatório: Resolução")
    #expect(harness.client.calls.count == 1)
  }

  @Test func transitionsLoad() async throws {
    let harness = Harness()
    let data = Data(
      #"{"transitions":[{"id":"31","name":"Iniciar","to":{"name":"Em andamento","category":"indeterminate"},"requires":"nothing"}]}"#
        .utf8)
    harness.serve(state: makeState()) { _ in data }
    let result = await harness.store.transitions("TT-1")
    #expect(try result.get().map(\.id) == ["31"])
  }

  @Test func aCommentIsTrimmedAndAnAnswerWithoutIdIsRefused() async {
    let harness = Harness()
    let empty = FakeAPIClient.json(JiraCommentResponse(ok: true, comment: .init(id: "")))
    harness.serve(state: makeState()) { _ in empty }
    #expect(await harness.store.comment("TT-1", text: "  feito \n") == "resposta inesperada do servidor")
    #expect(harness.client.writes.map(\.description) == [#"POST /api/jira/issues/TT-1/comments {"body":"feito"}"#])

    let good = FakeAPIClient.json(JiraCommentResponse(ok: true, comment: .init(id: "10")))
    harness.serve(state: makeState()) { _ in good }
    #expect(await harness.store.comment("TT-1", text: "ok") == nil)
  }

  @Test func approvalsLoadAndDecide() async throws {
    let harness = Harness()
    let list = FakeAPIClient.json(JiraApprovalsResponse(approvals: [.init(id: "7", name: "Gestor")]))
    harness.serve(state: makeState()) { call in call.method == "GET" ? list : FakeAPIClient.ok }
    let approvals = (try await harness.store.approvals("TT-1").get())
    #expect(approvals.map(\.id) == ["7"])
    #expect(await harness.store.decide("TT-1", approval: approvals[0], decision: .approve) == nil)
    #expect(
      harness.client.writes.map(\.description) == [
        "GET /api/jira/issues/TT-1/approvals -",
        #"POST /api/jira/issues/TT-1/approvals {"approvalId":"7","decision":"approve"}"#,
      ])
  }

  @Test func aConflictingDecisionKeepsTheStatus() async {
    let harness = Harness()
    harness.failWrites("já decidida", status: 409)
    let error = await harness.store.decide("TT-1", approval: .init(id: "7", name: "G"), decision: .decline)
    #expect(error == .server(status: 409, message: "já decidida", code: nil, retry: nil))
  }

  @Test func flagSendsTheReasonAndUnflagLeavesAnEmptyNoteOut() async throws {
    let harness = Harness()
    let warning = FakeAPIClient.json(JiraFlagResponse(ok: true, warning: "comentário não gravado"))
    harness.serve(state: makeState()) { _ in warning }
    let flagged = await harness.store.setFlag("TT-1", flagging: true, text: " bloqueado ")
    #expect(try flagged.get().warning == "comentário não gravado")
    _ = await harness.store.setFlag("TT-1", flagging: false, text: "  ")
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/jira/issues/TT-1/flag {"action":"flag","reason":"bloqueado"}"#,
        #"POST /api/jira/issues/TT-1/flag {"action":"unflag"}"#,
      ])
  }

  @Test func editsAndStories() async throws {
    let harness = Harness()
    let story = FakeAPIClient.json(JiraCreatedStory(ok: true, key: "TT-2", url: "https://acme/TT-2"))
    harness.serve(state: makeState()) { call in call.path.hasSuffix("/stories") ? story : FakeAPIClient.ok }
    #expect(await harness.store.edit("TT-1", .due(nil)) == nil)
    #expect(await harness.store.edit("TT-1", .assignSelf) == nil)
    let created = await harness.store.createStory("TT-1", summary: " Nova ", description: "   ")
    #expect(try created.get().key == "TT-2")
    #expect(await harness.store.setParent("TT-3", epic: "TT-1") == nil)
    #expect(await harness.store.setStartDate("TT-3", date: "2026-10-01") == nil)
    #expect(
      harness.client.writes.map(\.description) == [
        #"PUT /api/jira/issues/TT-1/fields {"change":"due","dueDate":null}"#,
        #"PUT /api/jira/issues/TT-1/fields {"change":"assign-self"}"#,
        #"POST /api/jira/issues/TT-1/stories {"summary":"Nova"}"#,
        #"PUT /api/jira/issues/TT-3/parent {"epic":"TT-1"}"#,
        #"PUT /api/jira/issues/TT-3/start-date {"date":"2026-10-01"}"#,
      ])
    // Each accepted write reads the state again.
    #expect(harness.client.calls.filter { $0.path == "/api/state" }.count == 5)
  }

  @Test func readsDoNotReload() async throws {
    let harness = Harness()
    let priorities = FakeAPIClient.json(
      JiraPriorityOptions(priorities: [.init(id: "1", name: "Alta")], current: nil))
    let epics = FakeAPIClient.json(JiraEpicsResponse(epics: [JiraParent(key: "TT-9", summary: "Épico")]))
    let suggestion = FakeAPIClient.json(JiraStartDateSuggestion(date: "2026-10-01", basis: .started))
    harness.serve(state: makeState()) { call in
      if call.path.hasSuffix("/fields") { return priorities }
      if call.path == "/api/jira/epics" { return epics }
      return suggestion
    }
    #expect(try await harness.store.priorities("TT-1").get().priorities.count == 1)
    #expect(try await harness.store.epics(project: "TT").get().map(\.key) == ["TT-9"])
    #expect(try await harness.store.startDateSuggestion("TT-1").get().basis == .started)
    #expect(harness.client.calls.allSatisfy { $0.path != "/api/state" })
    #expect(
      harness.client.calls.map(\.description) == [
        "GET /api/jira/issues/TT-1/fields?options=priority -", "GET /api/jira/epics?project=TT -",
        "GET /api/jira/issues/TT-1/start-date -",
      ])
  }

  // MARK: Bulk start dates

  @Test func suggestionsGoInBatchesOfFifty() async throws {
    let harness = Harness()
    harness.serve(state: makeState()) { call in
      let keys = (call.query ?? "").dropFirst("keys=".count).split(separator: ",").map(String.init)
      return FakeAPIClient.json(
        JiraStartDateSuggestionsResponse(
          suggestions: keys.map { .init(key: $0, status: .suggested, date: "2026-10-01", basis: .started) }))
    }
    let keys = (1...51).map { "A-\($0)" }
    let result = await harness.store.startDateSuggestions(keys)
    #expect(try result.get().count == 51)
    #expect(harness.client.calls.count == 2)
    #expect(harness.client.calls[1].query == "keys=A-51")
  }

  @Test func writingStopsAtTheFirstFailureAndKeepsWhatWasWritten() async {
    let harness = Harness()
    let written = FakeAPIClient.json(
      JiraStartDateResultsResponse(ok: true, results: (1...50).map { .init(key: "A-\($0)", outcome: .written) }))
    let counter = Counter()
    harness.serve(state: makeState()) { call throws(APIError) in
      guard call.path.hasPrefix("/api/jira") else { return FakeAPIClient.ok }
      if await counter.next() == 1 { return written }
      throw .server(status: 502, message: "Jira fora do ar", code: nil, retry: nil)
    }
    let items = (1...120).map { JiraEndpoints.StartDateItem(key: "A-\($0)", date: "2026-10-01") }
    let (results, error) = await harness.store.writeStartDates(items)
    #expect(results.count == 50)
    #expect(error?.userMessage == "Jira fora do ar")
    #expect(harness.client.writes.count == 2)
    // A date was written, so the state is read again.
    #expect(harness.client.calls.last?.path == "/api/state")
  }

  @Test func bulkRowsAndWritableItems() {
    let rows = BulkStartDates.rows(
      [
        .init(key: "A-1", status: .suggested, date: "2026-10-01", basis: .started),
        .init(key: "A-2", status: .failed, error: "sem histórico"),
        .init(key: "A-3", status: .suggested, date: "2099-01-01", basis: .created),
        .init(key: "A-4", status: .suggested, date: "2026-02-30", basis: .finished),
      ],
      summaries: ["A-1": "Um"])
    #expect(rows[0].summary == "Um")
    #expect(rows[1].kind == .unavailable(error: "sem histórico"))
    #expect(BulkStartDates.writable(rows, limit: "2026-11-04").map(\.key) == ["A-1"])
    var excluded = rows
    excluded[0].kind = .editable(date: "2026-10-01", basis: .started, included: false)
    #expect(BulkStartDates.writable(excluded, limit: "2026-11-04").isEmpty)
  }

  @Test func missingStartCountsOnlyStartProblems() {
    let problems = [
      JiraProblemItem(item: makeIssue("A-1"), problems: [.storyInProgressWithoutStart]),
      JiraProblemItem(item: makeIssue("A-2"), problems: [.storyWithoutEpic]),
    ]
    #expect(BulkStartDates.missing(problems).map(\.key) == ["A-1"])
  }

  @Test func batches() {
    #expect(JiraStore.batches(Array(0..<101)).map(\.count) == [50, 50, 1])
    #expect(JiraStore.batches([Int]()).isEmpty)
  }

  // MARK: Pull links and summary

  @Test func pullsByKeyCountsAPullOnce() {
    var state = makeState()
    let ref = PullJiraRef(key: "TT-1", url: "u", status: "s", statusCategory: .new)
    let pull = StandupTests.pull(number: 1)
    var cited = pull
    cited.jira = [ref]
    state.pulls = PanelResult(
      data: PullsDigest(items: [cited], errors: [], defaultBranches: [], truncated: []), error: nil)
    state.reviewRequests = PanelResult(
      data: ReviewRequestsDigest(items: [cited], truncated: false, total: 1, scopeNote: nil), error: nil)
    let harness = Harness(state)
    #expect(harness.store.pullsByKey["TT-1"]?.count == 1)
  }
}

/// Counts calls across the fake client's handler.
actor Counter {
  private var value = 0

  func next() -> Int {
    value += 1
    return value
  }
}
