import DailyAPI
import DailyCore
import DailyModels
import Foundation

@testable import FeaturePulls

nonisolated let testSha = String(repeating: "a", count: 40)

/// `pull()` of the web tests (`tests/lib/pullFilters.test.ts`).
nonisolated func pull(
  repo: String = "joao/daily-web",
  number: Int = 3,
  title: String = "Arrumar o build",
  author: String = "joao",
  draft: Bool = false,
  awaitingYou: Bool = false,
  mine: Bool = false,
  isPullRequest: Bool = true,
  updatedAt: String = "2026-10-21T10:00:00Z",
  createdAt: String = "2026-10-20T10:00:00Z",
  ci: PullCI = .passing,
  failedChecks: [PullFailedCheck] = [],
  review: PullReview = .pending,
  pendingReviewers: [String] = [],
  reviewers: [PullReviewer] = [],
  merge: PullMerge = .clean,
  headSha: String? = testSha,
  jira: [PullJiraRef]? = nil
) -> PullRequestItem {
  PullRequestItem(
    id: "PR_\(number)", repo: repo, number: number, title: title, url: "https://github.com/\(repo)/pull/\(number)",
    author: author, draft: draft, awaitingYou: awaitingYou, mine: mine, isPullRequest: isPullRequest,
    updatedAt: updatedAt, createdAt: createdAt, ci: ci, failedChecks: failedChecks, review: review,
    pendingReviewers: pendingReviewers, reviewers: reviewers, reviewRequestedAt: nil, merge: merge,
    size: PullSize(additions: 1, deletions: 1, files: 1), headRef: "feature/x", baseRef: "main", headSha: headSha,
    jira: jira)
}

nonisolated func jiraRef(_ category: JiraStatusCategory, key: String = "TT-5019") -> PullJiraRef {
  PullJiraRef(key: key, url: "https://example.atlassian.net/browse/\(key)", status: "Backlog", statusCategory: category)
}

/// `new Date('2026-10-21T12:00:00Z')`.
nonisolated let testNow = Date(timeIntervalSince1970: 1_792_584_000)

func makeState(
  tracked: [PullRequestItem] = [],
  reviews: [PullRequestItem] = [],
  mine: [PullRequestItem] = []
) -> DashboardState {
  var state = PreviewFixtures.dashboard
  state.pulls = PanelResult(
    data: PullsDigest(items: tracked, errors: [], defaultBranches: [], truncated: []), error: nil)
  state.reviewRequests = PanelResult(
    data: ReviewRequestsDigest(items: reviews, truncated: false, total: reviews.count, scopeNote: nil), error: nil)
  state.myPulls = PanelResult(data: MyPullsDigest(items: mine, truncated: false, total: mine.count), error: nil)
  return state
}

nonisolated func reposJSON(_ repos: [String], authors: [String: [String]] = [:]) -> Data {
  FakeAPIClient.json(PullReposResponse(repos: repos, authors: authors))
}

/// A store over a fake client. `GET /api/state` answers the state given at the
/// start; writes answer `write`.
@MainActor
final class Harness {
  let client: FakeAPIClient
  let dashboard: DashboardStore
  let toasts: ToastCenter
  let store: PullsStore

  init(_ state: DashboardState = makeState()) {
    let client = FakeAPIClient()
    self.client = client
    let toasts = ToastCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    self.toasts = toasts
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    store = PullsStore(client: client, dashboard: dashboard, now: { testNow })
    dashboard.apply(state)
    serve(state: state)
  }

  /// Answers writes with `write` and the dashboard read with `state`.
  func serve(
    state: DashboardState,
    write: @escaping @Sendable (FakeAPIClient.Call) async throws(APIError) -> Data = { _ in FakeAPIClient.ok }
  ) {
    let stateData = FakeAPIClient.json(state)
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { return stateData }
      return try await write(call)
    }
  }

  /// Every write fails with the server's message.
  func failWrites(_ message: String = "falhou", status: Int = 409) {
    client.respond { call throws(APIError) in
      if call.path == "/api/state" { throw .offline }
      throw .server(status: status, message: message, code: nil, retry: nil)
    }
  }

  var reads: Int { client.calls.filter { $0.path == "/api/state" }.count }
}
