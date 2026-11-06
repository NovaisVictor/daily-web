import CoreGraphics
import DailyModels
import Testing

@testable import FeatureHome

private typealias Engine = DashboardLayoutEngine

/// 12 columns of 56 pt with 24 pt gaps: a column step of 80 pt, a row step of 56 pt.
private let width: CGFloat = 12 * 56 + 11 * 24

private let start = Engine.synchronize(Engine.defaultLayout())

private func placement(_ module: ModuleID, in layout: [PanelPlacement]) -> PanelPlacement? {
  layout.first { $0.i == module }
}

/// Splits a table row into numbers; "-" stands for nil.
private func numbers(_ row: String) -> [Double?] {
  row.split(separator: " ").map { $0 == "-" ? nil : Double($0) }
}

/// The four numbers every row has: the input pair and the expected pair.
private func required(_ values: [Double?]) throws -> (a: Double, b: Double, c: Int, d: Int) {
  try #require(values.count == 6)
  let a = try #require(values[0])
  let b = try #require(values[1])
  let c = try #require(values[4])
  let d = try #require(values[5])
  return (a, b, Int(c), Int(d))
}

@Suite struct GridHysteresisTests {
  /// originX originY previousX previousY → x y, for a panel 5 columns wide.
  nonisolated static let cellRows = [
    "0 0 - - 0 0",
    "39 0 - - 0 0",
    "40 0 - - 1 0",
    "40 0 0 0 0 0",
    "47 0 0 0 0 0",
    "49 0 0 0 1 0",
    "33 0 1 0 1 0",
    "31 0 1 0 0 0",
    "200 0 1 0 3 0",
    "590 0 7 0 7 0",
    "5000 0 7 0 7 0",
    "-300 -300 - - 0 0",
    "0 28 0 0 0 0",
    "0 34 0 0 0 1",
  ]

  @Test(arguments: cellRows)
  func cellsHoldUntilCarriedPastTheBand(_ row: String) throws {
    let values = numbers(row)
    let parsed = try required(values)
    let previous = values[2].flatMap { x in values[3].map { GridCell(x: Int(x), y: Int($0)) } }
    let origin = CGPoint(x: parsed.a, y: parsed.b)
    let expected = GridCell(x: parsed.c, y: parsed.d)
    #expect(Engine.cell(for: origin, w: 5, containerWidth: width, previous: previous) == expected, "\(row)")
  }

  /// width height previousW previousH → w h, for a panel at column 0.
  nonisolated static let spanRows = [
    "376 360 - - 5 7",
    "416 360 5 7 5 7",
    "432 360 5 7 6 7",
    "376 345 5 7 5 7",
    "100 100 - - 3 4",
    "5000 10000 - - 12 80",
  ]

  @Test(arguments: spanRows)
  func spansHoldTooAndKeepThePanelLimits(_ row: String) throws {
    let values = numbers(row)
    let parsed = try required(values)
    let previous = values[2].flatMap { w in values[3].map { GridSpan(w: Int(w), h: Int($0)) } }
    let size = CGSize(width: parsed.a, height: parsed.b)
    let expected = GridSpan(w: parsed.c, h: parsed.d)
    #expect(Engine.span(for: size, x: 0, containerWidth: width, previous: previous) == expected, "\(row)")
  }

  @Test func aDegenerateWidthDoesNotTrap() {
    let cell = Engine.cell(for: CGPoint(x: CGFloat.infinity, y: CGFloat.nan), w: 5, containerWidth: 0, previous: nil)
    #expect(cell == GridCell(x: 0, y: 0))
  }
}

@Suite struct GridPreviewTests {
  @Test func previewOnTheStartCellIsTheStart() throws {
    let agenda = try #require(placement(.agenda, in: start))
    #expect(Engine.dragPreview(startLayout: start, id: .agenda, cell: GridCell(x: agenda.x, y: agenda.y)) == start)
    #expect(Engine.resizePreview(startLayout: start, id: .agenda, size: GridSpan(w: agenda.w, h: agenda.h)) == start)
  }

  /// Every preview comes from the start, so the path the pointer took does
  /// not matter and coming back undoes everything.
  @Test func theTrackerPreviewDependsOnlyOnThePointer() throws {
    var tracker = GridGestureTracker()
    let press = CGPoint(x: 600, y: 20)
    func drag(_ dx: CGFloat) -> GridGestureTracker.Outcome {
      tracker.update(
        module: .agenda, kind: .move, startLocation: press, translation: CGSize(width: dx, height: 0),
        layout: start, containerWidth: width)
    }
    #expect(drag(0) == .followed)
    let session = try #require(tracker.session)
    #expect(session.startPlacement == placement(.agenda, in: start))
    #expect(session.startFrame.origin == CGPoint(x: 560, y: 0))
    #expect(session.preview == start)

    #expect(drag(-560) == .changed)
    let atZero = Engine.dragPreview(startLayout: start, id: .agenda, cell: GridCell(x: 0, y: 0))
    #expect(tracker.session?.preview == atZero)
    #expect(drag(-555) == .followed, "the same cell")
    #expect(drag(-240) == .changed)
    #expect(drag(-560) == .changed)
    #expect(tracker.session?.preview == atZero, "the same cell gives the same layout")
    #expect(drag(0) == .changed)
    #expect(tracker.session?.preview == start, "back on the start cell, back to the start")
    let unchanged = tracker.end()
    #expect(unchanged == nil, "nothing changed")
    #expect(tracker.session == nil)
  }

  @Test func aResizeFollowsTheCorner() {
    var tracker = GridGestureTracker()
    let outcome = tracker.update(
      module: .email, kind: .resize, startLocation: CGPoint(x: 530, y: 750), translation: CGSize(width: 80, height: 56),
      layout: start, containerWidth: width)
    #expect(outcome == .changed)
    #expect(
      tracker.session?.preview == Engine.resizePreview(startLayout: start, id: .email, size: GridSpan(w: 8, h: 15)))
    let resized = tracker.end()
    #expect(resized == Engine.resizePreview(startLayout: start, id: .email, size: GridSpan(w: 8, h: 15)))
  }

  @Test func aCancelledGestureStaysCancelledUntilReleased() {
    var tracker = GridGestureTracker()
    let press = CGPoint(x: 600, y: 20)
    func drag() -> GridGestureTracker.Outcome {
      tracker.update(
        module: .agenda, kind: .move, startLocation: press, translation: CGSize(width: -560, height: 0),
        layout: start, containerWidth: width)
    }
    #expect(drag() == .changed)
    let cancelled = tracker.cancel()
    #expect(cancelled)
    #expect(tracker.session == nil)
    let cancelledAgain = tracker.cancel()
    #expect(!cancelledAgain, "nothing left to cancel")
    #expect(drag() == .ignored, "the pointer is still down")
    let ended = tracker.end()
    #expect(ended == nil)
    #expect(drag() == .changed, "released: the next press is a new gesture")
  }

  @Test func aPanelTheGridDoesNotDrawIsIgnored() {
    var tracker = GridGestureTracker()
    let layout = start.filter { $0.i != .slack }
    let outcome = tracker.update(
      module: .slack, kind: .move, startLocation: .zero, translation: CGSize(width: 10, height: 10),
      layout: layout, containerWidth: width)
    #expect(outcome == .ignored)
    #expect(tracker.session == nil)
  }

  @Test func theGridKeepsItsHeightWhileAGestureLasts() {
    #expect(GridDashboardLayout.size([], proposedWidth: 1200, minimumHeight: 500).height == 500)
    let full = GridDashboardLayout.size(start, proposedWidth: 1200, minimumHeight: 500).height
    #expect(full == Engine.contentHeight(start))
  }

  @Test func theResizedPanelStaysWithinItsLimits() {
    let follow = GridFollow(
      kind: .resize, startSize: CGSize(width: 300, height: 300), minimumSize: CGSize(width: 200, height: 200),
      maximumSize: CGSize(width: 400, height: 1000))
    #expect(follow.size(for: CGSize(width: 50, height: 50)) == CGSize(width: 350, height: 350))
    #expect(follow.size(for: CGSize(width: -500, height: -500)) == CGSize(width: 200, height: 200))
    #expect(follow.size(for: CGSize(width: 500, height: 900)) == CGSize(width: 400, height: 1000))
  }
}

@Suite struct GridKeyboardTests {
  @Test func tabFollowsReadingOrderAndWraps() {
    #expect(GridKeyboard.next(after: nil, in: start, backwards: false) == .email)
    #expect(GridKeyboard.next(after: .email, in: start, backwards: false) == .agenda)
    #expect(GridKeyboard.next(after: .slack, in: start, backwards: false) == .email)
    #expect(GridKeyboard.next(after: .email, in: start, backwards: true) == .slack)
    #expect(GridKeyboard.next(after: .email, in: [], backwards: false) == nil)
  }

  @Test func arrowsNudgeOneStep() {
    let left = Engine.nudge(start, id: .agenda, dx: -1, dy: 0)
    #expect(placement(.agenda, in: left)?.x == 6)
    #expect(Engine.nudge(start, id: .email, dx: -1, dy: 0) == start, "already on the first column")
    #expect(Engine.nudge(start, id: .slack, dx: 0, dy: 1) == start, "nothing under it to pass")
    #expect(Engine.nudge(start, id: .agenda, dx: 0, dy: 0) == start)
  }
}

@Suite struct GridMotionTests {
  @Test func theJiggleIsExactlyStillOutsideTheMode() {
    #expect(GridJiggle.angle(arranging: false, active: false, reduceMotion: false) == 0)
    #expect(GridJiggle.angle(arranging: true, active: false, reduceMotion: false) == GridJiggle.amplitude)
    #expect(GridJiggle.angle(arranging: true, active: true, reduceMotion: false) == 0, "paused during a gesture")
    #expect(GridJiggle.angle(arranging: true, active: false, reduceMotion: true) == 0)
  }

  @Test func theHoldBadgeCountsDownInTenths() {
    #expect(GridHold.badgeText(elapsed: 0) == "Segure para organizar · 0,5 s")
    #expect(GridHold.badgeText(elapsed: 0.1) == "Segure para organizar · 0,4 s")
    #expect(GridHold.badgeText(elapsed: 0.7) == "Segure para organizar · 0,0 s")
  }
}
