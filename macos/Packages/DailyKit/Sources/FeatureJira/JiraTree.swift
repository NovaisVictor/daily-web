import DailyModels
import Foundation

/// Why an issue is in the tree: it matches the tab's slice, or it only links
/// what matches to the top of the hierarchy (`JiraNodeOrigin`, `lib/parsers/jira.ts`).
nonisolated enum JiraNodeOrigin: Sendable {
  case match
  case ancestor
}

nonisolated struct JiraNode: Equatable, Identifiable, Sendable {
  var issue: JiraItem
  var origin: JiraNodeOrigin
  var children: [JiraNode]

  var id: String { issue.key }

  var hasMatch: Bool { origin == .match || children.contains { $0.hasMatch } }

  var matchCount: Int { (origin == .match ? 1 : 0) + children.reduce(0) { $0 + $1.matchCount } }

  /// A branch made only of ancestors shows nothing; it led to an issue the
  /// tab's slice left out.
  func pruned() -> JiraNode {
    var copy = self
    copy.children = children.filter(\.hasMatch).map { $0.pruned() }
    return copy
  }
}

nonisolated struct JiraProjectGroup: Equatable, Identifiable, Sendable {
  var project: String
  var roots: [JiraNode]
  var count: Int

  var id: String { project }
}

/// A situation bucket of the flat list (`groupByStatusCategory`).
nonisolated struct JiraStatusGroup: Equatable, Identifiable, Sendable {
  var category: JiraStatusCategory
  var label: String
  var issues: [JiraItem]

  var id: String { category.rawValue }
}

nonisolated enum JiraTree {
  /// `buildJiraTree`, `lib/parsers/jira.ts:96-128`. Each issue becomes a node
  /// under its parent and the result is split by project. `ancestors` enter
  /// as path, never as part of the slice; an item wins over an ancestor of the
  /// same key, keeping the ancestor's position (a `Map.set` on a known key).
  static func build(_ items: [JiraItem], ancestors: [JiraItem] = []) -> [JiraProjectGroup] {
    var order: [String] = []
    var entries: [String: (issue: JiraItem, origin: JiraNodeOrigin)] = [:]
    for issue in ancestors {
      if entries[issue.key] == nil { order.append(issue.key) }
      entries[issue.key] = (issue, .ancestor)
    }
    for issue in items {
      if entries[issue.key] == nil { order.append(issue.key) }
      entries[issue.key] = (issue, .match)
    }

    var childrenOf: [String: [String]] = [:]
    var rootKeys: [String] = []
    for key in order {
      guard let entry = entries[key] else { continue }
      if let parentKey = entry.issue.parent?.key, parentKey != key, entries[parentKey] != nil {
        childrenOf[parentKey, default: []].append(key)
      } else {
        rootKeys.append(key)
      }
    }

    // A parent pointing back is never reached from a root, so the recursion
    // ends; `visiting` guards the climb anyway.
    func node(_ key: String, visiting: Set<String>) -> JiraNode? {
      guard let entry = entries[key], !visiting.contains(key) else { return nil }
      let next = visiting.union([key])
      let children = (childrenOf[key] ?? []).compactMap { node($0, visiting: next) }
      return JiraNode(issue: entry.issue, origin: entry.origin, children: children)
    }

    var projectOrder: [String] = []
    var groups: [String: [JiraNode]] = [:]
    for key in rootKeys {
      guard let root = node(key, visiting: []), root.hasMatch else { continue }
      let project = root.issue.project
      if groups[project] == nil { projectOrder.append(project) }
      groups[project, default: []].append(root.pruned())
    }
    let built = projectOrder.map { project in
      let roots = groups[project] ?? []
      return JiraProjectGroup(project: project, roots: roots, count: roots.reduce(0) { $0 + $1.matchCount })
    }
    return JiraSorting.stable(built) { JiraText.localeLess($0.project, $1.project) }
  }

  /// `groupByStatusCategory`: what was started comes before what was not.
  static func byStatusCategory(_ items: [JiraItem]) -> [JiraStatusGroup] {
    let categories: [(JiraStatusCategory, String)] = [
      (.indeterminate, "Em andamento"), (.new, "Pendentes"), (.done, "Concluídas"),
    ]
    return categories.compactMap { category, label in
      let issues = items.filter { $0.statusCategory == category }
      return issues.isEmpty ? nil : JiraStatusGroup(category: category, label: label, issues: issues)
    }
  }
}

/// How the list is ordered (`lib/jiraOrder.ts`). The default keeps Jira's own
/// order, latest change first.
nonisolated enum JiraOrder: String, CaseIterable, Sendable {
  case updated = "atualizacao"
  case due = "prazo"
  case priority = "prioridade"
  case stale = "parado"

  static let `default` = JiraOrder.updated

  var label: String {
    switch self {
    case .updated: "Atualização"
    case .due: "Prazo"
    case .priority: "Prioridade"
    case .stale: "Parado há mais tempo"
    }
  }

  /// `parseJiraOrder`.
  static func parse(_ value: String?) -> JiraOrder {
    value.flatMap(JiraOrder.init(rawValue:)) ?? .default
  }

  private static func time(_ iso: String) -> Double? {
    JiraDates.parse(iso).map { $0.timeIntervalSince1970 * 1000 }
  }

  /// Missing goes last on every criterion.
  private static func ascending(_ lhs: Double?, _ rhs: Double?) -> Int {
    switch (lhs, rhs) {
    case (nil, nil): 0
    case (nil, _): 1
    case (_, nil): -1
    case (let lhs?, let rhs?): lhs < rhs ? -1 : (lhs > rhs ? 1 : 0)
    }
  }

  private static func recentFirst(_ lhs: JiraItem, _ rhs: JiraItem) -> Int {
    ascending(time(lhs.updatedAt).map { -$0 }, time(rhs.updatedAt).map { -$0 })
  }

  /// `compareJira`.
  func compare(_ lhs: JiraItem, _ rhs: JiraItem) -> Int {
    switch self {
    case .due:
      let byDue = Self.ascending(Self.time(lhs.dueDate), Self.time(rhs.dueDate))
      return byDue != 0 ? byDue : Self.recentFirst(lhs, rhs)
    case .priority:
      let byRank = Self.ascending(
        lhs.priority?.rank.map(Double.init), rhs.priority?.rank.map(Double.init))
      return byRank != 0 ? byRank : Self.recentFirst(lhs, rhs)
    case .stale:
      return Self.ascending(Self.time(lhs.updatedAt), Self.time(rhs.updatedAt))
    case .updated:
      return Self.recentFirst(lhs, rhs)
    }
  }

  /// `sortJira`: the default order returns the list as Jira sent it.
  func sort(_ items: [JiraItem]) -> [JiraItem] {
    self == .default ? items : JiraSorting.stable(items, compare: compare)
  }

  /// `sortJira` for wrappers of an item (problems, dated items).
  func sort<T>(_ items: [T], item: (T) -> JiraItem) -> [T] {
    self == .default ? items : JiraSorting.stable(items) { compare(item($0), item($1)) }
  }

  /// `sortJiraTree`: a branch is worth its most urgent issue.
  func sortTree(_ groups: [JiraProjectGroup]) -> [JiraProjectGroup] {
    guard self != .default else { return groups }

    func byBest(_ lhs: JiraItem?, _ rhs: JiraItem?) -> Int {
      switch (lhs, rhs) {
      case (let lhs?, let rhs?): compare(lhs, rhs)
      case (.some, nil): -1
      case (nil, .some): 1
      case (nil, nil): 0
      }
    }

    func sortNode(_ node: JiraNode) -> (node: JiraNode, best: JiraItem?) {
      let children = JiraSorting.stable(node.children.map(sortNode)) { byBest($0.best, $1.best) }
      let candidates = (node.origin == .match ? [node.issue] : []) + children.compactMap(\.best)
      let best = JiraSorting.stable(candidates, compare: compare).first
      var sorted = node
      sorted.children = children.map(\.node)
      return (sorted, best)
    }

    return groups.map { group in
      var copy = group
      copy.roots = JiraSorting.stable(group.roots.map(sortNode)) { byBest($0.best, $1.best) }.map(\.node)
      return copy
    }
  }
}
