import DailyModels
import Foundation

/// The seven states of the filter popover (`PullState`, `lib/pullFilters.ts:7-14`).
nonisolated enum PullState: String, CaseIterable, Sendable, Hashable {
  case ciFailing = "ci-failing"
  case changesRequested = "changes-requested"
  case approved
  case conflict
  case draft
  case awaitingYou = "awaiting-you"
  case stale

  /// `PULL_STATE_LABEL`.
  var label: String {
    switch self {
    case .ciFailing: "CI falhando"
    case .changesRequested: "Mudanças pedidas"
    case .approved: "Aprovado"
    case .conflict: "Conflito"
    case .draft: "Rascunho"
    case .awaitingYou: "Aguardando você"
    case .stale: "Parado há 3+ dias"
    }
  }

  /// `STATE_GROUPS` in `components/pulls/PullFilters.tsx`: grouped by the
  /// question each state answers.
  static let groups: [(title: String, states: [PullState])] = [
    ("Revisão", [.approved, .changesRequested, .awaitingYou]),
    ("CI", [.ciFailing]),
    ("Situação", [.draft, .conflict, .stale]),
  ]
}

/// Include or exclude the selected values (`FilterMode`, `lib/jiraFilters.ts`).
nonisolated enum PullFilterMode: String, Sendable, Hashable {
  case include
  case exclude
}

/// One multi-value dimension: repo or author (`PullFilterGroup`).
nonisolated struct PullFilterGroup: Equatable, Sendable {
  var values: [String] = []
  var mode: PullFilterMode = .include

  func matches(_ value: String) -> Bool {
    guard !values.isEmpty else { return true }
    let hit = values.contains { $0.lowercased() == value.lowercased() }
    return mode == .include ? hit : !hit
  }

  /// Adds or removes `value`, keeping the mode.
  mutating func toggle(_ value: String) {
    if let index = values.firstIndex(of: value) {
      values.remove(at: index)
    } else {
      values.append(value)
    }
  }

  /// `groupLabel` in `PullFilters.tsx`.
  func label(_ name: String) -> String {
    "\(name)\(mode == .exclude ? " ≠" : ":") \(values.joined(separator: ", "))"
  }
}

/// `PullFilterState`. The web keeps it in the URL; here it lives in the store
/// for as long as the window does.
nonisolated struct PullFilterState: Equatable, Sendable {
  var query = ""
  var repo = PullFilterGroup()
  var author = PullFilterGroup()
  var state: [PullState] = []

  static let empty = PullFilterState()

  /// `hasPullFilters`.
  var isActive: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !repo.values.isEmpty
      || !author.values.isEmpty || !state.isEmpty
  }
}

/// A removable badge under the filter bar (`ActiveFilter`).
nonisolated struct PullActiveFilter: Identifiable, Equatable {
  enum Kind: Hashable {
    case query
    case repo
    case author
    case state(PullState)
  }

  let id: Kind
  let label: String
}

/// One option of the repo or author dropdown, with how many distinct PRs carry it.
nonisolated struct PullFilterOption: Equatable, Sendable, Identifiable {
  let value: String
  let count: Int
  var id: String { value }
}

/// Filtering logic of `lib/pullFilters.ts`.
nonisolated enum PullFiltering {
  /// `hasPullState`.
  static func has(_ item: PullRequestItem, _ state: PullState, now: Date) -> Bool {
    switch state {
    case .ciFailing: item.ci == .failing
    case .changesRequested: item.review == .changesRequested
    case .approved: item.review == .approved
    case .conflict: item.merge == .conflict
    case .draft: item.draft
    case .awaitingYou: item.awaitingYou
    case .stale: PullAge.isStale(updatedAt: item.updatedAt, now: now)
    }
  }

  /// Within a dimension the values add up (OR); across dimensions all must
  /// hold (AND), the same cut as the Jira panel (`matchesPullFilters`).
  static func matches(_ item: PullRequestItem, _ filters: PullFilterState, now: Date) -> Bool {
    guard filters.repo.matches(item.repo), filters.author.matches(item.author) else { return false }
    if !filters.state.isEmpty, !filters.state.contains(where: { has(item, $0, now: now) }) { return false }
    let fields = [item.title, "\(item.repo)#\(item.number)", item.author] + (item.jira ?? []).map(\.key)
    return matchesQuery(fields, filters.query)
  }

  /// Accent- and case-insensitive on both sides, so "revisao" finds "Revisão"
  /// (`matchesQuery`, `lib/filters.ts:15-19`).
  static func matchesQuery(_ fields: [String], _ query: String) -> Bool {
    let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !term.isEmpty else { return true }
    return fields.contains { normalize($0).contains(term) }
  }

  static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
  }

  /// The same PR shows in more than one list (tracked and review requested);
  /// the count is of distinct PRs (`pullFilterOptions`).
  static func options(_ items: [PullRequestItem]) -> (repos: [PullFilterOption], authors: [PullFilterOption]) {
    var seen = Set<String>()
    var repos: [String: Int] = [:]
    var authors: [String: Int] = [:]
    for item in items {
      let key = "\(item.repo.lowercased())#\(item.number)"
      guard seen.insert(key).inserted else { continue }
      repos[item.repo, default: 0] += 1
      if !item.author.isEmpty { authors[item.author, default: 0] += 1 }
    }
    func sorted(_ counts: [String: Int]) -> [PullFilterOption] {
      counts.map { PullFilterOption(value: $0.key, count: $0.value) }
        .sorted { $0.value.localizedCompare($1.value) == .orderedAscending }
    }
    return (sorted(repos), sorted(authors))
  }

  /// The badges under the bar, in the web's order.
  static func activeFilters(_ filters: PullFilterState) -> [PullActiveFilter] {
    var out: [PullActiveFilter] = []
    let term = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !term.isEmpty { out.append(PullActiveFilter(id: .query, label: "Busca: \(term)")) }
    if !filters.repo.values.isEmpty {
      out.append(PullActiveFilter(id: .repo, label: filters.repo.label("Repositório")))
    }
    if !filters.author.values.isEmpty {
      out.append(PullActiveFilter(id: .author, label: filters.author.label("Autor")))
    }
    out += filters.state.map { PullActiveFilter(id: .state($0), label: $0.label) }
    return out
  }
}
