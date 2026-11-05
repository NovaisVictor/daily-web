import DailyModels
import Foundation
import Testing

@testable import FeatureJira

/// `tests/lib/jiraOrder.test.ts`, plus the tree and the row labels of `lib/parsers/jira.ts`.
@Suite struct JiraOrderTreeTests {
  static let a = makeIssue(
    "A-1", updatedAt: "2026-10-01T10:00:00Z", due: "2026-10-30", priority: JiraPriority(name: "Baixa", rank: 3))
  static let b = makeIssue(
    "A-2", updatedAt: "2026-10-15T10:00:00Z", due: "", priority: JiraPriority(name: "Crítica", rank: 0))
  static let c = makeIssue("A-3", updatedAt: "2026-10-10T10:00:00Z", due: "2026-10-21")

  @Test func parseFallsBackToTheDefault() {
    #expect(JiraOrder.parse(nil) == .updated)
    #expect(JiraOrder.parse("toString") == .updated)
    #expect(JiraOrder.parse("lixo") == .updated)
    #expect(JiraOrder.parse("prioridade") == .priority)
  }

  @Test func defaultOrderKeepsJirasOrder() {
    #expect(JiraOrder.updated.sort([Self.c, Self.a, Self.b]).map(\.key) == ["A-3", "A-1", "A-2"])
  }

  @Test func byDueDateNoDueLast() {
    #expect(JiraOrder.due.sort([Self.a, Self.b, Self.c]).map(\.key) == ["A-3", "A-1", "A-2"])
  }

  @Test func byPriorityHighestFirstNoneLast() {
    #expect(JiraOrder.priority.sort([Self.a, Self.b, Self.c]).map(\.key) == ["A-2", "A-1", "A-3"])
  }

  @Test func staleIsOldestChangeFirst() {
    #expect(JiraOrder.stale.sort([Self.a, Self.b, Self.c]).map(\.key) == ["A-1", "A-3", "A-2"])
  }

  @Test func tiesBreakByLatestChange() {
    let x = makeIssue("A-4", updatedAt: "2026-10-01T10:00:00Z", priority: JiraPriority(name: "Alta", rank: 1))
    let y = makeIssue("A-5", updatedAt: "2026-10-09T10:00:00Z", priority: JiraPriority(name: "Alta", rank: 1))
    #expect(JiraOrder.priority.sort([x, y]).map(\.key) == ["A-5", "A-4"])
  }

  @Test func anInvalidDateCountsAsMissing() {
    let bad = makeIssue("A-9", due: "sem data")
    #expect(JiraOrder.due.compare(bad, Self.c) > 0)
  }

  @Test func treeRaisesTheBranchWithTheHighestPriority() {
    let epicA = makeIssue("A-10", kind: "Epic", level: 1)
    let epicB = makeIssue("A-20", kind: "Epic", level: 1)
    let low = makeIssue("A-11", parent: "A-10", priority: JiraPriority(name: "Baixa", rank: 3))
    let critical = makeIssue("A-21", parent: "A-20", priority: JiraPriority(name: "Crítica", rank: 0))

    let tree = JiraTree.build([low, critical], ancestors: [epicA, epicB])
    #expect(tree[0].roots.map(\.issue.key) == ["A-10", "A-20"])

    let sorted = JiraOrder.priority.sortTree(tree)
    #expect(sorted[0].roots.map(\.issue.key) == ["A-20", "A-10"])
    #expect(sorted[0].count == 2)
  }

  @Test func treeSortsChildrenInsideTheBranch() {
    let epic = makeIssue("A-10", kind: "Epic", level: 1)
    let late = makeIssue("A-11", parent: "A-10", due: "2026-12-01")
    let early = makeIssue("A-12", parent: "A-10", due: "2026-10-25")
    let group = JiraOrder.due.sortTree(JiraTree.build([late, early], ancestors: [epic]))[0]
    #expect(group.roots[0].children.map(\.issue.key) == ["A-12", "A-11"])
  }

  // MARK: buildJiraTree

  @Test func treePrunesAncestorOnlyBranchesAndSplitsByProject() {
    let epic = makeIssue("B-1", kind: "Epic", level: 1)
    let lonelyEpic = makeIssue("B-2", kind: "Epic", level: 1)
    let story = makeIssue("B-11", parent: "B-1")
    let other = makeIssue("A-5")
    let tree = JiraTree.build([story, other], ancestors: [epic, lonelyEpic])
    #expect(tree.map(\.project) == ["A", "B"])
    #expect(tree[1].roots.map(\.issue.key) == ["B-1"])
    #expect(tree[1].roots[0].origin == .ancestor)
    #expect(tree[1].roots[0].children.map(\.issue.key) == ["B-11"])
    #expect(tree[1].count == 1)
  }

  @Test func anItemWinsOverTheAncestorOfTheSameKey() {
    let epicAsAncestor = makeIssue("B-1", kind: "Epic", level: 1)
    let epicMine = makeIssue("B-1", summary: "meu", kind: "Epic", level: 1)
    let tree = JiraTree.build([epicMine], ancestors: [epicAsAncestor])
    #expect(tree[0].roots[0].origin == .match)
    #expect(tree[0].roots[0].issue.summary == "meu")
  }

  @Test func visibleRowsWalkOpenBranchesDepthFirst() {
    let epic = makeIssue("B-1", kind: "Epic", level: 1)
    let story = makeIssue("B-11", parent: "B-1")
    let task = makeIssue("B-111", parent: "B-11")
    let sibling = makeIssue("B-12", parent: "B-1")
    let roots = JiraTree.build([epic, story, task, sibling])[0].roots

    let all = JiraTree.visibleRows(roots) { _ in true }
    #expect(all.map(\.id) == ["B-1", "B-11", "B-111", "B-12"])
    #expect(all.map(\.depth) == [0, 1, 2, 1])

    let closedStory = JiraTree.visibleRows(roots) { $0.issue.key != "B-11" }
    #expect(closedStory.map(\.id) == ["B-1", "B-11", "B-12"])
    #expect(JiraTree.visibleRows(roots) { _ in false }.map(\.id) == ["B-1"])
  }

  @Test func groupsBySituationInWorkOrder() {
    let groups = JiraTree.byStatusCategory([
      makeIssue("A-1", category: .done), makeIssue("A-2", category: .new), makeIssue("A-3"),
    ])
    #expect(groups.map(\.label) == ["Em andamento", "Pendentes", "Concluídas"])
  }

  // MARK: Labels

  @Test func markers() {
    #expect(JiraText.issueMarker(makeIssue("A-1", kind: "Story")) == "[S]")
    #expect(JiraText.issueMarker(makeIssue("A-1", kind: " Épico ")) == "[E]")
    #expect(JiraText.issueMarker(makeIssue("A-1", kind: "Subtarefa", subtask: true)) == "[s]")
    #expect(JiraText.issueMarker(makeIssue("A-1", kind: "Bug")) == "[?]")
  }

  @Test func normalizedStatus() {
    #expect(JiraText.normalizeStatus("  Em Andamento ") == "Em andamento")
    #expect(JiraText.normalizeStatus("") == "")
  }

  @Test func dueLabels() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15)) ?? .now
    #expect(JiraText.dueLabel("2026-09-20", now: now, calendar: calendar) == "venceu há 2d")
    #expect(JiraText.dueLabel("2026-09-22", now: now, calendar: calendar) == "vence hoje")
    #expect(JiraText.dueLabel("2026-09-23", now: now, calendar: calendar) == "vence amanhã")
    #expect(JiraText.dueLabel("2026-09-25", now: now, calendar: calendar) == "vence em 3d")
    #expect(JiraText.dueLabel("2026-09-30", now: now, calendar: calendar) == "vence 30/09")
    #expect(JiraText.dueLabel("", now: now, calendar: calendar) == nil)
    #expect(JiraText.isOverdue("2026-09-21", now: now, calendar: calendar))
    #expect(!JiraText.isOverdue("2026-09-22", now: now, calendar: calendar))
  }

  @Test func staleness() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let fresh = makeIssue("A-1", updatedAt: JiraText.isoForTest(now.addingTimeInterval(-4.9 * 86_400)))
    let old = makeIssue("A-2", updatedAt: JiraText.isoForTest(now.addingTimeInterval(-6.5 * 86_400)))
    #expect(JiraText.stalenessLabel(fresh, now: now) == nil)
    #expect(JiraText.stalenessLabel(old, now: now) == "parado há 6d")
  }
}

extension JiraText {
  static func isoForTest(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
