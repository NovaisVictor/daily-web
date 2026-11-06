import CoreGraphics
import DailyModels
import Testing

@testable import FeatureHome

/// Trellis' `sortTabAtPointer`: the tab follows the pointer in its strip and
/// the siblings pack around the slot it would land in.
@Suite struct TabStripSortTests {
  /// The resolver tests' layout: group "a" with email (4–84), tasks (86–166)
  /// and notes (168–248), 2pt apart; group "b" with agenda beside it.
  let resolver = TabDropResolver(zones: [TabDropResolverTests.zoneA, TabDropResolverTests.zoneB])
  /// Email taken 16pt from its left edge.
  static let start = CGPoint(x: 20, y: 15)

  /// One pointer position while email is dragged: the landing index and each
  /// tab's offset from its laid-out slot.
  nonisolated struct Row: Sendable, CustomTestStringConvertible {
    var pointerX: CGFloat
    var index: Int
    var email: CGFloat
    var tasks: CGFloat
    var notes: CGFloat

    var testDescription: String { "pointer at \(pointerX)" }
  }

  nonisolated static let rows: [Row] = [
    // Left of tasks' midpoint: no sibling moves; the tab stops at the strip's start.
    Row(pointerX: 5, index: 0, email: -4, tasks: 0, notes: 0),
    // Past tasks' midpoint (126): tasks slides into email's slot.
    Row(pointerX: 150, index: 1, email: 130, tasks: -82, notes: 0),
    // Past notes' midpoint (208): both siblings slide left.
    Row(pointerX: 300, index: 2, email: 280, tasks: -82, notes: -82),
    // Near the strip's end: the tab is held inside the 400pt strip.
    Row(pointerX: 390, index: 2, email: 316, tasks: -82, notes: -82),
  ]

  @Test(arguments: rows)
  func siblingsSlideAroundTheLandingSlot(row: Row) throws {
    let point = CGPoint(x: row.pointerX, y: 15)
    let sort = try #require(resolver.sort(dragging: .email, at: point, from: Self.start, spacing: 2))
    #expect(sort.groupID == "a")
    #expect(sort.index == row.index)
    #expect(sort.offset(of: .email) == row.email)
    #expect(sort.offset(of: .tasks) == row.tasks)
    #expect(sort.offset(of: .notes) == row.notes)
  }

  @Test func theLandingIndexIsTheDropTargets() throws {
    let point = CGPoint(x: 150, y: 15)
    let sort = try #require(resolver.sort(dragging: .email, at: point, from: Self.start, spacing: 2))
    #expect(resolver.target(at: point, dragging: .email) == .strip(groupID: "a", index: sort.index))
  }

  @Test func outsideTheOwnStripThereIsNoSort() {
    // Below the strip, in the group's body.
    #expect(resolver.sort(dragging: .email, at: CGPoint(x: 150, y: 100), from: Self.start, spacing: 2) == nil)
    // Over another group's strip: a move, drawn with the ghost.
    #expect(resolver.sort(dragging: .email, at: CGPoint(x: 450, y: 15), from: Self.start, spacing: 2) == nil)
    // Agenda over group "a"'s strip is not in its own strip either.
    #expect(resolver.sort(dragging: .agenda, at: CGPoint(x: 150, y: 15), from: Self.start, spacing: 2) == nil)
  }

  @Test func anUnmeasuredTabFallsBackToTheGhost() {
    let zone = TabDropResolver.Zone(
      groupID: "c",
      frame: CGRect(x: 0, y: 0, width: 400, height: 300),
      strip: CGRect(x: 0, y: 0, width: 400, height: 34),
      tabs: [
        TabDropResolver.Tab(view: .jira, frame: CGRect(x: 4, y: 4, width: 80, height: 30)),
        TabDropResolver.Tab(view: .pulls, frame: nil),
      ]
    )
    let sort = TabDropResolver(zones: [zone])
      .sort(dragging: .jira, at: CGPoint(x: 150, y: 15), from: Self.start, spacing: 2)
    #expect(sort == nil)
  }

  @Test func aTabWiderThanTheStripStaysAtItsStart() throws {
    let zone = TabDropResolver.Zone(
      groupID: "c",
      frame: CGRect(x: 0, y: 0, width: 60, height: 300),
      strip: CGRect(x: 0, y: 0, width: 60, height: 34),
      tabs: [TabDropResolver.Tab(view: .jira, frame: CGRect(x: 4, y: 4, width: 80, height: 30))]
    )
    let sort = try #require(
      TabDropResolver(zones: [zone]).sort(dragging: .jira, at: CGPoint(x: 50, y: 15), from: Self.start, spacing: 2))
    #expect(sort.offset(of: .jira) == -4)
  }
}

/// The alignment haptic fires when the drag lands on a new target.
@Suite struct TabDropLandingTests {
  nonisolated struct Row: Sendable, CustomTestStringConvertible {
    var old: TabDropTarget?
    var new: TabDropTarget?
    var lands: Bool

    var testDescription: String { "\(String(describing: old)) → \(String(describing: new))" }
  }

  nonisolated static let rows: [Row] = [
    Row(old: nil, new: .strip(groupID: "a", index: 0), lands: true),
    Row(old: .strip(groupID: "a", index: 0), new: .strip(groupID: "a", index: 0), lands: false),
    Row(old: .strip(groupID: "a", index: 0), new: .strip(groupID: "a", index: 1), lands: true),
    Row(old: .group(groupID: "a"), new: .edge(groupID: "a", edge: .left), lands: true),
    Row(old: .edge(groupID: "a", edge: .left), new: .edge(groupID: "a", edge: .top), lands: true),
    Row(old: .strip(groupID: "a", index: 0), new: nil, lands: false),
    Row(old: nil, new: nil, lands: false),
  ]

  @Test(arguments: rows)
  func landsOnlyOnANewTarget(row: Row) {
    #expect(TabDropTarget.isNewLanding(from: row.old, to: row.new) == row.lands)
  }
}
