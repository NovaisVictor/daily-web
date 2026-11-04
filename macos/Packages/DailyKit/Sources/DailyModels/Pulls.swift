/// Last-commit check rollup; `none` means no checks at all (`lib/types.ts:82`).
public struct PullCI: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let passing = PullCI(rawValue: "passing")
  public static let failing = PullCI(rawValue: "failing")
  public static let running = PullCI(rawValue: "running")
  public static let none = PullCI(rawValue: "none")
  public static let unknown = PullCI(rawValue: "unknown")
  public static let known: [PullCI] = [.passing, .failing, .running, .none, .unknown]
}

/// GitHub's reviewDecision; `none` means the repo requires no review (`lib/types.ts:85`).
public struct PullReview: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let approved = PullReview(rawValue: "approved")
  public static let changesRequested = PullReview(rawValue: "changes-requested")
  public static let pending = PullReview(rawValue: "pending")
  public static let none = PullReview(rawValue: "none")
  public static let unknown = PullReview(rawValue: "unknown")
  public static let known: [PullReview] = [.approved, .changesRequested, .pending, .none, .unknown]
}

/// Mergeability (`lib/types.ts:89`). `unknown` is "not computed yet", never a
/// conflict; `none` is only used for issues.
public struct PullMerge: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let clean = PullMerge(rawValue: "clean")
  public static let conflict = PullMerge(rawValue: "conflict")
  public static let blocked = PullMerge(rawValue: "blocked")
  public static let unknown = PullMerge(rawValue: "unknown")
  public static let none = PullMerge(rawValue: "none")
  public static let known: [PullMerge] = [.clean, .conflict, .blocked, .unknown, .none]
}

/// A reviewer's latest review (`lib/types.ts:92`).
public struct PullReviewerState: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let approved = PullReviewerState(rawValue: "approved")
  public static let changesRequested = PullReviewerState(rawValue: "changes-requested")
  public static let commented = PullReviewerState(rawValue: "commented")
  public static let dismissed = PullReviewerState(rawValue: "dismissed")
  public static let pending = PullReviewerState(rawValue: "pending")
  public static let unknown = PullReviewerState(rawValue: "unknown")
  public static let known: [PullReviewerState] = [
    .approved, .changesRequested, .commented, .dismissed, .pending, .unknown,
  ]
}

/// `lib/types.ts:94-97`.
public struct PullReviewer: Codable, Sendable, Equatable, Hashable {
  public var login: String
  public var state: PullReviewerState

  public init(login: String, state: PullReviewerState) {
    self.login = login
    self.state = state
  }
}

/// `lib/types.ts:99-102`.
public struct PullFailedCheck: Codable, Sendable, Equatable, Hashable {
  public var name: String
  public var url: String?

  public init(name: String, url: String?) {
    self.name = name
    self.url = url
  }
}

/// `lib/types.ts:104-108`.
public struct PullSize: Codable, Sendable, Equatable, Hashable {
  public var additions: Int
  public var deletions: Int
  public var files: Int

  public init(additions: Int, deletions: Int, files: Int) {
    self.additions = additions
    self.deletions = deletions
    self.files = files
  }
}

/// A Jira card cited in a PR title (`lib/types.ts:153-158`).
public struct PullJiraRef: Codable, Sendable, Equatable, Hashable {
  public var key: String
  public var url: String
  public var status: String
  public var statusCategory: JiraStatusCategory

  public init(key: String, url: String, status: String, statusCategory: JiraStatusCategory) {
    self.key = key
    self.url = url
    self.status = status
    self.statusCategory = statusCategory
  }
}

/// An open pull request or issue (`lib/types.ts:114-151`). On issues the PR-only
/// fields hold their "not applicable" value: `none`, empty lists and null.
public struct PullRequestItem: Codable, Sendable, Equatable, Hashable, Identifiable {
  /// GraphQL node id, used by writes.
  public var id: String
  public var repo: String
  public var number: Int
  public var title: String
  public var url: String
  /// Empty when the author account was deleted.
  public var author: String
  public var draft: Bool
  public var awaitingYou: Bool
  public var mine: Bool
  public var isPullRequest: Bool
  public var updatedAt: String
  public var createdAt: String
  public var ci: PullCI
  public var failedChecks: [PullFailedCheck]
  public var review: PullReview
  /// Logins, and teams as `team:<slug>`.
  public var pendingReviewers: [String]
  public var reviewers: [PullReviewer]
  /// Only the review-requests search fills it.
  public var reviewRequestedAt: String?
  public var merge: PullMerge
  public var size: PullSize?
  public var headRef: String?
  public var baseRef: String?
  public var headSha: String?
  public var jira: [PullJiraRef]?

  public init(
    id: String,
    repo: String,
    number: Int,
    title: String,
    url: String,
    author: String,
    draft: Bool,
    awaitingYou: Bool,
    mine: Bool,
    isPullRequest: Bool,
    updatedAt: String,
    createdAt: String,
    ci: PullCI,
    failedChecks: [PullFailedCheck],
    review: PullReview,
    pendingReviewers: [String],
    reviewers: [PullReviewer],
    reviewRequestedAt: String?,
    merge: PullMerge,
    size: PullSize?,
    headRef: String?,
    baseRef: String?,
    headSha: String?,
    jira: [PullJiraRef]? = nil
  ) {
    self.id = id
    self.repo = repo
    self.number = number
    self.title = title
    self.url = url
    self.author = author
    self.draft = draft
    self.awaitingYou = awaitingYou
    self.mine = mine
    self.isPullRequest = isPullRequest
    self.updatedAt = updatedAt
    self.createdAt = createdAt
    self.ci = ci
    self.failedChecks = failedChecks
    self.review = review
    self.pendingReviewers = pendingReviewers
    self.reviewers = reviewers
    self.reviewRequestedAt = reviewRequestedAt
    self.merge = merge
    self.size = size
    self.headRef = headRef
    self.baseRef = baseRef
    self.headSha = headSha
    self.jira = jira
  }
}

/// Review requests from any repository the token sees (`lib/types.ts:162-172`).
public struct ReviewRequestsDigest: Codable, Sendable, Equatable, Hashable {
  public var items: [PullRequestItem]
  public var truncated: Bool
  public var total: Int
  /// Token reach warning, only when the list came back empty.
  public var scopeNote: String?
  public var errors: [String]?

  public init(
    items: [PullRequestItem],
    truncated: Bool,
    total: Int,
    scopeNote: String?,
    errors: [String]? = nil
  ) {
    self.items = items
    self.truncated = truncated
    self.total = total
    self.scopeNote = scopeNote
    self.errors = errors
  }
}

/// The user's own open PRs (`lib/types.ts:175-181`).
public struct MyPullsDigest: Codable, Sendable, Equatable, Hashable {
  public var items: [PullRequestItem]
  public var truncated: Bool
  public var total: Int
  public var errors: [String]?

  public init(items: [PullRequestItem], truncated: Bool, total: Int, errors: [String]? = nil) {
    self.items = items
    self.truncated = truncated
    self.total = total
    self.errors = errors
  }
}

/// `lib/types.ts:183-187`.
public struct DefaultBranchStatus: Codable, Sendable, Equatable, Hashable {
  public var repo: String
  public var branch: String
  public var ci: PullCI

  public init(repo: String, branch: String, ci: PullCI) {
    self.repo = repo
    self.branch = branch
    self.ci = ci
  }
}

/// `pulls` or `issues` (`lib/types.ts:192`).
public struct PullsTruncationKind: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let pulls = PullsTruncationKind(rawValue: "pulls")
  public static let issues = PullsTruncationKind(rawValue: "issues")
  public static let known: [PullsTruncationKind] = [.pulls, .issues]
}

/// A tracked repo with more open items than one page (`lib/types.ts:190-195`).
public struct PullsTruncation: Codable, Sendable, Equatable, Hashable {
  public var repo: String
  public var kind: PullsTruncationKind
  public var shown: Int
  public var total: Int

  public init(repo: String, kind: PullsTruncationKind, shown: Int, total: Int) {
    self.repo = repo
    self.kind = kind
    self.shown = shown
    self.total = total
  }
}

/// The tracked repositories panel (`lib/types.ts:197-204`).
public struct PullsDigest: Codable, Sendable, Equatable, Hashable {
  public var items: [PullRequestItem]
  /// Repositories that failed on their own.
  public var errors: [String]
  public var defaultBranches: [DefaultBranchStatus]
  public var truncated: [PullsTruncation]

  public init(
    items: [PullRequestItem],
    errors: [String],
    defaultBranches: [DefaultBranchStatus],
    truncated: [PullsTruncation]
  ) {
    self.items = items
    self.errors = errors
    self.defaultBranches = defaultBranches
    self.truncated = truncated
  }
}

/// `GET`, `POST`, `DELETE /api/pulls/repos` and `PUT /api/pulls/repos/authors`
/// (`app/api/pulls/repos/route.ts:11,14,29`, `lib/operations/github.ts:56-60`).
/// A repo missing from `authors` follows everyone.
public struct PullReposResponse: Codable, Sendable, Equatable, Hashable {
  public var repos: [String]
  public var authors: [String: [String]]

  public init(repos: [String], authors: [String: [String]]) {
    self.repos = repos
    self.authors = authors
  }
}

/// `GET /api/pulls/jira-sync` (`app/api/pulls/jira-sync/route.ts:24`).
public struct PullJiraSyncResponse: Codable, Sendable, Equatable, Hashable {
  public var transition: JiraTransition

  public init(transition: JiraTransition) {
    self.transition = transition
  }
}

/// `POST …/comments` (`app/api/pulls/[owner]/[repo]/[number]/comments/route.ts:20`,
/// `lib/integrations/github/actions.ts:97-100`).
public struct PullCommentResponse: Codable, Sendable, Equatable, Hashable {
  public struct Comment: Codable, Sendable, Equatable, Hashable {
    public var id: Int
    public var url: String

    public init(id: Int, url: String) {
      self.id = id
      self.url = url
    }
  }

  public var ok: Bool
  public var comment: Comment

  public init(ok: Bool, comment: Comment) {
    self.ok = ok
    self.comment = comment
  }
}

/// `POST …/merge` (`app/api/pulls/[owner]/[repo]/[number]/merge/route.ts:28`).
public struct PullMergeResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var sha: String

  public init(ok: Bool, sha: String) {
    self.ok = ok
    self.sha = sha
  }
}

/// A run GitHub did not accept to re-run (`lib/integrations/github/actions.ts:206-209`).
public struct PullRerunFailure: Codable, Sendable, Equatable, Hashable {
  public var id: Int
  public var error: String

  public init(id: Int, error: String) {
    self.id = id
    self.error = error
  }
}

/// `POST …/rerun` (`app/api/pulls/[owner]/[repo]/[number]/rerun/route.ts:20`,
/// `app/api/pulls/shared.ts:20-25`). `rerun` 0 with no failures means the
/// failing check is not from Actions.
public struct PullRerunResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var rerun: Int
  public var failed: [PullRerunFailure]

  public init(ok: Bool, rerun: Int, failed: [PullRerunFailure]) {
    self.ok = ok
    self.rerun = rerun
    self.failed = failed
  }
}

/// `POST …/reviewers` (`app/api/pulls/[owner]/[repo]/[number]/reviewers/route.ts:41`):
/// who is requested afterwards, teams as `team:<slug>`.
public struct PullReviewersResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var requested: [String]

  public init(ok: Bool, requested: [String]) {
    self.ok = ok
    self.requested = requested
  }
}

/// The state GitHub gives a submitted review (`lib/operations/results.ts:6`).
public struct PullSubmittedReviewState: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let approved = PullSubmittedReviewState(rawValue: "APPROVED")
  public static let changesRequested = PullSubmittedReviewState(rawValue: "CHANGES_REQUESTED")
  public static let known: [PullSubmittedReviewState] = [.approved, .changesRequested]
}

/// `POST …/reviews` (`app/api/pulls/[owner]/[repo]/[number]/reviews/route.ts:28`,
/// `lib/integrations/github/actions.ts:73-76`).
public struct PullReviewResponse: Codable, Sendable, Equatable, Hashable {
  public struct Review: Codable, Sendable, Equatable, Hashable {
    public var id: Int
    public var state: PullSubmittedReviewState

    public init(id: Int, state: PullSubmittedReviewState) {
      self.id = id
      self.state = state
    }
  }

  public var ok: Bool
  public var review: Review

  public init(ok: Bool, review: Review) {
    self.ok = ok
    self.review = review
  }
}
