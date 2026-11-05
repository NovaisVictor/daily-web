import DailyModels
import Foundation
import Testing

@testable import FeatureHome

@Suite struct WorkspaceLayoutTests {
  static let all = ModuleID.known

  /// The groups' tabs, in tree order.
  func tabs(_ layout: WorkspaceLayout) -> [[ModuleID]] {
    layout.groups.map(\.views)
  }

  func groupID(_ layout: WorkspaceLayout, _ view: ModuleID) throws -> String {
    try #require(layout.group(containing: view)).id
  }

  /// Every invariant the view relies on.
  func expectValid(_ layout: WorkspaceLayout, sourceLocation: SourceLocation = #_sourceLocation) {
    func check(_ node: WorkspaceNode, parentAxis: WorkspaceAxis?) {
      switch node {
      case .group(let group):
        #expect(!group.views.isEmpty, sourceLocation: sourceLocation)
        #expect(group.views.contains(group.selected), sourceLocation: sourceLocation)
      case .split(let split):
        #expect(split.children.count >= 2, sourceLocation: sourceLocation)
        #expect(split.children.count == split.weights.count, sourceLocation: sourceLocation)
        #expect(abs(split.weights.reduce(0, +) - 1) < 1e-9, sourceLocation: sourceLocation)
        #expect(split.axis != parentAxis, sourceLocation: sourceLocation)
        for child in split.children { check(child, parentAxis: split.axis) }
      }
    }
    if let root = layout.root { check(root, parentAxis: nil) }
    #expect(Set(layout.views).count == layout.views.count, sourceLocation: sourceLocation)
  }

  // MARK: - Default

  @Test func defaultIsARowOfTwoColumnsSizedThreeToTwo() throws {
    let layout = WorkspaceLayout.makeDefault(modules: Self.all)
    guard case .split(let row) = try #require(layout.root) else {
      Issue.record("root is not a split")
      return
    }
    #expect(row.axis == .x)
    #expect(row.weights == [0.6, 0.4])
    #expect(tabs(layout) == [[.email], [.tasks], [.notes], [.agenda], [.jira], [.pulls], [.slack]])
    guard case .split(let left) = row.children[0], case .split(let right) = row.children[1] else {
      Issue.record("columns are not splits")
      return
    }
    #expect(left.axis == .y && right.axis == .y)
    #expect(left.children.count == 4)
    #expect(right.children.count == 3)
    expectValid(layout)
  }

  @Test func defaultFollowsTheWebOrderWhateverTheInputOrder() {
    let layout = WorkspaceLayout.makeDefault(modules: [.slack, .jira, .email])
    #expect(tabs(layout) == [[.email], [.jira], [.slack]])
    expectValid(layout)
  }

  @Test func defaultWithTwoModulesIsTwoGroupsSideBySide() throws {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    guard case .split(let row) = try #require(layout.root) else {
      Issue.record("root is not a split")
      return
    }
    #expect(row.axis == .x)
    #expect(row.weights == [0.6, 0.4])
    #expect(tabs(layout) == [[.email], [.tasks]])
  }

  @Test func defaultWithOneModuleIsOneGroup() {
    let layout = WorkspaceLayout.makeDefault(modules: [.jira])
    #expect(layout.root == .group(WorkspaceGroup(id: "panel-1", views: [.jira], selected: .jira)))
  }

  @Test func defaultWithoutModulesIsEmpty() {
    #expect(WorkspaceLayout.makeDefault(modules: []).root == nil)
    #expect(WorkspaceLayout.makeDefault(modules: [ModuleID(rawValue: "novo")]).root == nil)
  }

  @Test func defaultIdsAreUnique() {
    let layout = WorkspaceLayout.makeDefault(modules: Self.all)
    var ids: [String] = []
    func collect(_ node: WorkspaceNode) {
      ids.append(node.id)
      if case .split(let split) = node { split.children.forEach(collect) }
    }
    if let root = layout.root { collect(root) }
    #expect(Set(ids).count == ids.count)
  }

  // MARK: - Selecting

  @Test func selectingMakesTheTabActive() throws {
    var layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    layout = layout.moving(.tasks, to: try groupID(layout, .email))
    #expect(layout.group(containing: .email)?.selected == .tasks)
    let selected = layout.selecting(.email)
    #expect(selected.group(containing: .email)?.selected == .email)
    #expect(selected.selecting(.email) == selected)
    #expect(layout.selecting(.slack) == layout)
  }

  // MARK: - Moving tabs

  @Test func movingATabIntoAnotherGroupAppendsAndSelectsIt() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    let moved = start.moving(.slack, to: try groupID(start, .email))
    #expect(moved.group(containing: .email)?.views == [.email, .slack])
    #expect(moved.group(containing: .email)?.selected == .slack)
    // Slack's group emptied and went away.
    #expect(moved.groups.count == 6)
    expectValid(moved)
  }

  @Test func movingATabAtAnIndexInsertsThere() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    let target = try groupID(layout, .email)
    layout = layout.moving(.tasks, to: target)
    layout = layout.moving(.notes, to: target, at: 1)
    #expect(layout.group(id: target)?.views == [.email, .notes, .tasks])
    layout = layout.moving(.slack, to: target, at: 99)
    #expect(layout.group(id: target)?.views == [.email, .notes, .tasks, .slack])
    layout = layout.moving(.agenda, to: target, at: -4)
    #expect(layout.group(id: target)?.views.first == .agenda)
    expectValid(layout)
  }

  @Test func movingWithinTheSameGroupReorders() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    let target = try groupID(layout, .email)
    layout = layout.moving(.tasks, to: target).moving(.notes, to: target)
    let reordered = layout.moving(.notes, to: target, at: 0)
    #expect(reordered.group(id: target)?.views == [.notes, .email, .tasks])
    #expect(reordered.group(id: target)?.selected == .notes)
    #expect(reordered.groups.count == layout.groups.count)
  }

  @Test func movingTheActiveTabOutSelectsItsNeighbour() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    let left = try groupID(layout, .email)
    layout = layout.moving(.tasks, to: left).moving(.notes, to: left).selecting(.tasks)
    let moved = layout.moving(.tasks, to: try groupID(layout, .slack))
    #expect(moved.group(id: left)?.views == [.email, .notes])
    #expect(moved.group(id: left)?.selected == .notes)
  }

  @Test func emptyingAColumnCollapsesTheSplit() throws {
    // Two modules: [email] | [tasks]. Moving tasks into email leaves one group.
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let moved = start.moving(.tasks, to: try groupID(start, .email))
    guard case .group(let group) = try #require(moved.root) else {
      Issue.record("the split did not collapse")
      return
    }
    #expect(group.views == [.email, .tasks])
  }

  @Test func movingToAnUnknownGroupOrViewChangesNothing() {
    let layout = WorkspaceLayout.makeDefault(modules: Self.all)
    #expect(layout.moving(.email, to: "panel-999") == layout)
    #expect(layout.moving(ModuleID(rawValue: "novo"), to: "panel-1") == layout)
  }

  // MARK: - Splitting

  @Test func droppingOnTheRightEdgeSplitsTheGroupSideBySide() throws {
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks, .notes])
    // [email, tasks] | notes after moving tasks into email's group.
    let grouped = start.moving(.tasks, to: try groupID(start, .email))
    let target = try groupID(grouped, .email)
    let split = grouped.splitting(target, with: .tasks, edge: .right)
    #expect(tabs(split) == [[.email], [.tasks], [.notes]])
    guard case .split(let row) = try #require(split.root) else {
      Issue.record("root is not a split")
      return
    }
    // The new split shares the row's axis, so it merges into the row:
    // email and tasks halve email's 0.6.
    #expect(row.axis == .x)
    #expect(row.children.count == 3)
    #expect(zip(row.weights, [0.3, 0.3, 0.4]).allSatisfy { abs($0 - $1) < 1e-9 })
    expectValid(split)
  }

  @Test func droppingOnTheTopEdgeStacksTheNewGroupFirst() throws {
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let target = try groupID(start, .email)
    let split = start.splitting(target, with: .tasks, edge: .top, share: 0.25)
    guard case .group(let top) = try #require(split.root.flatMap(Self.firstSplit)?.children.first) else {
      Issue.record("no stacked group")
      return
    }
    #expect(top.views == [.tasks])
    let column = try #require(split.root.flatMap(Self.firstSplit))
    #expect(column.axis == .y)
    #expect(zip(column.weights, [0.25, 0.75]).allSatisfy { abs($0 - $1) < 1e-9 })
    expectValid(split)
  }

  static func firstSplit(_ node: WorkspaceNode) -> WorkspaceSplit? {
    guard case .split(let split) = node else { return nil }
    return split
  }

  @Test func everyEdgeKeepsTheTreeValid() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    for edge in WorkspaceEdge.allCases {
      for view in Self.all {
        for target in start.groups {
          let result = start.splitting(target.id, with: view, edge: edge)
          expectValid(result)
          #expect(Set(result.views) == Set(Self.all))
        }
      }
    }
  }

  @Test func shareIsClamped() throws {
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let target = try groupID(start, .email)
    let split = start.splitting(target, with: .tasks, edge: .bottom, share: 5)
    let column = try #require(split.root.flatMap(Self.firstSplit))
    #expect(zip(column.weights, [0.1, 0.9]).allSatisfy { abs($0 - $1) < 1e-9 })
  }

  @Test func droppingAGroupsOnlyTabOnItsOwnEdgeChangesNothing() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    #expect(start.splitting(try groupID(start, .email), with: .email, edge: .left) == start)
  }

  @Test func droppingAGroupsTabOnItsOwnEdgeSplitsIt() throws {
    var layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    layout = layout.moving(.tasks, to: try groupID(layout, .email))
    let target = try groupID(layout, .email)
    let split = layout.splitting(target, with: .tasks, edge: .left)
    #expect(tabs(split) == [[.tasks], [.email]])
    expectValid(split)
  }

  // MARK: - Resizing

  @Test func resizingTradesSpaceBetweenNeighbours() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    let row = try #require(start.root.flatMap(Self.firstSplit))
    let resized = start.resizing(split: row.id, boundary: 0, by: 0.1)
    let weights = try #require(resized.split(id: row.id)).weights
    #expect(abs(weights[0] - 0.7) < 1e-9)
    #expect(abs(weights[1] - 0.3) < 1e-9)
    expectValid(resized)
  }

  @Test func resizingStopsAtTheMinimumShare() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    let row = try #require(start.root.flatMap(Self.firstSplit))
    let wide = try #require(start.resizing(split: row.id, boundary: 0, by: 5).split(id: row.id)).weights
    #expect(abs(wide[0] - 0.9) < 1e-9 && abs(wide[1] - 0.1) < 1e-9)
    let narrow = try #require(start.resizing(split: row.id, boundary: 0, by: -5).split(id: row.id)).weights
    #expect(abs(narrow[0] - 0.1) < 1e-9 && abs(narrow[1] - 0.9) < 1e-9)
  }

  @Test func resizingLeavesTheOtherChildrenAlone() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    guard case .split(let row) = try #require(start.root), case .split(let left) = row.children[0] else {
      Issue.record("no left column")
      return
    }
    let resized = try #require(start.resizing(split: left.id, boundary: 1, by: 0.05).split(id: left.id)).weights
    #expect(abs(resized[0] - 0.25) < 1e-9 && abs(resized[3] - 0.25) < 1e-9)
    #expect(abs(resized[1] - 0.3) < 1e-9 && abs(resized[2] - 0.2) < 1e-9)
    #expect(abs(resized.reduce(0, +) - 1) < 1e-9)
  }

  @Test func resizingSomethingThatIsNotThereChangesNothing() throws {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    let row = try #require(start.root.flatMap(Self.firstSplit))
    #expect(start.resizing(split: "split-999", boundary: 0, by: 0.1) == start)
    #expect(start.resizing(split: row.id, boundary: 1, by: 0.1) == start)
    #expect(start.resizing(split: row.id, boundary: -1, by: 0.1) == start)
    #expect(start.resizing(split: row.id, boundary: 0, by: .nan) == start)
  }

  // MARK: - Enabled modules

  @Test func aModuleTurnedOnOpensInTheLastGroup() {
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks, .agenda])
    let reconciled = start.reconciled(with: [.email, .tasks, .agenda, .slack, .jira])
    #expect(tabs(reconciled) == [[.email], [.tasks], [.agenda, .jira, .slack]])
    // A new tab does not steal the focus, as `open(id, {focus: false})`.
    #expect(reconciled.group(containing: .slack)?.selected == .agenda)
    expectValid(reconciled)
  }

  @Test func aModuleTurnedOffDisappears() {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    let reconciled = start.reconciled(with: [.email, .slack])
    #expect(tabs(reconciled) == [[.email], [.slack]])
    expectValid(reconciled)
  }

  @Test func turningOffTheActiveTabSelectsAnother() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    let left = try groupID(layout, .email)
    layout = layout.moving(.tasks, to: left).moving(.notes, to: left).selecting(.tasks)
    let reconciled = layout.reconciled(with: Self.all.filter { $0 != .tasks })
    #expect(reconciled.group(id: left)?.views == [.email, .notes])
    #expect(reconciled.group(id: left)?.selected == .notes)
  }

  @Test func turningEverythingOffThenOnStartsFromTheDefault() {
    let empty = WorkspaceLayout.makeDefault(modules: Self.all).reconciled(with: [])
    #expect(empty.root == nil)
    let back = empty.reconciled(with: [.email, .tasks])
    #expect(tabs(back) == [[.email], [.tasks]])
  }

  @Test func reconcilingWithTheSameModulesChangesNothing() {
    let start = WorkspaceLayout.makeDefault(modules: Self.all)
    #expect(start.reconciled(with: Self.all.reversed()) == start)
  }

  @Test func reconcilingDropsDuplicatesAndUnknownModules() {
    let doubled = WorkspaceLayout(
      root: .split(
        WorkspaceSplit(
          id: "s", axis: .x, weights: [1, 1],
          children: [
            .group(WorkspaceGroup(id: "a", views: [.email, ModuleID(rawValue: "novo")], selected: .email)),
            .group(WorkspaceGroup(id: "b", views: [.email, .tasks], selected: .email)),
          ])),
      nextID: 1)
    let reconciled = doubled.reconciled(with: [.email, .tasks, ModuleID(rawValue: "novo")])
    #expect(tabs(reconciled) == [[.email], [.tasks]])
    #expect(reconciled.group(id: "b")?.selected == .tasks)
    expectValid(reconciled)
  }

  // MARK: - Normalizing

  @Test func normalizingRepairsAHandMadeTree() {
    var layout = WorkspaceLayout(
      root: .split(
        WorkspaceSplit(
          id: "row", axis: .x, weights: [2, .nan, -1],
          children: [
            .split(
              WorkspaceSplit(
                id: "inner", axis: .x, weights: [1, 3],
                children: [
                  .group(WorkspaceGroup(id: "a", views: [.email], selected: .slack)),
                  .group(WorkspaceGroup(id: "b", views: [.tasks], selected: .tasks)),
                ])),
            .group(WorkspaceGroup(id: "empty", views: [], selected: .email)),
            .split(
              WorkspaceSplit(
                id: "single", axis: .y, weights: [1],
                children: [.group(WorkspaceGroup(id: "c", views: [.jira], selected: .jira))])),
          ])),
      nextID: 1)
    layout.normalize()
    #expect(tabs(layout) == [[.email], [.tasks], [.jira]])
    #expect(layout.group(id: "a")?.selected == .email)
    guard case .split(let row) = layout.root else {
      Issue.record("root is not a split")
      return
    }
    #expect(row.children.map(\.id) == ["a", "b", "c"])
    let expected = [0.5, 1.5, 0.001].map { $0 / 2.001 }
    #expect(zip(row.weights, expected).allSatisfy { abs($0 - $1) < 1e-9 })
    expectValid(layout)
  }

  // MARK: - Persistence

  @Test func encodesTheTrellisShape() throws {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let json = try #require(JSONSerialization.jsonObject(with: layout.encoded()) as? [String: Any])
    #expect(json["schema"] as? Int == 1)
    #expect(json["version"] as? Int == WorkspaceLayout.currentVersion)
    let root = try #require(json["root"] as? [String: Any])
    #expect(root["kind"] as? String == "split")
    #expect(root["axis"] as? String == "x")
    let children = try #require(root["children"] as? [[String: Any]])
    #expect(children.first?["kind"] as? String == "panel")
    #expect(children.first?["views"] as? [String] == ["email"])
    #expect(children.first?["selected"] as? String == "email")
  }

  @Test func roundTripsThroughData() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    layout = layout.moving(.slack, to: try groupID(layout, .email))
    let restored = try WorkspaceLayout.decode(layout.encoded())
    #expect(restored == layout)
  }

  @Test func anotherVersionIsDiscarded() throws {
    var layout = WorkspaceLayout.makeDefault(modules: Self.all)
    layout.version = WorkspaceLayout.currentVersion + 1
    #expect(try WorkspaceLayout.decode(layout.encoded()) == nil)
    let otherSchema = Data(#"{"schema":2,"version":1,"root":null,"nextID":1}"#.utf8)
    #expect(try WorkspaceLayout.decode(otherSchema) == nil)
    let noVersion = Data(#"{"schema":1,"root":null,"nextID":1}"#.utf8)
    #expect(try WorkspaceLayout.decode(noVersion) == nil)
  }

  @Test func corruptDataThrows() {
    #expect(throws: (any Error).self) { try WorkspaceLayout.decode(Data("nada".utf8)) }
    let stage = Data(#"{"schema":1,"version":1,"root":{"kind":"stage","id":"s"},"nextID":1}"#.utf8)
    #expect(throws: (any Error).self) { try WorkspaceLayout.decode(stage) }
  }

  @Test func decodingNormalizes() throws {
    let data = Data(
      #"""
      {"schema":1,"version":1,"nextID":3,"root":{"kind":"split","id":"s","axis":"y","weights":[1],
      "children":[{"kind":"panel","id":"p","views":["jira"],"selected":"email"}]}}
      """#.utf8)
    let layout = try #require(try WorkspaceLayout.decode(data))
    #expect(layout.root == .group(WorkspaceGroup(id: "p", views: [.jira], selected: .jira)))
  }

  @Test func newIdsNeverRepeatAfterARestore() throws {
    let start = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let restored = try #require(try WorkspaceLayout.decode(start.encoded()))
    var layout = restored.moving(.tasks, to: try groupID(restored, .email))
    layout = layout.splitting(try groupID(layout, .email), with: .tasks, edge: .right)
    let ids = Set(start.groups.map(\.id))
    #expect(layout.group(containing: .tasks).map { !ids.contains($0.id) } == true)
  }
}
