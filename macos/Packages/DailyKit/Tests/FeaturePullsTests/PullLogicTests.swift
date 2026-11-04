import DailyModels
import Foundation
import Testing

@testable import FeaturePulls

/// `tests/lib/pullFilters.test.ts` (`matchesPullFilters`, `pullFilterOptions`).
@Suite struct PullFilteringTests {
  private func filters(
    query: String = "",
    repo: PullFilterGroup = PullFilterGroup(),
    author: PullFilterGroup = PullFilterGroup(),
    state: [PullState] = []
  ) -> PullFilterState {
    PullFilterState(query: query, repo: repo, author: author, state: state)
  }

  private func include(_ values: String...) -> PullFilterGroup { PullFilterGroup(values: values, mode: .include) }

  private func matches(_ item: PullRequestItem, _ filters: PullFilterState) -> Bool {
    PullFiltering.matches(item, filters, now: testNow)
  }

  @Test func matchesEverythingWithoutFilters() {
    #expect(matches(pull(), .empty))
  }

  @Test func searchesTheTitleIgnoringAccentsAndCase() {
    #expect(matches(pull(title: "Revisão do build"), filters(query: "REVISAO")))
  }

  @Test func searchesRepoAndNumber() {
    #expect(matches(pull(), filters(query: "daily-web#3")))
  }

  @Test func searchesTheAuthor() {
    #expect(matches(pull(author: "maria"), filters(query: "mari")))
  }

  @Test func searchesTheLinkedJiraKeys() {
    let item = pull(jira: [
      PullJiraRef(key: "TT-42", url: "https://jira/TT-42", status: "Doing", statusCategory: .indeterminate)
    ])
    #expect(matches(item, filters(query: "tt-42")))
  }

  @Test func rejectsAnItemTheSearchDoesNotHit() {
    #expect(!matches(pull(), filters(query: "deploy")))
  }

  @Test func acceptsAnyOfTheSelectedRepos() {
    #expect(matches(pull(), filters(repo: include("joao/other", "joao/daily-web"))))
  }

  @Test func comparesReposIgnoringCase() {
    #expect(matches(pull(), filters(repo: include("Joao/Daily-Web"))))
  }

  @Test func rejectsARepoOutsideTheSelection() {
    #expect(!matches(pull(), filters(repo: include("joao/other"))))
  }

  @Test func rejectsASelectedRepoInExcludeMode() {
    #expect(!matches(pull(), filters(repo: PullFilterGroup(values: ["joao/daily-web"], mode: .exclude))))
  }

  @Test func rejectsAnAuthorOutsideTheSelection() {
    #expect(!matches(pull(), filters(author: include("maria"))))
  }

  @Test func acceptsAnyOfTheSelectedStates() {
    #expect(matches(pull(ci: .failing), filters(state: [.draft, .ciFailing])))
  }

  @Test func requiresEveryDimensionToMatch() {
    #expect(!matches(pull(draft: false), filters(repo: include("joao/daily-web"), state: [.draft])))
  }

  @Test(arguments: [
    (PullState.ciFailing, pull(ci: .failing)),
    (.changesRequested, pull(review: .changesRequested)),
    (.approved, pull(review: .approved)),
    (.conflict, pull(merge: .conflict)),
    (.draft, pull(draft: true)),
    (.awaitingYou, pull(awaitingYou: true)),
    (.stale, pull(updatedAt: "2026-10-18T11:59:59Z")),
  ])
  func matchesState(_ state: PullState, _ item: PullRequestItem) {
    #expect(matches(item, filters(state: [state])))
  }

  @Test(arguments: [
    (PullState.ciFailing, pull(ci: .running)),
    (.changesRequested, pull(review: .pending)),
    (.approved, pull(review: .unknown)),
    (.conflict, pull(merge: .unknown)),
    (.draft, pull(draft: false)),
    (.awaitingYou, pull(awaitingYou: false)),
    (.stale, pull(updatedAt: "2026-10-18T12:00:00Z")),
  ])
  func doesNotMatchState(_ state: PullState, _ item: PullRequestItem) {
    #expect(!matches(item, filters(state: [state])))
  }

  @Test(arguments: ["2026-10-18T12:00:00Z", "2026-10-18T11:59:59Z"])
  func agreesWithTheRowBadgeOnStale(_ updatedAt: String) {
    let item = pull(updatedAt: updatedAt)
    let badge = PullAge.age(createdAt: item.createdAt, updatedAt: item.updatedAt, now: testNow)?.stalled != nil
    #expect(matches(item, filters(state: [.stale])) == badge)
  }

  @Test func doesNotTreatAnUnparseableUpdateDateAsStale() {
    #expect(!matches(pull(updatedAt: ""), filters(state: [.stale])))
  }

  @Test func sortsReposAndCountsEachPullRequestOnceAcrossLists() {
    let a = pull(repo: "joao/zeta", number: 1)
    let b = pull(repo: "joao/alpha", number: 2)
    #expect(
      PullFiltering.options([a, b, a]).repos == [
        PullFilterOption(value: "joao/alpha", count: 1), PullFilterOption(value: "joao/zeta", count: 1),
      ])
  }

  @Test func leavesDeletedAuthorsOutOfTheAuthorOptions() {
    let items = [pull(number: 1, author: ""), pull(number: 2, author: "maria")]
    #expect(PullFiltering.options(items).authors == [PullFilterOption(value: "maria", count: 1)])
  }

  @Test func activeFiltersLabelsAndHiddenCountLeaveTheSearchOut() {
    let state = filters(
      query: " build ", repo: PullFilterGroup(values: ["joao/a"], mode: .exclude), author: include("maria", "joao"),
      state: [.ciFailing])
    #expect(
      PullFiltering.activeFilters(state).map(\.label) == [
        "Busca: build", "Repositório ≠ joao/a", "Autor: maria, joao", "CI falhando",
      ])
    #expect(state.isActive)
    #expect(!PullFilterState.empty.isActive)
  }
}

/// `tests/lib/pullAge.test.ts`.
@Suite struct PullAgeTests {
  private func age(_ createdAt: String, _ updatedAt: String) -> PullAge.Value? {
    PullAge.age(createdAt: createdAt, updatedAt: updatedAt, now: testNow)
  }

  @Test func countsTheDaysSinceOpening() {
    #expect(age("2026-10-12T12:00:00Z", "2026-10-21T10:00:00Z")?.opened == "aberto há 9 dias")
  }

  @Test func usesTheSingularForOneDay() {
    #expect(age("2026-10-20T11:00:00Z", "2026-10-21T10:00:00Z")?.opened == "aberto há 1 dia")
  }

  @Test func saysTodayUnderADay() {
    #expect(age("2026-10-21T01:00:00Z", "2026-10-21T01:00:00Z")?.opened == "aberto hoje")
  }

  @Test func marksAsStalledAfterThreeDays() {
    #expect(age("2026-10-01T12:00:00Z", "2026-10-17T11:00:00Z")?.stalled == "parado há 4 dias")
  }

  @Test func exactlyThreeDaysIsNotStalled() {
    #expect(age("2026-10-01T12:00:00Z", "2026-10-18T12:00:00Z")?.stalled == nil)
  }

  @Test func noAgeWithoutOpeningDate() {
    #expect(age("", "2026-10-18T12:00:00Z") == nil)
  }

  @Test func noAgeWithAnInvalidDate() {
    #expect(age("ontem", "2026-10-18T12:00:00Z") == nil)
  }
}

/// `tests/lib/githubLogin.test.ts` plus `teamSlug` and `isValidRepo`.
@Suite struct GitHubNamesTests {
  @Test(arguments: ["user-1", "a", "dependabot[bot]", String(repeating: "A", count: 39)])
  func acceptsLogin(_ login: String) {
    #expect(GitHubNames.isLogin(login))
  }

  @Test(arguments: ["-user", "user_1", "<script>", "", "[bot]", String(repeating: "A", count: 40), "x[bot][bot]"])
  func rejectsLogin(_ login: String) {
    #expect(!GitHubNames.isLogin(login))
  }

  @Test func requestableLogins() {
    #expect(GitHubNames.isRequestableLogin("user-1"))
    #expect(!GitHubNames.isRequestableLogin("dependabot[bot]"))
    #expect(!GitHubNames.isRequestableLogin("-user"))
  }

  @Test func teamsAndRepos() {
    #expect(GitHubNames.teamSlug("team:core_web") == "core_web")
    #expect(GitHubNames.teamSlug("team:") == nil)
    #expect(GitHubNames.isRepo("joao/a"))
    #expect(!GitHubNames.isRepo("a/b/c"))
    #expect(!GitHubNames.isRepo("nope"))
    #expect(GitHubNames.repoURL("nope") == nil)
    #expect(GitHubNames.repoURL("joao/a")?.absoluteString == "https://github.com/joao/a")
  }

  @Test func actionsURLEncodesTheQueryAsURLSearchParams() {
    #expect(
      GitHubNames.actionsURL(repo: "acme/api", branch: "release/1 x")?.absoluteString
        == "https://github.com/acme/api/actions?query=branch%3Arelease%2F1+x")
  }
}

/// `tests/lib/myPulls.test.ts`.
@Suite struct MyPullsTests {
  private func my(
    number: Int = 1,
    draft: Bool = false,
    updatedAt: String = "2026-10-20T10:00:00Z",
    ci: PullCI = .passing,
    review: PullReview = .pending,
    merge: PullMerge = .clean
  ) -> PullRequestItem {
    pull(
      repo: "acme/repo-1", number: number, author: "viewer", draft: draft, mine: true, updatedAt: updatedAt, ci: ci,
      review: review, merge: merge)
  }

  @Test func groups() {
    #expect(PullGrouping.myGroup(my(draft: true, ci: .failing)) == .draft)
    #expect(PullGrouping.myGroup(my(ci: .failing)) == .needsYou)
    #expect(PullGrouping.myGroup(my(review: .changesRequested)) == .needsYou)
    #expect(PullGrouping.myGroup(my(merge: .conflict)) == .needsYou)
    #expect(PullGrouping.myGroup(my(ci: .failing, review: .approved)) == .needsYou)
    #expect(PullGrouping.myGroup(my(ci: .passing, review: .approved, merge: .clean)) == .ready)
    #expect(PullGrouping.myGroup(my(ci: PullCI.none, review: .approved, merge: .clean)) == .ready)
    #expect(PullGrouping.myGroup(my(ci: .passing, review: .approved, merge: .unknown)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(review: .approved, merge: .blocked)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(ci: .running, review: .approved)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(review: .pending)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(ci: .passing, review: PullReview.none, merge: .clean)) == .ready)
    #expect(PullGrouping.myGroup(my(ci: .passing, review: PullReview.none, merge: .unknown)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(ci: .unknown, review: .approved)) == .waitingOthers)
    #expect(PullGrouping.myGroup(my(review: .unknown)) == .waitingOthers)
  }

  @Test func blockersInAFixedOrder() {
    #expect(
      PullGrouping.blockers(my(ci: .failing, review: .changesRequested, merge: .conflict)) == [
        .ciFailing, .changesRequested, .conflict,
      ])
    #expect(PullGrouping.blockers(my()).isEmpty)
  }

  @Test func ordersGroupsAndOmitsEmptyOnes() {
    let groups = PullGrouping.myPulls([
      my(number: 1, draft: true), my(number: 2, review: .approved), my(number: 3), my(number: 4, ci: .failing),
    ])
    #expect(groups.map(\.group) == [.needsYou, .waitingOthers, .ready, .draft])
    #expect(PullGrouping.myPulls([my(draft: true)]).map(\.group) == [.draft])
    #expect(PullGrouping.myPulls([]).isEmpty)
  }

  @Test func oldestFirstInNeedsYouNewestFirstElsewhere() {
    let needsYou = PullGrouping.myPulls([
      my(number: 1, updatedAt: "2026-10-20T10:00:00Z", ci: .failing),
      my(number: 2, updatedAt: "2026-10-01T10:00:00Z", ci: .failing),
    ])
    #expect(needsYou.first?.items.map(\.number) == [2, 1])
    let waiting = PullGrouping.myPulls([
      my(number: 1, updatedAt: "2026-10-01T10:00:00Z"), my(number: 2, updatedAt: "2026-10-20T10:00:00Z"),
    ])
    #expect(waiting.first?.items.map(\.number) == [2, 1])
  }

  @Test func byRepoSortsReposAndRanksAwaitingThenMineThenRecent() {
    let groups = PullGrouping.byRepo([
      pull(repo: "b/z", number: 1),
      pull(repo: "a/y", number: 2, updatedAt: "2026-10-01T00:00:00Z"),
      pull(repo: "a/y", number: 3, mine: true, updatedAt: "2026-09-01T00:00:00Z"),
      pull(repo: "a/y", number: 4, awaitingYou: true, updatedAt: "2026-08-01T00:00:00Z"),
      pull(repo: "a/y", number: 5, updatedAt: "2026-10-05T00:00:00Z"),
      pull(repo: "a/y", number: 6, isPullRequest: false),
    ])
    #expect(groups.map(\.repo) == ["a/y", "b/z"])
    #expect(groups.first?.pulls.map(\.number) == [4, 3, 5, 2])
    #expect(groups.first?.issues.map(\.number) == [6])
  }
}

/// `tests/lib/pullJiraSync.test.ts` (`jiraSyncSuggestion`).
@Suite struct JiraSyncSuggestionTests {
  private let ready = pull(mine: true)
  private let draft = pull(draft: true, mine: true)
  private let issue = pull(isPullRequest: false)

  @Test func suggestions() {
    #expect(JiraSyncSuggestion.of(ready, jiraRef(.new)) == .move(.review))
    #expect(JiraSyncSuggestion.of(draft, jiraRef(.new)) == .move(.inProgress))
    #expect(JiraSyncSuggestion.of(ready, jiraRef(.done)) == .diverged)
    #expect(JiraSyncSuggestion.of(draft, jiraRef(.done)) == .diverged)
    #expect(JiraSyncSuggestion.of(ready, jiraRef(.indeterminate)) == nil)
    #expect(JiraSyncSuggestion.of(draft, jiraRef(.indeterminate)) == nil)
  }

  @Test(arguments: [JiraStatusCategory.new, .indeterminate, .done])
  func nothingForAnIssue(_ category: JiraStatusCategory) {
    #expect(JiraSyncSuggestion.of(issue, jiraRef(category)) == nil)
  }

  @Test func statusIsNormalized() {
    #expect(PullFormat.status("  EM ANDAMENTO ") == "Em andamento")
    #expect(PullFormat.status("") == "")
  }
}

/// `tests/components/PullActions.test.tsx`: the menu and the forms' rules.
@Suite struct PullActionRulesTests {
  @Test func onlyCommentOnAnIssue() {
    #expect(PullAction.entries(for: pull(isPullRequest: false)) == [.comment])
  }

  @Test func reviewOnSomeoneElsesPullRequest() {
    #expect(PullAction.entries(for: pull()) == [.approve, .requestChanges, .comment, .merge])
  }

  @Test func noReviewOnYourOwn() {
    let entries = PullAction.entries(for: pull(mine: true, review: .approved))
    #expect(!entries.contains(.approve) && !entries.contains(.requestChanges))
  }

  @Test(arguments: [PullReview.changesRequested, .pending])
  func rerequestOnYourOwn(_ review: PullReview) {
    #expect(PullAction.entries(for: pull(mine: true, review: review)).contains(.rerequest))
  }

  @Test(arguments: [PullMerge.conflict, .blocked, .unknown])
  func mergeOnlyWhenClean(_ merge: PullMerge) {
    #expect(!PullAction.entries(for: pull(merge: merge)).contains(.merge))
  }

  @Test func noMergeOnADraftOrWithoutHead() {
    #expect(!PullAction.entries(for: pull(draft: true)).contains(.merge))
    #expect(!PullAction.entries(for: pull(headSha: nil)).contains(.merge))
  }

  @Test func rerunOnlyWhenFailing() {
    #expect(PullAction.entries(for: pull(ci: .failing)).contains(.rerun))
    #expect(!PullAction.entries(for: pull(ci: .passing)).contains(.rerun))
    #expect(!PullAction.entries(for: pull(ci: .failing, headSha: nil)).contains(.rerun))
  }

  @Test func candidatesIncludeReviewersWithoutAuthorOrRepeats() {
    let item = pull(
      author: "viewer", mine: true, pendingReviewers: ["ana", "team:core", "dependabot[bot]"],
      reviewers: [
        PullReviewer(login: "Ana", state: .commented), PullReviewer(login: "bruno", state: .changesRequested),
        PullReviewer(login: "viewer", state: .commented),
      ])
    #expect(PullActionRules.rerequestCandidates(item) == ["ana", "team:core", "bruno"])
  }

  @Test func typedLoginsAreCheckedAndCapped() {
    #expect(PullActionRules.reviewers(chosen: ["ana"], typed: "bruno, ana  carla") == ["ana", "bruno", "carla"])
    #expect(PullActionRules.rerequestProblem(chosen: [], typed: "ok, <x>") == "\"<x>\" não é um login do GitHub")
    let many = (1...16).map { "user\($0)" }.joined(separator: ",")
    #expect(PullActionRules.rerequestProblem(chosen: [], typed: many) == "no máximo 15 revisores")
    #expect(PullActionRules.rerequestProblem(chosen: ["ana"], typed: "") == nil)
  }

  @Test func rerunMessages() {
    #expect(PullActionRules.rerunMessage(rerun: 2, failed: []) == "2 workflow(s) rodando de novo")
    #expect(
      PullActionRules.rerunMessage(rerun: 1, failed: ["sem permissão"])
        == "1 workflow(s) rodando de novo; 1 recusado(s) pelo GitHub: sem permissão")
    #expect(PullActionRules.rerunMessage(rerun: 0, failed: []) == PullActionRules.noActionsRun)
  }
}
