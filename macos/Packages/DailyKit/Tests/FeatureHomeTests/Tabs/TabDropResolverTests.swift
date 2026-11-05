import CoreGraphics
import DailyModels
import Testing

@testable import FeatureHome

@Suite struct TabDropResolverTests {
  /// Group "a": three tabs in a 400×300 group; group "b": one tab beside it.
  static let zoneA = TabDropResolver.Zone(
    groupID: "a",
    frame: CGRect(x: 0, y: 0, width: 400, height: 300),
    strip: CGRect(x: 0, y: 0, width: 400, height: 34),
    tabs: [
      TabDropResolver.Tab(view: .email, frame: CGRect(x: 4, y: 4, width: 80, height: 30)),
      TabDropResolver.Tab(view: .tasks, frame: CGRect(x: 86, y: 4, width: 80, height: 30)),
      TabDropResolver.Tab(view: .notes, frame: CGRect(x: 168, y: 4, width: 80, height: 30)),
    ]
  )
  static let zoneB = TabDropResolver.Zone(
    groupID: "b",
    frame: CGRect(x: 406, y: 0, width: 300, height: 300),
    strip: CGRect(x: 406, y: 0, width: 300, height: 34),
    tabs: [TabDropResolver.Tab(view: .agenda, frame: CGRect(x: 410, y: 4, width: 80, height: 30))]
  )
  let resolver = TabDropResolver(zones: [Self.zoneA, Self.zoneB])

  // MARK: - Strip

  @Test func stripInsertsBeforeTheFirstTabWhoseMidpointIsRightOfThePointer() {
    #expect(resolver.target(at: CGPoint(x: 20, y: 15), dragging: .agenda) == .strip(groupID: "a", index: 0))
    #expect(resolver.target(at: CGPoint(x: 100, y: 15), dragging: .agenda) == .strip(groupID: "a", index: 1))
    #expect(resolver.target(at: CGPoint(x: 200, y: 15), dragging: .agenda) == .strip(groupID: "a", index: 2))
  }

  @Test func stripPastTheLastTabAppends() {
    #expect(resolver.target(at: CGPoint(x: 300, y: 15), dragging: .agenda) == .strip(groupID: "a", index: 3))
  }

  @Test func stripOfTheOwnGroupCountsWithoutTheDraggedTab() {
    // Without email the tabs are [tasks, notes]: 150 is left of notes' midpoint (208).
    #expect(resolver.target(at: CGPoint(x: 150, y: 15), dragging: .email) == .strip(groupID: "a", index: 1))
    #expect(resolver.target(at: CGPoint(x: 300, y: 15), dragging: .email) == .strip(groupID: "a", index: 2))
  }

  @Test func stripWinsOverTheTopEdge() {
    #expect(resolver.target(at: CGPoint(x: 300, y: 2), dragging: .agenda) == .strip(groupID: "a", index: 3))
  }

  @Test func stripWithUnmeasuredTabsAppends() {
    let zone = TabDropResolver.Zone(
      groupID: "c",
      frame: CGRect(x: 0, y: 0, width: 400, height: 300),
      strip: CGRect(x: 0, y: 0, width: 400, height: 34),
      tabs: [TabDropResolver.Tab(view: .jira, frame: nil), TabDropResolver.Tab(view: .pulls, frame: nil)]
    )
    let target = TabDropResolver(zones: [zone]).target(at: CGPoint(x: 10, y: 10), dragging: .slack)
    #expect(target == .strip(groupID: "c", index: 2))
  }

  // MARK: - Edges and middle

  @Test func pointsNearAnEdgeSplitTheGroupOnThatSide() {
    #expect(resolver.target(at: CGPoint(x: 20, y: 150), dragging: .agenda) == .edge(groupID: "a", edge: .left))
    #expect(resolver.target(at: CGPoint(x: 380, y: 150), dragging: .agenda) == .edge(groupID: "a", edge: .right))
    #expect(resolver.target(at: CGPoint(x: 200, y: 60), dragging: .agenda) == .edge(groupID: "a", edge: .top))
    #expect(resolver.target(at: CGPoint(x: 200, y: 290), dragging: .agenda) == .edge(groupID: "a", edge: .bottom))
  }

  @Test func theMiddleOfAGroupJoinsIt() {
    #expect(resolver.target(at: CGPoint(x: 200, y: 150), dragging: .agenda) == .group(groupID: "a"))
    #expect(resolver.target(at: CGPoint(x: 556, y: 150), dragging: .email) == .group(groupID: "b"))
  }

  @Test func theEdgeBandIsTwentyEightPercent() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(TabDropResolver.edge(at: CGPoint(x: 27, y: 50), in: rect) == .left)
    #expect(TabDropResolver.edge(at: CGPoint(x: 30, y: 50), in: rect) == nil)
    #expect(TabDropResolver.edge(at: CGPoint(x: 50, y: 71), in: rect) == nil)
    #expect(TabDropResolver.edge(at: CGPoint(x: 50, y: 73), in: rect) == .bottom)
  }

  @Test func equalDistancesPreferLeftThenRightThenTopThenBottom() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(TabDropResolver.edge(at: CGPoint(x: 0, y: 0), in: rect) == .left)
    #expect(TabDropResolver.edge(at: CGPoint(x: 100, y: 100), in: rect) == .right)
    #expect(TabDropResolver.edge(at: CGPoint(x: 50, y: 0), in: rect) == .top)
  }

  @Test func outsideEveryGroupIsNothing() {
    // The gap between the two groups.
    #expect(resolver.target(at: CGPoint(x: 403, y: 150), dragging: .agenda) == nil)
    #expect(resolver.target(at: CGPoint(x: 1000, y: 1000), dragging: .agenda) == nil)
    #expect(TabDropResolver.edge(at: CGPoint(x: -1, y: 50), in: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
  }

  // MARK: - No-op drops

  @Test func theOnlyTabOnItsOwnGroupsEdgeIsNothing() {
    #expect(resolver.target(at: CGPoint(x: 420, y: 150), dragging: .agenda) == nil)
  }

  @Test func theMiddleOfTheOwnGroupIsNothing() {
    #expect(resolver.target(at: CGPoint(x: 556, y: 150), dragging: .agenda) == nil)
    #expect(resolver.target(at: CGPoint(x: 200, y: 150), dragging: .email) == nil)
  }

  @Test func aTabOfAGroupWithOthersCanSplitItsOwnGroup() {
    #expect(resolver.target(at: CGPoint(x: 20, y: 150), dragging: .email) == .edge(groupID: "a", edge: .left))
  }

  // MARK: - Indicators

  @Test func stripIndicatorIsABarBeforeTheTargetTab() {
    let bar = resolver.indicator(for: .strip(groupID: "a", index: 1), dragging: .agenda)
    #expect(bar == CGRect(x: 84, y: 6, width: 2, height: 22))
  }

  @Test func stripIndicatorPastTheLastTabFollowsIt() {
    let bar = resolver.indicator(for: .strip(groupID: "a", index: 3), dragging: .agenda)
    #expect(bar == CGRect(x: 248, y: 6, width: 2, height: 22))
  }

  @Test func edgeIndicatorIsTheHalfTheNewGroupTakes() {
    #expect(
      resolver.indicator(for: .edge(groupID: "a", edge: .right), dragging: .agenda)
        == CGRect(x: 200, y: 0, width: 200, height: 300))
    #expect(
      resolver.indicator(for: .edge(groupID: "a", edge: .bottom), dragging: .agenda)
        == CGRect(x: 0, y: 150, width: 400, height: 150))
    #expect(
      resolver.indicator(for: .edge(groupID: "a", edge: .left), dragging: .agenda)
        == CGRect(x: 0, y: 0, width: 200, height: 300))
    #expect(
      resolver.indicator(for: .edge(groupID: "a", edge: .top), dragging: .agenda)
        == CGRect(x: 0, y: 0, width: 400, height: 150))
  }

  @Test func groupIndicatorIsTheWholeGroup() {
    #expect(resolver.indicator(for: .group(groupID: "b"), dragging: .email) == Self.zoneB.frame)
    #expect(resolver.indicator(for: .group(groupID: "missing"), dragging: .email) == nil)
  }

  // MARK: - Applying

  @Test func droppingOnAStripMovesTheTabThere() throws {
    let layout = WorkspaceLayout.makeDefault(modules: ModuleID.known)
    let jiraGroup = try #require(layout.group(containing: .jira)).id
    let next = TabDropResolver.apply(.strip(groupID: jiraGroup, index: 0), moving: .email, to: layout)
    let group = try #require(next.group(containing: .email))
    #expect(group.id == jiraGroup)
    #expect(group.views == [.email, .jira])
    #expect(group.selected == .email)
  }

  @Test func droppingOnTheMiddleAppendsTheTab() throws {
    let layout = WorkspaceLayout.makeDefault(modules: ModuleID.known)
    let jiraGroup = try #require(layout.group(containing: .jira)).id
    let next = TabDropResolver.apply(.group(groupID: jiraGroup), moving: .email, to: layout)
    #expect(try #require(next.group(id: jiraGroup)).views == [.jira, .email])
  }

  @Test func droppingOnAnEdgeGivesTheTabItsOwnGroup() throws {
    let start = WorkspaceLayout.makeDefault(modules: ModuleID.known)
    let jiraGroup = try #require(start.group(containing: .jira)).id
    let joined = TabDropResolver.apply(.strip(groupID: jiraGroup, index: 0), moving: .email, to: start)
    let next = TabDropResolver.apply(.edge(groupID: jiraGroup, edge: .left), moving: .email, to: joined)
    #expect(try #require(next.group(containing: .email)).views == [.email])
    #expect(try #require(next.group(containing: .jira)).views == [.jira])
    #expect(next.views.count == ModuleID.known.count)
  }

  @Test func zonesFollowTheLaidOutGroupsAndTheMeasuredTabs() {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let geometry = WorkspaceGeometry(root: layout.root, size: CGSize(width: 1006, height: 600))
    let frame = CGRect(x: 4, y: 4, width: 80, height: 30)
    let resolver = TabDropResolver(geometry: geometry, layout: layout, tabFrames: [.email: frame])
    #expect(resolver.zones.map(\.groupID) == layout.groups.map(\.id))
    #expect(resolver.zones.first?.tabs == [TabDropResolver.Tab(view: .email, frame: frame)])
    #expect(resolver.zones.last?.tabs == [TabDropResolver.Tab(view: .tasks, frame: nil)])
  }
}
