import DailyModels
import Foundation

/// The three tiers the panel lets one pick (`lib/jiraFilters.ts:7-25`).
nonisolated enum JiraTier: String, CaseIterable, Sendable {
  case initiative
  case epic
  case story

  var label: String {
    switch self {
    case .initiative: "Iniciativas"
    case .epic: "Épicos"
    case .story: "Histórias"
    }
  }

  var level: Int {
    switch self {
    case .initiative: 2
    case .epic: 1
    case .story: 0
    }
  }

  /// `tierOf`: read from the hierarchy level, not the type's name.
  static func of(_ item: JiraItem) -> JiraTier? {
    allCases.first { $0.level == item.hierarchyLevel }
  }
}

nonisolated enum JiraFilterMode: String, Sendable {
  case include
  case exclude
}

/// One selector's choice: values and include/exclude. Tier values are
/// `JiraTier` raw values, so every group has the same shape, as in the web's
/// field-indexed helpers.
nonisolated struct JiraFilterGroup: Equatable, Sendable {
  var values: [String] = []
  var mode: JiraFilterMode = .include

  init(_ values: [String] = [], mode: JiraFilterMode = .include) {
    self.values = values
    self.mode = mode
  }

  /// `passes`: an empty group lets everything through.
  func passes(_ matched: Bool) -> Bool {
    values.isEmpty || matched == (mode == .include)
  }
}

/// The selectors, in the order they appear (`JIRA_FILTER_FIELDS`).
nonisolated enum JiraFilterField: String, CaseIterable, Sendable {
  case status
  case tier
  case initiative
  case epic
  case story

  var label: String {
    switch self {
    case .status: "Status"
    case .tier: "Tipo"
    case .initiative: "Iniciativa"
    case .epic: "Épico"
    case .story: "História"
    }
  }

  /// `BELOW`: picking an upper tier narrows the options of the ones under it.
  var below: [JiraFilterField] {
    switch self {
    case .initiative: [.epic, .story]
    case .epic: [.story]
    default: []
    }
  }
}

/// The panel's slice (`JiraFilterState`). Empty is "no filter"; the three
/// hierarchy groups add up.
nonisolated struct JiraFilterState: Equatable, Sendable {
  var query = ""
  var status = JiraFilterGroup()
  var tier = JiraFilterGroup()
  var initiative = JiraFilterGroup()
  var epic = JiraFilterGroup()
  var story = JiraFilterGroup()

  static let empty = JiraFilterState()

  subscript(field: JiraFilterField) -> JiraFilterGroup {
    get {
      switch field {
      case .status: status
      case .tier: tier
      case .initiative: initiative
      case .epic: epic
      case .story: story
      }
    }
    set {
      switch field {
      case .status: status = newValue
      case .tier: tier = newValue
      case .initiative: initiative = newValue
      case .epic: epic = newValue
      case .story: story = newValue
      }
    }
  }

  /// `hasJiraFilters`.
  var isActive: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || JiraFilterField.allCases.contains { !self[$0].values.isEmpty }
  }

  /// `clearJiraFilter`: removing an upper tier frees the ones below it.
  mutating func clear(_ field: JiraFilterField) {
    self[field] = JiraFilterGroup()
    for below in field.below { self[below] = JiraFilterGroup() }
  }

  /// `changeJiraFilter`: when nothing chosen before survives, the tier changed
  /// subject and the ones below are freed; adding a value or switching the
  /// mode keeps them.
  mutating func change(_ field: JiraFilterField, to next: JiraFilterGroup) {
    let previous = self[field].values
    let switched = !previous.isEmpty && !previous.contains { next.values.contains($0) }
    self[field] = next
    if switched {
      for below in field.below { self[below] = JiraFilterGroup() }
    }
  }
}

/// A filter shown as a removable badge (`ActiveFilter`, `lib/filters.ts`).
struct JiraActiveFilter: Identifiable, Equatable {
  enum Kind: Hashable {
    case query
    case field(JiraFilterField)
    case role
  }

  let id: Kind
  let label: String
}

nonisolated enum JiraFilters {
  /// Ceiling of the climb: the hierarchy has five tiers; the limit keeps a
  /// parent that points back from becoming a loop (`MAX_LINEAGE`).
  static let maxLineage = 8

  /// `lineageOf`: the known ancestors, from the parent up.
  static func lineage(of item: JiraItem, in byKey: [String: JiraItem]) -> [JiraItem] {
    var lineage: [JiraItem] = []
    var seen: Set<String> = [item.key]
    var parentKey = item.parent?.key
    while let key = parentKey, !seen.contains(key), lineage.count < maxLineage {
      guard let parent = byKey[key] else { break }
      lineage.append(parent)
      seen.insert(key)
      parentKey = parent.parent?.key
    }
    return lineage
  }

  private static func underAny(_ item: JiraItem, _ lineage: [JiraItem], _ keys: [String]) -> Bool {
    keys.contains { key in item.key == key || lineage.contains { $0.key == key } }
  }

  private static func sameStatus(_ lhs: String, _ rhs: String) -> Bool {
    lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// `matchesJiraFilters`.
  static func matches(_ item: JiraItem, _ filters: JiraFilterState, byKey: [String: JiraItem]) -> Bool {
    guard filters.status.passes(filters.status.values.contains { sameStatus(item.status, $0) }) else { return false }
    let tier = JiraTier.of(item)
    guard filters.tier.passes(tier.map { filters.tier.values.contains($0.rawValue) } ?? false) else { return false }

    let lineage = lineage(of: item, in: byKey)
    for field in [JiraFilterField.initiative, .epic, .story] {
      let group = filters[field]
      guard group.passes(underAny(item, lineage, group.values)) else { return false }
    }
    // The search looks at the whole path: searching for the initiative's
    // name brings what sits under it.
    let fields = ([item] + lineage).flatMap { [$0.key, $0.summary] }
    return JiraText.matches(fields, query: filters.query)
  }

  struct Options: Equatable {
    var statuses: [String]
    var initiatives: [JiraItem]
    var epics: [JiraItem]
    var stories: [JiraItem]
  }

  /// `jiraFilterOptions`: what each selector offers for the tab's list. The
  /// hierarchy ones cascade, and an option with nothing of the list under it
  /// does not show.
  static func options(_ items: [JiraItem], byKey: [String: JiraItem], filters: JiraFilterState) -> Options {
    var statusOrder: [String] = []
    var statuses: [String: String] = [:]
    var poolOrder: [String] = []
    var pool: [String: (item: JiraItem, lineage: [JiraItem])] = [:]

    for item in items {
      let trimmed = item.status.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = trimmed.lowercased()
      if !normalized.isEmpty, statuses[normalized] == nil {
        statuses[normalized] = trimmed
        statusOrder.append(normalized)
      }
      let lineage = lineage(of: item, in: byKey)
      for (index, node) in ([item] + lineage).enumerated() where pool[node.key] == nil {
        pool[node.key] = (node, Array(lineage.dropFirst(index)))
        poolOrder.append(node.key)
      }
    }

    let activeInitiatives = filters.initiative.mode == .include ? filters.initiative.values : []
    let activeEpics = filters.epic.mode == .include ? filters.epic.values : []

    func ofTier(_ tier: JiraTier, within initiatives: [String], _ epics: [String]) -> [JiraItem] {
      let matching = poolOrder.compactMap { pool[$0] }
        .filter { JiraTier.of($0.item) == tier }
        .filter { entry in
          (initiatives.isEmpty || underAny(entry.item, entry.lineage, initiatives))
            && (epics.isEmpty || underAny(entry.item, entry.lineage, epics))
        }
        .map(\.item)
      return JiraSorting.stable(matching) { JiraText.localeLess($0.summary, $1.summary) }
    }

    return Options(
      statuses: JiraSorting.stable(statusOrder.compactMap { statuses[$0] }, by: JiraText.localeLess),
      initiatives: ofTier(.initiative, within: [], []),
      epics: ofTier(.epic, within: activeInitiatives, []),
      stories: ofTier(.story, within: activeInitiatives, activeEpics)
    )
  }

  /// `activeJiraFilters`. `describeIssue` gives an issue key's label, which only
  /// the panel knows.
  static func active(_ filters: JiraFilterState, describeIssue: (String) -> String) -> [JiraActiveFilter] {
    var result: [JiraActiveFilter] = []
    let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty { result.append(JiraActiveFilter(id: .query, label: "Busca: \(query)")) }
    for field in JiraFilterField.allCases {
      let group = filters[field]
      guard !group.values.isEmpty else { continue }
      let separator = group.mode == .exclude ? " ≠ " : ": "
      let values = group.values.map { describe(field, $0, describeIssue) }.joined(separator: ", ")
      result.append(JiraActiveFilter(id: .field(field), label: "\(field.label)\(separator)\(values)"))
    }
    return result
  }

  private static func describe(_ field: JiraFilterField, _ value: String, _ issue: (String) -> String) -> String {
    switch field {
    case .status: value
    case .tier: JiraTier(rawValue: value)?.label ?? value
    default: issue(value)
    }
  }
}

nonisolated enum JiraSorting {
  /// `Array.prototype.sort` is stable; Swift's `sorted` does not promise it.
  static func stable<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
    items.enumerated()
      .sorted { lhs, rhs in
        if less(lhs.element, rhs.element) { return true }
        if less(rhs.element, lhs.element) { return false }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  /// A stable sort by a three-way comparator, as JavaScript's `sort(compare)`.
  static func stable<T>(_ items: [T], compare: (T, T) -> Int) -> [T] {
    stable(items) { compare($0, $1) < 0 }
  }
}
