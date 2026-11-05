import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeaturePulls

@MainActor
@Suite struct PullsStoreTests {
  // MARK: Lists and filters

  @Test func filtersApplyToEveryTab() {
    let harness = Harness(
      makeState(
        tracked: [pull(number: 1, title: "Arrumar o build"), pull(number: 2, title: "Deploy")],
        reviews: [pull(number: 3, title: "Deploy")],
        mine: [pull(number: 4, title: "Build novo", mine: true)]))
    harness.store.filters.query = "build"
    #expect(harness.store.tracked.map(\.number) == [1])
    #expect(harness.store.reviews.isEmpty)
    #expect(harness.store.mine.map(\.number) == [4])
    #expect(harness.store.trackedEmptyText == PullsStore.noFilterMatch)
    harness.store.clearFilters()
    #expect(harness.store.trackedEmptyText == "Nada aberto nos repositórios acompanhados.")
  }

  @Test func hiddenFilterCountLeavesTheSearchOut() {
    let harness = Harness(makeState(tracked: [pull()]))
    harness.store.filters.query = "x"
    harness.store.toggle(.draft)
    harness.store.toggle(.stale)
    #expect(harness.store.hiddenFilterCount == 2)
    harness.store.toggle(.draft)
    #expect(harness.store.filters.state == [.stale])
    harness.store.clear(.query)
    #expect(harness.store.filters.query.isEmpty)
    harness.store.clearFilters()
    #expect(!harness.store.filters.isActive)
  }

  @Test func revealOpensTheListThatHasTheItemAndClearsHidingFilters() {
    let harness = Harness(makeState(tracked: [pull(number: 1)], reviews: [pull(repo: "acme/web", number: 9)]))
    harness.store.filters.query = "nada"
    harness.store.reveal("acme/web#9")
    #expect(harness.store.tab == .reviews)
    #expect(harness.store.highlighted == "acme/web#9")
    #expect(!harness.store.filters.isActive)
  }

  @Test func aPendingPullWaitsForTheStateAndIsFinishedOnceRevealed() {
    let state = makeState(reviews: [pull(repo: "acme/web", number: 9)])
    let harness = Harness(state, loaded: false)
    let navigator = AppNavigator()
    navigator.open(.module(.pulls), itemID: "acme/web#9")
    harness.store.revealPending(from: navigator)
    #expect(navigator.pendingItem(for: .module(.pulls)) == "acme/web#9")
    #expect(harness.store.highlighted == nil)
    harness.dashboard.apply(state)
    harness.store.revealPending(from: navigator)
    #expect(harness.store.tab == .reviews)
    #expect(harness.store.highlighted == "acme/web#9")
    #expect(navigator.pending == nil)
  }

  @Test func aPendingPullAbsentFromTheLoadedListsIsFinished() {
    let harness = Harness(makeState(tracked: [pull(number: 1)]))
    let navigator = AppNavigator()
    navigator.open(.module(.pulls), itemID: "acme/web#404")
    harness.store.revealPending(from: navigator)
    #expect(harness.store.highlighted == nil)
    #expect(navigator.pending == nil)
  }

  // MARK: Tracked repositories

  @Test func loadsTheTrackedRepos() async {
    let harness = Harness()
    harness.client.respond { _ in reposJSON(["acme/web"], authors: ["acme/web": ["ana"]]) }
    await harness.store.loadRepos()
    #expect(harness.store.repos == ["acme/web"])
    #expect(harness.store.authors == ["acme/web": ["ana"]])
    #expect(harness.client.calls.map(\.description) == ["GET /api/pulls/repos -"])
  }

  @Test func theScreenAndThePanelShareOneLoad() async {
    let harness = Harness()
    let gate = Gate()
    harness.client.respond { _ in
      await gate.wait()
      return reposJSON(["acme/web"])
    }
    let first = Task { await harness.store.loadRepos() }
    await settle()
    let second = Task { await harness.store.loadRepos() }
    await settle()
    gate.open()
    await first.value
    await second.value
    #expect(harness.client.calls.map(\.description) == ["GET /api/pulls/repos -"])
    #expect(harness.store.repos == ["acme/web"])
    // Once settled, opening again reads the list again.
    await harness.store.loadRepos()
    #expect(harness.client.calls.count == 2)
  }

  @Test func aFailedLoadIsShownNotSwallowed() async {
    let harness = Harness()
    harness.failWrites("configure o token")
    await harness.store.loadRepos()
    #expect(harness.store.reposError == "configure o token")
    #expect(!harness.store.reposLoaded)
  }

  @Test func addsATrimmedRepoAndReloads() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in reposJSON(["acme/web"]) }
    harness.store.newRepo = "  acme/web "
    #expect(await harness.store.addRepo())
    #expect(harness.client.writes.map(\.description) == [#"POST /api/pulls/repos {"repo":"acme/web"}"#])
    #expect(harness.client.writes.allSatisfy { $0.idempotent })
    #expect(harness.store.repos == ["acme/web"])
    #expect(harness.store.newRepo.isEmpty)
    #expect(harness.reads == 1)
  }

  @Test func aRefusedRepoKeepsTheInputAndShowsTheReason() async {
    let harness = Harness()
    harness.failWrites("repositório inválido (use owner/nome)", status: 400)
    harness.store.newRepo = "nope"
    #expect(!(await harness.store.addRepo()))
    #expect(harness.store.reposError == "repositório inválido (use owner/nome)")
    #expect(harness.store.newRepo == "nope")
    #expect(harness.reads == 0)
  }

  @Test func removingIsOptimisticAndRollsBack() async {
    let harness = Harness()
    harness.client.respond { _ in reposJSON(["acme/web", "acme/api"], authors: ["acme/web": ["ana"]]) }
    await harness.store.loadRepos()
    let gate = Gate()
    harness.client.respond { call throws(APIError) in
      await gate.wait()
      throw .server(status: 502, message: "O GitHub recusou a operação", code: nil, retry: nil)
    }
    let running = Task { await harness.store.removeRepo("acme/web") }
    await settle()
    #expect(harness.store.repos == ["acme/api"])
    gate.open()
    await running.value
    #expect(harness.store.repos == ["acme/web", "acme/api"])
    #expect(harness.store.authors == ["acme/web": ["ana"]])
    #expect(harness.store.reposError == "O GitHub recusou a operação")
    #expect(harness.client.writes.last?.description == #"DELETE /api/pulls/repos {"repo":"acme/web"}"#)
  }

  @Test func followsAnAuthorWithoutTheAt() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in reposJSON(["acme/web"], authors: ["acme/web": ["ana"]]) }
    harness.store.authorDrafts["acme/web"] = " @ana "
    #expect(await harness.store.addAuthor(to: "acme/web"))
    #expect(
      harness.client.writes.map(\.description) == [
        #"PUT /api/pulls/repos/authors {"authors":["ana"],"repo":"acme/web"}"#
      ])
    #expect(harness.client.writes.allSatisfy { $0.idempotent })
    #expect(harness.store.authorDrafts["acme/web"] == "")
  }

  @Test func refusesAnInvalidLoginWithoutCallingTheServer() async {
    let harness = Harness()
    harness.store.authorDrafts["acme/web"] = "<script>"
    #expect(!(await harness.store.addAuthor(to: "acme/web")))
    #expect(harness.store.authorErrors["acme/web"] == "login do GitHub inválido")
    #expect(harness.client.calls.isEmpty)
  }

  @Test func authorsAreCappedPerRepo() async {
    let harness = Harness()
    harness.client.respond { _ in reposJSON(["acme/web"], authors: ["acme/web": (1...10).map { "u\($0)" }]) }
    await harness.store.loadRepos()
    harness.store.authorDrafts["acme/web"] = "novo"
    #expect(!(await harness.store.addAuthor(to: "acme/web")))
    #expect(
      harness.store.authorErrors["acme/web"]
        == "limite de 10 autores por repositório — remova um antes de adicionar outro")
    #expect(harness.client.calls.count == 1)
  }

  @Test func aRefusedAuthorListRollsBack() async {
    let harness = Harness()
    harness.client.respond { _ in reposJSON(["acme/web"], authors: ["acme/web": ["ana", "bruno"]]) }
    await harness.store.loadRepos()
    harness.failWrites(
      "limite de 10 autores por repositório e 20 no total — remova um antes de adicionar outro", status: 400)
    await harness.store.removeAuthor("ana", from: "acme/web")
    #expect(harness.client.writes.last?.body == #"{"authors":["bruno"],"repo":"acme/web"}"#)
    #expect(harness.store.authors["acme/web"] == ["ana", "bruno"])
    #expect(harness.store.authorErrors["acme/web"]?.hasPrefix("limite de 10 autores") == true)
  }

  // MARK: Pull request writes

  @Test func approvesWithAnOptionalCommentThenReloads() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in Data(#"{"ok":true,"review":{"id":1,"state":"APPROVED"}}"#.utf8) }
    let item = pull(repo: "acme/web", number: 12)
    #expect(await harness.store.approve(item, comment: "  ") == .done("PR aprovado"))
    #expect(await harness.store.approve(item, comment: " boa ") == .done("PR aprovado"))
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/pulls/acme/web/12/reviews {"event":"APPROVE"}"#,
        #"POST /api/pulls/acme/web/12/reviews {"body":"boa","event":"APPROVE"}"#,
      ])
    #expect(harness.client.writes.allSatisfy { $0.idempotent })
    #expect(harness.reads == 2)
  }

  @Test func requestChangesNeedsABody() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in Data(#"{"ok":true,"review":{"id":2,"state":"CHANGES_REQUESTED"}}"#.utf8) }
    let item = pull(repo: "acme/web", number: 12)
    #expect(
      await harness.store.requestChanges(item, comment: " ")
        == .refused("Explique as mudanças solicitadas antes de enviar a revisão"))
    #expect(harness.client.calls.isEmpty)
    #expect(await harness.store.requestChanges(item, comment: " faltou teste ") == .done("mudanças pedidas"))
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/pulls/acme/web/12/reviews {"body":"faltou teste","event":"REQUEST_CHANGES"}"#
      ])
  }

  @Test func commentsOnAnIssue() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in
      Data(#"{"ok":true,"comment":{"id":5,"url":"https://github.com/acme/web/issues/4#c5"}}"#.utf8)
    }
    let item = pull(repo: "acme/web", number: 4, isPullRequest: false)
    #expect(await harness.store.comment(item, text: " oi ") == .done("comentário publicado"))
    #expect(harness.client.writes.map(\.description) == [#"POST /api/pulls/acme/web/4/comments {"body":"oi"}"#])
  }

  @Test func rerequestsChosenAndTypedReviewers() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in Data(#"{"ok":true,"requested":["ana","bruno"]}"#.utf8) }
    let item = pull(repo: "acme/web", number: 12, mine: true)
    #expect(
      await harness.store.requestReviewers(item, chosen: ["ana"], typed: "bruno, ana")
        == .done("revisão pedida de novo a ana, bruno"))
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/pulls/acme/web/12/reviewers {"reviewers":["ana","bruno"]}"#
      ])
    #expect(
      await harness.store.requestReviewers(item, chosen: [], typed: "<x>")
        == .refused("\"<x>\" não é um login do GitHub"))
    #expect(harness.client.writes.count == 1)
  }

  @Test func mergeSendsTheMethodAndTheHeadShaTheUserSaw() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in Data(#"{"ok":true,"sha":"bbb"}"#.utf8) }
    let item = pull(repo: "acme/web", number: 12)
    #expect(await harness.store.merge(item, method: .squash) == .done("merge feito em main"))
    #expect(
      harness.client.writes.map(\.description) == [
        #"POST /api/pulls/acme/web/12/merge {"headSha":"\#(testSha)","method":"squash"}"#
      ])
    #expect(harness.client.writes.allSatisfy { $0.idempotent })
  }

  @Test func aRefusedMergeShowsTheReasonAndDoesNotReload() async {
    let harness = Harness()
    let message =
      "O estado do PR mudou ou impede esta ação. Atualize o painel e confira os commits e as regras da branch antes de tentar novamente"
    harness.failWrites(message)
    #expect(await harness.store.merge(pull(), method: .merge) == .refused(message))
    #expect(harness.reads == 0)
  }

  @Test func rerunSendsTheHeadShaAndCountsWhatRan() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in
      Data(
        #"{"ok":true,"rerun":1,"failed":[{"id":7,"error":"Não foi possível confirmar a reexecução no GitHub"}]}"#.utf8)
    }
    let item = pull(repo: "acme/web", number: 12, ci: .failing)
    #expect(
      await harness.store.rerun(item)
        == .done(
          "1 workflow(s) rodando de novo; 1 recusado(s) pelo GitHub: Não foi possível confirmar a reexecução no GitHub")
    )
    #expect(
      harness.client.writes.map(\.description) == [#"POST /api/pulls/acme/web/12/rerun {"headSha":"\#(testSha)"}"#])
    #expect(harness.client.writes.allSatisfy { $0.idempotent })
  }

  @Test func anUnexpectedRerunAnswerIsAFailure() async {
    let harness = Harness()
    harness.serve(state: makeState()) { _ in Data(#"{"ok":true}"#.utf8) }
    #expect(await harness.store.rerun(pull(ci: .failing)) == .refused("Resposta inesperada do servidor."))
  }

  // MARK: Jira sync

  @Test func asksTheServerForTheTransitionOfThatCard() async {
    let harness = Harness()
    let transition = JiraTransition(
      id: "7", name: "Revisar", to: .init(name: "Code Review PR", category: .indeterminate), requires: .nothing)
    harness.serve(state: makeState()) { _ in FakeAPIClient.json(PullJiraSyncResponse(transition: transition)) }
    #expect(await harness.store.jiraTarget(key: "TT-5019", intent: .review) == .confirm(transition))
    let call = harness.client.calls[0]
    #expect(call.path == "/api/pulls/jira-sync")
    #expect(call.query == [URLQueryItem(name: "key", value: "TT-5019"), URLQueryItem(name: "intent", value: "review")])
    // Nothing is written before the confirmation.
    #expect(harness.client.calls.count == 1)
  }

  @Test func noTransitionIsShownAsTheServerSaysIt() async {
    let harness = Harness()
    harness.failWrites("nenhuma transição para revisão disponível — abrir no Jira", status: 404)
    #expect(
      await harness.store.jiraTarget(key: "TT-1", intent: .review)
        == .failed("nenhuma transição para revisão disponível — abrir no Jira"))
  }

  @Test func anUnknownRequirementIsAnUnexpectedAnswer() async {
    let harness = Harness()
    let transition = JiraTransition(
      id: "7", name: "x", to: .init(name: "Code Review", category: .indeterminate),
      requires: JiraTransitionRequirement(rawValue: "approval"))
    harness.serve(state: makeState()) { _ in FakeAPIClient.json(PullJiraSyncResponse(transition: transition)) }
    #expect(await harness.store.jiraTarget(key: "TT-1", intent: .review) == .failed("resposta inesperada do servidor"))
  }

  @Test func movingTheCardPostsTheTransitionAndReloads() async {
    let harness = Harness()
    let transition = JiraTransition(
      id: "31", name: "Iniciar", to: .init(name: "Em Andamento", category: .indeterminate), requires: .nothing)
    #expect(await harness.store.moveCard(key: "TT-1", transition: transition) == nil)
    #expect(
      harness.client.writes.map(\.description) == [#"POST /api/jira/issues/TT-1/transitions {"transitionId":"31"}"#])
    #expect(harness.reads == 1)
  }

  @Test func aRefusedMoveIsShownAndDoesNotReload() async {
    let harness = Harness()
    harness.failWrites("transição inválida", status: 400)
    let transition = JiraTransition(
      id: "31", name: "Iniciar", to: .init(name: "Em Andamento", category: .indeterminate), requires: .nothing)
    #expect(await harness.store.moveCard(key: "TT-1", transition: transition) == "transição inválida")
    #expect(harness.reads == 0)
  }
}

/// Lets every ready main-actor task run.
@MainActor
func settle() async {
  for _ in 0..<200 { await Task.yield() }
}
