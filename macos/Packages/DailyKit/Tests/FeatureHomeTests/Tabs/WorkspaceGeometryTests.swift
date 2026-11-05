import CoreGraphics
import DailyModels
import Testing

@testable import FeatureHome

@Suite struct WorkspaceGeometryTests {
  func expectClose(
    _ actual: CGRect, _ expected: CGRect, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let values: [(CGFloat, CGFloat)] = [
      (actual.minX, expected.minX), (actual.minY, expected.minY),
      (actual.width, expected.width), (actual.height, expected.height),
    ]
    for (lhs, rhs) in values {
      #expect(abs(lhs - rhs) < 1e-6, "\(actual) != \(expected)", sourceLocation: sourceLocation)
    }
  }

  static func divider(length: CGFloat, before: CGFloat = 200, after: CGFloat = 200) -> WorkspaceGeometry.Divider {
    WorkspaceGeometry.Divider(
      splitID: "split", boundary: 0, axis: .x, frame: .zero, length: length,
      minimumBefore: before, minimumAfter: after)
  }

  // MARK: - Placement

  @Test func twoGroupsShareTheRowThreeToTwoAroundTheGap() throws {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let geometry = WorkspaceGeometry(root: layout.root, size: CGSize(width: 1006, height: 600))
    #expect(geometry.groups.count == 2)
    let left = try #require(geometry.groups.first)
    let right = try #require(geometry.groups.last)
    expectClose(left.frame, CGRect(x: 0, y: 0, width: 600, height: 600))
    expectClose(right.frame, CGRect(x: 606, y: 0, width: 400, height: 600))
    expectClose(left.strip, CGRect(x: 0, y: 0, width: 600, height: 34))
    expectClose(left.content, CGRect(x: 0, y: 34, width: 600, height: 566))
  }

  @Test func theDividerIsCentredOnTheGapAndWiderThanIt() throws {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let geometry = WorkspaceGeometry(root: layout.root, size: CGSize(width: 1006, height: 600))
    let divider = try #require(geometry.dividers.first)
    #expect(geometry.dividers.count == 1)
    #expect(divider.axis == .x)
    #expect(divider.boundary == 0)
    #expect(divider.length == 1000)
    expectClose(divider.frame, CGRect(x: 599, y: 0, width: 8, height: 600))
  }

  @Test func theDefaultLaysEveryModuleOutInColumns() {
    let layout = WorkspaceLayout.makeDefault(modules: ModuleID.known)
    let geometry = WorkspaceGeometry(root: layout.root, size: CGSize(width: 1006, height: 800))
    #expect(geometry.groups.map(\.id) == layout.groups.map(\.id))
    // One divider between the columns, three in the left column, two in the right.
    #expect(geometry.dividers.count == 6)
    let leftColumn = geometry.groups.prefix(4)
    let widths: [CGFloat] = leftColumn.map { $0.frame.width }
    #expect(widths.allSatisfy { abs($0 - 600) < 1e-6 })
    let totalHeight: CGFloat = leftColumn.map { $0.frame.height }.reduce(0, +)
    let expectedHeight: CGFloat = 800 - 3 * 6
    #expect(abs(totalHeight - expectedHeight) < 1e-6)
  }

  @Test func anEmptyLayoutHasNothing() {
    let geometry = WorkspaceGeometry(root: nil, size: CGSize(width: 800, height: 600))
    #expect(geometry.groups.isEmpty)
    #expect(geometry.dividers.isEmpty)
  }

  @Test func minimumLengthAddsAlongTheAxisAndTakesTheLargestAcrossIt() throws {
    let layout = WorkspaceLayout.makeDefault(modules: ModuleID.known)
    let geometry = WorkspaceGeometry(root: nil, size: .zero)
    guard case .split(let row) = try #require(layout.root) else {
      Issue.record("root is not a split")
      return
    }
    // The left column stacks four groups.
    let columnHeight: CGFloat = 4 * 140 + 3 * 6
    let columnWidth: CGFloat = 200
    let rowWidth: CGFloat = 2 * 200 + 6
    #expect(abs(geometry.minimumLength(of: row.children[0], along: .y) - columnHeight) < 1e-6)
    #expect(abs(geometry.minimumLength(of: row.children[0], along: .x) - columnWidth) < 1e-6)
    #expect(abs(geometry.minimumLength(of: .split(row), along: .x) - rowWidth) < 1e-6)
  }

  // MARK: - Resizing

  @Test func resizeDeltaIsTheTranslationAsAShareOfTheSplit() {
    let divider = Self.divider(length: 1000)
    let delta = WorkspaceGeometry.resizeDelta(translation: 100, divider: divider, weights: [0.6, 0.4])
    #expect(abs(delta - 0.1) < 1e-9)
  }

  @Test func resizeDeltaStopsAtEachSidesMinimum() {
    let divider = Self.divider(length: 1000)
    let grow = WorkspaceGeometry.resizeDelta(translation: 500, divider: divider, weights: [0.6, 0.4])
    let shrink = WorkspaceGeometry.resizeDelta(translation: -900, divider: divider, weights: [0.6, 0.4])
    #expect(abs(grow - 0.2) < 1e-9)
    #expect(abs(shrink - -0.4) < 1e-9)
  }

  @Test func aSideAlreadyBelowItsMinimumIsNotShrunkNorForcedToGrow() {
    let divider = Self.divider(length: 1000)
    #expect(WorkspaceGeometry.resizeDelta(translation: -50, divider: divider, weights: [0.1, 0.9]) == 0)
    let grow = WorkspaceGeometry.resizeDelta(translation: 50, divider: divider, weights: [0.1, 0.9])
    #expect(abs(grow - 0.05) < 1e-9)
  }

  @Test func resizeDeltaOfAnEmptySplitIsZero() {
    #expect(WorkspaceGeometry.resizeDelta(translation: 40, divider: Self.divider(length: 0), weights: [0.5, 0.5]) == 0)
    #expect(WorkspaceGeometry.resizeDelta(translation: 40, divider: Self.divider(length: 1000), weights: [1]) == 0)
  }

  @Test func equalizingMakesBothSidesTheSame() {
    let delta = WorkspaceGeometry.equalizingDelta(divider: Self.divider(length: 1000), weights: [0.6, 0.4])
    #expect(abs(delta - -0.1) < 1e-9)
  }

  @Test func resizingThroughTheLayoutKeepsTheTotal() throws {
    let layout = WorkspaceLayout.makeDefault(modules: [.email, .tasks])
    let geometry = WorkspaceGeometry(root: layout.root, size: CGSize(width: 1006, height: 600))
    let divider = try #require(geometry.dividers.first)
    let split = try #require(layout.split(id: divider.splitID))
    let delta = WorkspaceGeometry.resizeDelta(translation: -100, divider: divider, weights: split.weights)
    let next = layout.resizing(split: divider.splitID, boundary: divider.boundary, by: delta)
    let weights = try #require(next.split(id: divider.splitID)).weights
    #expect(abs(weights[0] - 0.5) < 1e-9)
    #expect(abs(weights.reduce(0, +) - 1) < 1e-9)
  }

  // MARK: - Keyboard

  @Test func cyclingWrapsAtBothEnds() {
    let group = WorkspaceGroup(id: "g", views: [.email, .tasks, .notes], selected: .email)
    #expect(group.cycled(by: 1) == .tasks)
    #expect(group.cycled(by: -1) == .notes)
    #expect(group.cycled(by: 4) == .tasks)
    #expect(WorkspaceGroup(id: "g", views: [.jira], selected: .jira).cycled(by: 1) == .jira)
  }
}
