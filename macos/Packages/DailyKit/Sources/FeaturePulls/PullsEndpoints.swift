import DailyAPI
import DailyModels
import Foundation

/// `app/api/pulls/**`. Every write is idempotent: the routes read
/// `Idempotency-Key` and `X-Request-Timestamp` (`app/api/pulls/shared.ts:15`).
nonisolated enum PullsEndpoints {
  struct RepoBody: Encodable, Sendable, Equatable {
    var repo: String
  }

  struct AuthorsBody: Encodable, Sendable, Equatable {
    var repo: String
    var authors: [String]
  }

  /// `body` is left out when empty, as the web does for an approval without text.
  struct ReviewBody: Encodable, Sendable, Equatable {
    enum Event: String, Encodable, Sendable {
      case approve = "APPROVE"
      case requestChanges = "REQUEST_CHANGES"
    }

    var event: Event
    var body: String?
  }

  struct CommentBody: Encodable, Sendable, Equatable {
    var body: String
  }

  struct ReviewersBody: Encodable, Sendable, Equatable {
    var reviewers: [String]
  }

  /// `headSha` is the commit the user saw: GitHub refuses the merge if the PR moved.
  struct MergeBody: Encodable, Sendable, Equatable {
    var method: MergeMethod
    var headSha: String
  }

  struct RerunBody: Encodable, Sendable, Equatable {
    var headSha: String
  }

  struct TransitionBody: Encodable, Sendable, Equatable {
    var transitionId: String
  }

  static var repos: Endpoint<PullReposResponse> { Endpoint(.get, "/api/pulls/repos") }

  static func addRepo(_ repo: String) -> Endpoint<PullReposResponse> {
    Endpoint(.post, "/api/pulls/repos", body: RepoBody(repo: repo), idempotent: true)
  }

  static func removeRepo(_ repo: String) -> Endpoint<PullReposResponse> {
    Endpoint(.delete, "/api/pulls/repos", body: RepoBody(repo: repo), idempotent: true)
  }

  static func setAuthors(repo: String, _ authors: [String]) -> Endpoint<PullReposResponse> {
    Endpoint(.put, "/api/pulls/repos/authors", body: AuthorsBody(repo: repo, authors: authors), idempotent: true)
  }

  /// The transition that would move the card for `intent`; 404 when none matches.
  static func jiraSync(key: String, intent: JiraSyncIntent) -> Endpoint<PullJiraSyncResponse> {
    Endpoint(
      .get, "/api/pulls/jira-sync",
      query: [URLQueryItem(name: "key", value: key), URLQueryItem(name: "intent", value: intent.rawValue)])
  }

  /// The move itself goes through the Jira route, as `PullJiraSync.tsx` does;
  /// it is not a pulls write, so it carries no idempotency key.
  static func transition(key: String, transitionId: String) -> Endpoint<EmptyResponse> {
    Endpoint(
      .post, "/api/jira/issues/\(Endpoint<EmptyResponse>.segment(key))/transitions",
      body: TransitionBody(transitionId: transitionId))
  }

  static func review(_ item: PullRequestItem, _ body: ReviewBody) -> Endpoint<PullReviewResponse> {
    Endpoint(.post, path(item, "reviews"), body: body, idempotent: true)
  }

  static func comment(_ item: PullRequestItem, body: String) -> Endpoint<PullCommentResponse> {
    Endpoint(.post, path(item, "comments"), body: CommentBody(body: body), idempotent: true)
  }

  static func requestReviewers(_ item: PullRequestItem, _ reviewers: [String]) -> Endpoint<PullReviewersResponse> {
    Endpoint(.post, path(item, "reviewers"), body: ReviewersBody(reviewers: reviewers), idempotent: true)
  }

  static func merge(_ item: PullRequestItem, method: MergeMethod, headSha: String) -> Endpoint<PullMergeResponse> {
    Endpoint(.post, path(item, "merge"), body: MergeBody(method: method, headSha: headSha), idempotent: true)
  }

  static func rerun(_ item: PullRequestItem, headSha: String) -> Endpoint<PullRerunResponse> {
    Endpoint(.post, path(item, "rerun"), body: RerunBody(headSha: headSha), idempotent: true)
  }

  /// `actionUrl` in `PullActions.tsx`: `/api/pulls/{owner}/{name}/{number}/{action}`.
  static func path(_ item: PullRequestItem, _ action: String) -> String {
    let parts = item.repo.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    let owner = parts.first ?? ""
    let name = parts.count > 1 ? parts[1] : ""
    let segment = Endpoint<EmptyResponse>.segment
    return "/api/pulls/\(segment(owner))/\(segment(name))/\(item.number)/\(action)"
  }
}
