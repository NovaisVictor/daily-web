import DailyModels
import Foundation

// MARK: - Dates and age (`lib/pullAge.ts`)

nonisolated enum PullAge {
  static let dayMs: Double = 86_400_000
  static let staleUpdateMs: Double = 3 * dayMs

  /// What the row shows: how long it has been open, and how long it has been
  /// stalled when that is more than three days.
  struct Value: Equatable, Sendable {
    let opened: String
    let stalled: String?
  }

  /// `Date.parse` for the ISO shapes GitHub sends. A date-time without a zone
  /// is local time, as in JavaScript; anything unreadable is nil (`NaN`).
  static func parse(_ text: String, timeZone: TimeZone = .current) -> Date? {
    let pattern =
      #/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:?\d{2})?)?$/#
    guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern) else { return nil }
    var components = DateComponents()
    components.year = Int(match.1)
    components.month = Int(match.2)
    components.day = Int(match.3)
    components.hour = match.4.flatMap { Int($0) } ?? 0
    components.minute = match.5.flatMap { Int($0) } ?? 0
    components.second = match.6.flatMap { Int($0) } ?? 0
    if let fraction = match.7 {
      let digits = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
      components.nanosecond = (Int(digits) ?? 0) * 1_000_000
    }
    var calendar = Calendar(identifier: .gregorian)
    if match.4 == nil {
      calendar.timeZone = .gmt
    } else if let zone = match.8 {
      guard let offset = offsetSeconds(String(zone)), let fixed = TimeZone(secondsFromGMT: offset) else { return nil }
      calendar.timeZone = fixed
    } else {
      calendar.timeZone = timeZone
    }
    guard let date = calendar.date(from: components), calendar.component(.day, from: date) == components.day else {
      return nil
    }
    return date
  }

  private static func offsetSeconds(_ zone: String) -> Int? {
    if zone == "Z" { return 0 }
    let sign = zone.hasPrefix("-") ? -1 : 1
    let digits = zone.dropFirst().filter(\.isNumber)
    guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else {
      return nil
    }
    return sign * (hours * 3600 + minutes * 60)
  }

  /// `elapsedMs`: never negative, nil without a readable date.
  static func elapsedMs(_ iso: String, now: Date) -> Double? {
    guard !iso.isEmpty, let date = parse(iso) else { return nil }
    return max(0, now.timeIntervalSince(date) * 1000)
  }

  /// One rule for "parado" everywhere: the stale filter and the row badge agree.
  static func isStale(updatedAt: String, now: Date) -> Bool {
    guard let idle = elapsedMs(updatedAt, now: now) else { return false }
    return idle > staleUpdateMs
  }

  static func formatDays(_ ms: Double) -> String {
    PullFormat.count(Int((ms / dayMs).rounded(.down)), singular: "dia", plural: "dias")
  }

  static func age(createdAt: String, updatedAt: String, now: Date) -> Value? {
    guard let open = elapsedMs(createdAt, now: now) else { return nil }
    let idle = elapsedMs(updatedAt, now: now)
    let stalled = idle.flatMap { isStale(updatedAt: updatedAt, now: now) ? "parado há \(formatDays($0))" : nil }
    return Value(opened: open < dayMs ? "aberto hoje" : "aberto há \(formatDays(open))", stalled: stalled)
  }
}

/// Numbers as `Intl.NumberFormat('pt-BR')` writes them (`lib/format.ts`).
nonisolated enum PullFormat {
  static func number(_ value: Int) -> String {
    value.formatted(.number.locale(Locale(identifier: "pt-BR")))
  }

  /// "1 items" in a selector is what makes a screen look careless.
  static func count(_ value: Int, singular: String, plural: String) -> String {
    "\(number(value)) \(value == 1 ? singular : plural)"
  }

  /// `normalizeStatus` (`lib/parsers/jira.ts:152`): Jira statuses come in any case.
  static func status(_ status: String) -> String {
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "" }
    let locale = Locale(identifier: "pt-BR")
    let lower = trimmed.lowercased(with: locale)
    return String(first).uppercased(with: locale) + lower.dropFirst()
  }
}

// MARK: - Validation (`lib/githubLogin.ts`, `lib/api/validation.ts`, `lib/integrations/github/actions.ts`)

nonisolated enum GitHubNames {
  /// `REVIEWERS_MAX`.
  static let reviewersMax = 15
  /// `TEXT_MAX`, in UTF-16 units as JavaScript counts.
  static let textMax = 10_000
  /// `AUTHORS_PER_REPO_MAX`.
  static let authorsPerRepoMax = 10

  // Computed: `Regex` is not `Sendable`, so it cannot be a stored static.
  private static var login: Regex<Substring> { #/^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/# }
  private static var team: Regex<(Substring, Substring)> { #/^team:([A-Za-z0-9][A-Za-z0-9_-]{0,99})$/# }
  private static var repo: Regex<Substring> { #/^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/# }
  private static let botSuffix = "[bot]"

  /// Any author GitHub shows, apps included (`dependabot[bot]`).
  static func isLogin(_ value: String) -> Bool {
    let bare = value.hasSuffix(botSuffix) ? String(value.dropLast(botSuffix.count)) : value
    return bare.wholeMatch(of: login) != nil
  }

  /// A user GitHub accepts as a requested reviewer: apps cannot be asked to review.
  static func isRequestableLogin(_ value: String) -> Bool {
    value.wholeMatch(of: login) != nil
  }

  /// The slug of a `team:<slug>` entry.
  static func teamSlug(_ value: String) -> String? {
    value.wholeMatch(of: team).map { String($0.1) }
  }

  static func isRepo(_ value: String) -> Bool {
    value.wholeMatch(of: repo) != nil
  }

  /// `repoUrl`: only a well-formed `owner/name` becomes a link.
  static func repoURL(_ repo: String) -> URL? {
    guard isRepo(repo) else { return nil }
    return URL(string: "https://github.com/\(repo)")
  }

  /// `actionsUrl` in `DefaultBranchAlert.tsx`: the Actions runs of that branch.
  static func actionsURL(repo: String, branch: String) -> URL? {
    guard let base = repoURL(repo) else { return nil }
    return URL(string: base.absoluteString + "/actions?query=" + formEncode("branch:\(branch)"))
  }

  /// `URLSearchParams` value encoding (application/x-www-form-urlencoded).
  static func formEncode(_ value: String) -> String {
    let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._".utf8)
    var out = ""
    for byte in value.utf8 {
      if unreserved.contains(byte) {
        out.unicodeScalars.append(Unicode.Scalar(byte))
      } else if byte == 0x20 {
        out += "+"
      } else {
        out += String(format: "%%%02X", byte)
      }
    }
    return out
  }
}

// MARK: - Grouping (`lib/integrations/githubApi.ts`, `lib/myPulls.ts`)

/// One tracked repository, issues apart from pull requests (`RepoGroup`).
nonisolated struct RepoGroup: Equatable, Sendable, Identifiable {
  let repo: String
  var issues: [PullRequestItem]
  var pulls: [PullRequestItem]
  var id: String { repo }
}

/// The groups of "Meus PRs", in display order.
nonisolated enum MyPullGroup: String, CaseIterable, Sendable {
  case needsYou = "needs-you"
  case waitingOthers = "waiting-others"
  case ready
  case draft

  var label: String {
    switch self {
    case .needsYou: "Precisa de você"
    case .waitingOthers: "Esperando os outros"
    case .ready: "Pronto para merge"
    case .draft: "Rascunho"
    }
  }
}

nonisolated enum MyPullBlocker: String, CaseIterable, Sendable {
  case ciFailing = "ci-failing"
  case changesRequested = "changes-requested"
  case conflict

  var label: String {
    switch self {
    case .ciFailing: "CI falhou"
    case .changesRequested: "pediram mudanças"
    case .conflict: "conflito"
    }
  }
}

nonisolated enum PullGrouping {
  /// Groups by repository and splits issues from pull requests, repos sorted by name.
  static func byRepo(_ items: [PullRequestItem]) -> [RepoGroup] {
    var order: [String] = []
    var groups: [String: RepoGroup] = [:]
    for item in items {
      if groups[item.repo] == nil {
        order.append(item.repo)
        groups[item.repo] = RepoGroup(repo: item.repo, issues: [], pulls: [])
      }
      if item.isPullRequest {
        groups[item.repo]?.pulls.append(item)
      } else {
        groups[item.repo]?.issues.append(item)
      }
    }
    return order.compactMap { groups[$0] }
      .map { RepoGroup(repo: $0.repo, issues: rank($0.issues), pulls: rank($0.pulls)) }
      .sorted { $0.repo.localizedCompare($1.repo) == .orderedAscending }
  }

  /// What awaits your review first, then yours, then the most recently updated (`rankPulls`).
  static func rank(_ items: [PullRequestItem]) -> [PullRequestItem] {
    items.enumerated().sorted { lhs, rhs in
      let a = lhs.element
      let b = rhs.element
      if a.awaitingYou != b.awaitingYou { return a.awaitingYou }
      if a.mine != b.mine { return a.mine }
      if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
      return lhs.offset < rhs.offset
    }
    .map(\.element)
  }

  /// `myPullBlockers`, in a fixed order.
  static func blockers(_ item: PullRequestItem) -> [MyPullBlocker] {
    var out: [MyPullBlocker] = []
    if item.ci == .failing { out.append(.ciFailing) }
    if item.review == .changesRequested { out.append(.changesRequested) }
    if item.merge == .conflict { out.append(.conflict) }
    return out
  }

  /// `myPullGroup`: a draft is a draft first; `unknown` states never count as
  /// failing or approved.
  static func myGroup(_ item: PullRequestItem) -> MyPullGroup {
    if item.draft { return .draft }
    if !blockers(item).isEmpty { return .needsYou }
    if (item.review == .approved || item.review == PullReview.none)
      && (item.ci == .passing || item.ci == PullCI.none) && item.merge == .clean
    {
      return .ready
    }
    return .waitingOthers
  }

  /// `groupMyPulls`: empty groups left out; the oldest first in "Precisa de
  /// você", the most recent first elsewhere.
  static func myPulls(_ items: [PullRequestItem]) -> [(group: MyPullGroup, items: [PullRequestItem])] {
    MyPullGroup.allCases.compactMap { group in
      let oldestFirst = group == .needsYou
      let grouped = items.enumerated()
        .filter { myGroup($0.element) == group }
        .sorted { lhs, rhs in
          let a = updatedTime(lhs.element)
          let b = updatedTime(rhs.element)
          if a != b { return oldestFirst ? a < b : a > b }
          return lhs.offset < rhs.offset
        }
        .map(\.element)
      return grouped.isEmpty ? nil : (group, grouped)
    }
  }

  private static func updatedTime(_ item: PullRequestItem) -> Double {
    PullAge.parse(item.updatedAt)?.timeIntervalSince1970 ?? 0
  }
}

// MARK: - Jira sync (`lib/pullJiraSync.ts`)

nonisolated enum JiraSyncIntent: String, Sendable, Hashable {
  case review
  case inProgress = "in-progress"

  /// `INTENT_LABEL`.
  var label: String {
    switch self {
    case .review: "revisão"
    case .inProgress: "em andamento"
    }
  }
}

nonisolated enum JiraSyncSuggestion: Equatable, Sendable {
  case move(JiraSyncIntent)
  /// A done card next to an open PR.
  case diverged

  /// Only open items reach the panel, so a done card next to one is always out of step.
  static func of(_ item: PullRequestItem, _ ref: PullJiraRef) -> JiraSyncSuggestion? {
    guard item.isPullRequest else { return nil }
    if ref.statusCategory == .done { return .diverged }
    if ref.statusCategory == .new { return .move(item.draft ? .inProgress : .review) }
    return nil
  }
}

// MARK: - Actions (`components/pulls/PullActions.tsx`)

/// The row menu's entries, each one opening its own dialog.
nonisolated enum PullAction: String, CaseIterable, Sendable, Identifiable {
  case approve
  case requestChanges = "request-changes"
  case comment
  case rerequest
  case merge
  case rerun

  var id: String { rawValue }

  var label: String {
    switch self {
    case .approve: "Aprovar"
    case .requestChanges: "Pedir mudanças"
    case .comment: "Comentar"
    case .rerequest: "Pedir revisão de novo"
    case .merge: "Fazer merge"
    case .rerun: "Rodar CI de novo"
    }
  }

  var systemImage: String {
    switch self {
    case .approve: "checkmark"
    case .requestChanges: "xmark.circle"
    case .comment: "text.bubble"
    case .rerequest: "person.badge.plus"
    case .merge: "arrow.triangle.merge"
    case .rerun: "arrow.clockwise"
    }
  }

  /// `menuEntries`: an issue only takes a comment.
  static func entries(for item: PullRequestItem) -> [PullAction] {
    guard item.isPullRequest else { return [.comment] }
    var out: [PullAction] = []
    if !item.mine { out += [.approve, .requestChanges] }
    out.append(.comment)
    if item.mine && (item.review == .changesRequested || item.review == .pending) { out.append(.rerequest) }
    if item.merge == .clean && !item.draft && item.headSha != nil { out.append(.merge) }
    if item.ci == .failing && item.headSha != nil { out.append(.rerun) }
    return out
  }
}

nonisolated enum MergeMethod: String, CaseIterable, Sendable, Encodable {
  case merge
  case squash
  case rebase

  var label: String {
    switch self {
    case .merge: "merge commit"
    case .squash: "squash"
    case .rebase: "rebase"
    }
  }
}

nonisolated enum PullActionRules {
  static let noActionsRun =
    "nenhum workflow do GitHub Actions falhou neste commit (o check pode ser de outro serviço)"

  static func ref(_ item: PullRequestItem) -> String { "\(item.repo)#\(item.number)" }

  /// Entries the server accepts: a re-request of anything else would be refused.
  static func isRequestable(_ reviewer: String) -> Bool {
    GitHubNames.isRequestableLogin(reviewer) || GitHubNames.teamSlug(reviewer) != nil
  }

  /// Who can be asked again: the pending requests plus everyone who already
  /// reviewed (GitHub drops a request once its review arrives), minus the author.
  static func rerequestCandidates(_ item: PullRequestItem) -> [String] {
    let author = item.author.lowercased()
    var seen = Set<String>()
    var out: [String] = []
    for reviewer in item.pendingReviewers + item.reviewers.map(\.login) {
      let key = reviewer.lowercased()
      guard key != author, !seen.contains(key), isRequestable(reviewer) else { continue }
      seen.insert(key)
      out.append(reviewer)
    }
    return out
  }

  /// `typedLogins`: split on spaces and commas.
  static func typedLogins(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
  }

  /// The chosen ones then the typed ones, without repeats, in order (`new Set`).
  static func reviewers(chosen: [String], typed: String) -> [String] {
    var seen = Set<String>()
    return (chosen + typedLogins(typed)).filter { seen.insert($0).inserted }
  }

  /// What is wrong with the re-request form, or nil when it can be sent.
  static func rerequestProblem(chosen: [String], typed: String) -> String? {
    if let bad = typedLogins(typed).first(where: { !GitHubNames.isRequestableLogin($0) }) {
      return "\"\(bad)\" não é um login do GitHub"
    }
    if reviewers(chosen: chosen, typed: typed).count > GitHubNames.reviewersMax {
      return "no máximo \(GitHubNames.reviewersMax) revisores"
    }
    return nil
  }

  /// `rerunMessage`.
  static func rerunMessage(rerun: Int, failed: [String]) -> String {
    if rerun == 0 && failed.isEmpty { return noActionsRun }
    let ran = "\(rerun) workflow(s) rodando de novo"
    return failed.isEmpty ? ran : "\(ran); \(failed.count) recusado(s) pelo GitHub: \(failed.joined(separator: "; "))"
  }
}
