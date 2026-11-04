import DailyCore
import DailyModels
import Foundation

/// Sample pull requests for previews: invented repositories and people.
enum PullsPreviewData {
  static func item(
    _ number: Int,
    repo: String = "acme/web",
    title: String,
    author: String = "maria",
    mine: Bool = false,
    awaitingYou: Bool = false,
    draft: Bool = false,
    ci: PullCI = .passing,
    review: PullReview = .pending,
    merge: PullMerge = .clean,
    jira: [PullJiraRef]? = nil
  ) -> PullRequestItem {
    PullRequestItem(
      id: "PR_\(number)", repo: repo, number: number, title: title,
      url: "https://github.com/\(repo)/pull/\(number)", author: author, draft: draft, awaitingYou: awaitingYou,
      mine: mine, isPullRequest: true, updatedAt: "2026-11-01T10:00:00Z", createdAt: "2026-10-28T10:00:00Z", ci: ci,
      failedChecks: ci == .failing ? [PullFailedCheck(name: "build", url: nil)] : [], review: review,
      pendingReviewers: review == .pending ? ["joao"] : [], reviewers: [], reviewRequestedAt: nil, merge: merge,
      size: PullSize(additions: 120, deletions: 8, files: 4), headRef: "feature/x", baseRef: "main",
      headSha: String(repeating: "a", count: 40), jira: jira)
  }

  static var state: DashboardState {
    var state = PreviewFixtures.dashboard
    let card = PullJiraRef(
      key: "TT-42", url: "https://example.atlassian.net/browse/TT-42", status: "Backlog", statusCategory: .new)
    state.pulls = PanelResult(
      data: PullsDigest(
        items: [
          item(12, title: "Arrumar o build", awaitingYou: true, jira: [card]),
          item(15, title: "Novo cabeçalho", author: "joao", ci: .failing, review: .changesRequested),
          item(3, repo: "acme/api", title: "Paginar a busca", mine: true, review: .approved),
        ],
        errors: [],
        defaultBranches: [DefaultBranchStatus(repo: "acme/api", branch: "main", ci: .failing)],
        truncated: []
      ),
      error: nil)
    state.reviewRequests = PanelResult(
      data: ReviewRequestsDigest(
        items: [item(12, title: "Arrumar o build", awaitingYou: true)], truncated: false, total: 1, scopeNote: nil),
      error: nil)
    state.myPulls = PanelResult(
      data: MyPullsDigest(
        items: [
          item(3, repo: "acme/api", title: "Paginar a busca", mine: true, review: .approved),
          item(7, repo: "acme/api", title: "Rascunho do cache", mine: true, draft: true),
        ],
        truncated: false, total: 2),
      error: nil)
    return state
  }
}
