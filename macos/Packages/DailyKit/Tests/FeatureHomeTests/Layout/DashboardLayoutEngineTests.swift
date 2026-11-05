import CoreGraphics
import DailyModels
import Testing

@testable import FeatureHome

private typealias Engine = DashboardLayoutEngine

private func item(_ i: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutItem {
  LayoutItem(i: i, x: x, y: y, w: w, h: h)
}

private func place(_ i: ModuleID, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> PanelPlacement {
  PanelPlacement(i: i, x: x, y: y, w: w, h: h)
}

private func hasOverlaps(_ layout: [PanelPlacement]) -> Bool {
  for (index, a) in layout.enumerated() {
    for b in layout[(index + 1)...]
    where a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h {
      return true
    }
  }
  return false
}

/// Ported from the web's `tests/lib/dashboardLayout.test.ts`, test by test.
@Suite struct DashboardLayoutWebTests {
  // MARK: defaultLayout

  @Test func defaultPlacesEveryPanelInsideTheGrid() {
    for p in Engine.defaultLayout() {
      #expect(p.x >= 0)
      #expect(p.x + p.w <= Engine.columns)
      #expect(p.w >= Engine.minimumWidth)
      #expect(p.h >= Engine.minimumHeight)
    }
  }

  @Test func defaultIsTheWebsPositions() {
    #expect(
      Engine.defaultLayout() == [
        place(.email, 0, 0, 7, 14), place(.tasks, 0, 14, 7, 12), place(.agenda, 7, 0, 5, 9),
        place(.jira, 7, 9, 5, 12), place(.pulls, 7, 21, 5, 5), place(.notes, 0, 26, 7, 10),
        place(.slack, 7, 26, 5, 10),
      ])
  }

  @Test func defaultIsACopy() {
    var a = Engine.defaultLayout()
    a[0].x = 99
    #expect(Engine.defaultLayout()[0].x != 99)
  }

  // MARK: parseLayout

  @Test func readsASavedLayout() {
    let parsed = Engine.parseLayout([item("email", 4, 2, 5, 10)])
    #expect(parsed.first { $0.i == .email } == place(.email, 4, 2, 5, 10))
  }

  @Test func fillsAMissingPanelWithItsDefault() {
    let parsed = Engine.parseLayout([item("email", 0, 0, 6, 10)])
    #expect(Set(parsed.map(\.i)) == Set(Engine.defaultLayout().map(\.i)))
    #expect(parsed.first { $0.i == .tasks } == place(.tasks, 0, 14, 7, 12))
  }

  @Test func ignoresAnUnknownPanel() {
    let parsed = Engine.parseLayout([item("inventado", 0, 0, 4, 5)])
    #expect(!parsed.contains { $0.i.rawValue == "inventado" })
    #expect(parsed == Engine.defaultLayout())
  }

  @Test func clampsAbsurdValuesIntoTheGrid() throws {
    let email = try #require(Engine.parseLayout([item("email", 999, -5, 999, 9999)]).first { $0.i == .email })
    #expect(email.w == Engine.columns)
    #expect(email.x == 0)
    #expect(email.y == 0)
    #expect(email.h <= 80)
  }

  @Test func respectsTheMinimumSize() throws {
    let email = try #require(Engine.parseLayout([item("email", 0, 0, 0, 0)]).first { $0.i == .email })
    #expect(email.w == Engine.minimumWidth)
    #expect(email.h == Engine.minimumHeight)
  }

  @Test func keepsThePanelInsideTheRightEdge() throws {
    let email = try #require(Engine.parseLayout([item("email", 10, 0, 6, 8)]).first { $0.i == .email })
    #expect(email.x + email.w <= Engine.columns)
  }

  /// The web's "sobrevive a lixo": what survives JSON decoding here is an
  /// empty list or items with unusable numbers.
  @Test func survivesGarbage() {
    let garbage: [[LayoutItem]] = [
      [], [item("email", .nan, 0, 6, 8)], [item("email", 0, .infinity, 6, 8)], [item("", 0, 0, 0, 0)],
    ]
    for bad in garbage {
      #expect(Engine.parseLayout(bad) == Engine.defaultLayout())
    }
  }

  // MARK: serializeLayout

  @Test func roundTripKeepsTheLayout() {
    let original = Engine.defaultLayout()
    #expect(Engine.parseLayout(Engine.serializeLayout(original)) == original)
  }

  @Test func serializeKeepsOnlyCleanPlacements() {
    let dirty = [place(.email, 20, -3, 1, 200)]
    // `sanitize` widens to 3 first, then clamps x into 0...12 - 3.
    #expect(Engine.serializeLayout(dirty) == [item("email", 9, 0, 3, 80)])
  }

  // MARK: layoutFor

  @Test func onlyEnabledModulesShow() {
    let visible = Engine.layoutFor(Engine.defaultLayout(), enabled: [.email, .jira])
    #expect(Set(visible.map(\.i)) == [.email, .jira])
  }

  @Test func nothingEnabledShowsNothing() {
    #expect(Engine.layoutFor(Engine.defaultLayout(), enabled: []).isEmpty)
  }

  // MARK: isDefaultLayout

  @Test func recognisesTheDefaultAndAChange() {
    #expect(Engine.isDefaultLayout(Engine.defaultLayout()))
    var changed = Engine.defaultLayout()
    changed[0].x = 5
    #expect(!Engine.isDefaultLayout(changed))
  }

  // MARK: nearestLayout

  static func sized(_ width: Int, _ height: Int, _ module: ModuleID) -> SizedLayout {
    SizedLayout(width: width, height: height, layout: [place(module, 0, 0, 6, 8)])
  }

  @Test func nearestIsNilWithoutSavedLayouts() {
    #expect(Engine.nearestLayout([], width: 1920, height: 1080) == nil)
  }

  @Test func nearestFindsTheExactSize() {
    let entries = [Self.sized(1920, 1080, .email), Self.sized(1512, 945, .jira)]
    #expect(Engine.nearestLayout(entries, width: 1512, height: 945)?.layout[0].i == .jira)
  }

  @Test func nearestPicksTheClosestWhenNothingMatches() {
    let entries = [Self.sized(1920, 1080, .email), Self.sized(1512, 945, .jira)]
    #expect(Engine.nearestLayout(entries, width: 1920, height: 1040)?.layout[0].i == .email)
    #expect(Engine.nearestLayout(entries, width: 1500, height: 900)?.layout[0].i == .jira)
  }

  @Test func nearestWeighsWidthAndHeight() {
    let entries = [Self.sized(1600, 400, .email), Self.sized(1500, 1000, .jira)]
    #expect(Engine.nearestLayout(entries, width: 1590, height: 990)?.layout[0].i == .jira)
  }

  @Test func nearestUsesTheOnlyOneEvenOnAVeryDifferentScreen() {
    let entries = [Self.sized(3440, 1440, .email)]
    #expect(Engine.nearestLayout(entries, width: 1280, height: 800)?.layout[0].i == .email)
  }

  @Test func nearestTieGoesToTheNewest() {
    let entries = [Self.sized(1000, 1000, .email), Self.sized(1000, 1000, .jira)]
    #expect(Engine.nearestLayout(entries, width: 900, height: 900)?.layout[0].i == .email)
  }

  // MARK: putSizedLayout

  static let disp = [place(.email, 0, 0, 6, 8)]
  static let dispJira = [place(.jira, 0, 0, 6, 8)]

  @Test func putSavesTheFirstSize() {
    let after = Engine.putSizedLayout([], width: 1920, height: 1080, layout: Self.disp)
    #expect(after.count == 1)
    #expect(after[0].width == 1920 && after[0].height == 1080)
  }

  @Test func putAtTheSameSizeReplaces() {
    let before = Engine.putSizedLayout([], width: 1920, height: 1080, layout: Self.disp)
    let after = Engine.putSizedLayout(before, width: 1920, height: 1080, layout: Self.dispJira)
    #expect(after.count == 1)
    #expect(after[0].layout[0].i == .jira)
  }

  @Test func putANewSizeKeepsTheOthers() {
    let before = Engine.putSizedLayout([], width: 1920, height: 1080, layout: Self.disp)
    let after = Engine.putSizedLayout(before, width: 1512, height: 945, layout: Self.dispJira)
    #expect(after.map(\.width) == [1512, 1920])
  }

  @Test func putRoundsTheSize() {
    let after = Engine.putSizedLayout([], width: 1919.6, height: 1079.2, layout: Self.disp)
    #expect(after[0].width == 1920 && after[0].height == 1079)
  }

  @Test func putDropsTheOldestPastTheCap() {
    var entries: [SizedLayout] = []
    for i in 0..<(Engine.maximumSizedLayouts + 5) {
      entries = Engine.putSizedLayout(entries, width: Double(1000 + i), height: 800, layout: Self.disp)
    }
    #expect(entries.count == Engine.maximumSizedLayouts)
    #expect(entries[0].width == 1000 + Engine.maximumSizedLayouts + 4)
    #expect(!entries.contains { $0.width == 1000 })
  }

  // MARK: parseSizedLayouts

  @Test func parseAcceptsWhatWasSaved() {
    let entries = Engine.putSizedLayout([], width: 1920, height: 1080, layout: Self.disp)
    #expect(Engine.parseSizedLayouts(entries.map(\.savedLayout)).count == 1)
  }

  @Test func parseDropsUnusableSizes() {
    let parsed = Engine.parseSizedLayouts([
      SavedLayout(width: 0, height: 100, layout: []),
      SavedLayout(width: -5, height: 100, layout: []),
      SavedLayout(width: .nan, height: 100, layout: []),
      SavedLayout(width: 1920, height: 1080, layout: []),
    ])
    #expect(parsed.count == 1)
  }

  @Test func parseKeepsEachSizeOnce() {
    let parsed = Engine.parseSizedLayouts([
      SavedLayout(width: 1920, height: 1080, layout: []),
      SavedLayout(width: 1920, height: 1080, layout: []),
    ])
    #expect(parsed.count == 1)
  }

  @Test func parseFillsTheMissingPanels() {
    let parsed = Engine.parseSizedLayouts([
      SavedLayout(width: 1920, height: 1080, layout: [item("email", 0, 0, 6, 8)])
    ])
    #expect(Set(parsed[0].layout.map(\.i)) == Set(Engine.defaultLayout().map(\.i)))
  }

  @Test func parseKeepsAtMostTwenty() {
    let many = (0..<30).map { SavedLayout(width: Double(1000 + $0), height: 800, layout: []) }
    #expect(Engine.parseSizedLayouts(many).count == Engine.maximumSizedLayouts)
  }
}

/// Mapping, the layout the home shows, and the react-grid-layout operations.
@Suite struct DashboardLayoutEngineTests {
  @Test func placementMapsToAndFromTheServerShape() {
    let placement = place(.jira, 7, 9, 5, 12)
    #expect(placement.layoutItem == item("jira", 7, 9, 5, 12))
    #expect(PanelPlacement(placement.layoutItem) == placement)
    #expect(PanelPlacement(item("jira", 7.4, 8.5, 5, 12)) == place(.jira, 7, 9, 5, 12))
    #expect(PanelPlacement(item("jira", .nan, 0, 5, 12)) == nil)
    #expect(PanelPlacement(item("pomodoro", 0, 0, 5, 12)) == nil)
  }

  @Test func roundsHalvesUpLikeJavaScript() {
    #expect(Engine.jsRound(2.5) == 3)
    #expect(Engine.jsRound(-2.5) == -2)
    #expect(Engine.jsRound(-0.4) == 0)
  }

  @Test func hugeYIsBoundedInsteadOfTrapping() {
    #expect(PanelPlacement(item("email", 0, 1e300, 6, 8))?.y == Engine.maximumY)
  }

  @Test func shownLayoutPrefersTheNearestSavedSize() {
    let saved = [
      SavedLayout(width: 1440, height: 900, layout: [item("email", 5, 0, 7, 14)])
    ]
    let shown = Engine.layout(saved: saved, legacy: [item("email", 0, 0, 7, 14)], width: 1400, height: 880)
    #expect(shown.first { $0.i == .email }?.x == 5)
  }

  @Test func shownLayoutFallsBackToTheLegacyOneThenTheDefault() {
    let legacy = Engine.layout(saved: [], legacy: [item("email", 2, 0, 7, 14)], width: 1400, height: 880)
    #expect(legacy.first { $0.i == .email }?.x == 2)
    #expect(Engine.layout(saved: [], legacy: [], width: 1400, height: 880) == Engine.defaultLayout())
  }

  // MARK: Compaction

  @Test func compactionPullsPanelsUp() {
    let compacted = Engine.compact([place(.email, 0, 5, 6, 4), place(.tasks, 0, 20, 6, 4)])
    #expect(compacted == [place(.email, 0, 0, 6, 4), place(.tasks, 0, 4, 6, 4)])
  }

  @Test func compactionPushesOverlapsDown() {
    let compacted = Engine.compact([place(.email, 0, 0, 6, 4), place(.tasks, 2, 2, 6, 4)])
    #expect(compacted == [place(.email, 0, 0, 6, 4), place(.tasks, 2, 4, 6, 4)])
  }

  @Test func compactionKeepsTheInputOrder() {
    let compacted = Engine.compact([place(.tasks, 0, 10, 6, 4), place(.email, 0, 0, 6, 4)])
    #expect(compacted.map(\.i) == [.tasks, .email])
    #expect(compacted[0].y == 4)
  }

  @Test func theDefaultIsAlreadyCompact() {
    #expect(Engine.compact(Engine.defaultLayout()) == Engine.defaultLayout())
    #expect(Engine.synchronize(Engine.defaultLayout()) == Engine.defaultLayout())
  }

  @Test func synchronizePullsPanelsInsideTheColumns() {
    let synced = Engine.synchronize([place(.email, 10, 3, 6, 4)])
    #expect(synced == [place(.email, 6, 0, 6, 4)])
  }

  // MARK: Moving

  @Test func movingOntoAPanelPushesItDown() {
    let start = [place(.email, 0, 0, 6, 4), place(.tasks, 6, 0, 6, 4)]
    let moved = Engine.move(start, id: .tasks, x: 0, y: 0)
    #expect(moved == [place(.email, 0, 4, 6, 4), place(.tasks, 0, 0, 6, 4)])
  }

  @Test func movingDownBelowEverythingCompactsBackUp() {
    let start = [place(.email, 0, 0, 6, 4), place(.tasks, 6, 0, 6, 4)]
    let moved = Engine.move(start, id: .email, x: 0, y: 30)
    #expect(moved == start)
  }

  /// Checked against react-grid-layout: the stack only swaps once the panel
  /// is dragged past the middle of the one below.
  @Test func movingPastThePanelBelowSwapsTheStack() {
    let start = [place(.email, 0, 0, 12, 4), place(.tasks, 0, 4, 12, 4)]
    #expect(Engine.move(start, id: .email, x: 0, y: 5) == start)
    let moved = Engine.move(start, id: .email, x: 0, y: 7)
    #expect(moved == [place(.email, 0, 4, 12, 4), place(.tasks, 0, 0, 12, 4)])
  }

  @Test func movingClampsToTheGrid() throws {
    let moved = Engine.move([place(.email, 0, 0, 6, 4)], id: .email, x: 20, y: -3)
    let email = try #require(moved.first)
    #expect(email.x == 6)
    #expect(email.y == 0)
  }

  @Test func movingTheDefaultNeverOverlaps() {
    for module in ModuleID.known {
      for x in stride(from: 0, through: 12, by: 3) {
        for y in stride(from: 0, through: 40, by: 7) {
          let moved = Engine.move(Engine.defaultLayout(), id: module, x: x, y: y)
          #expect(!hasOverlaps(moved), "moving \(module) to \(x),\(y)")
          #expect(moved.allSatisfy { $0.x >= 0 && $0.x + $0.w <= Engine.columns && $0.y >= 0 })
          #expect(Engine.compact(moved) == moved)
        }
      }
    }
  }

  @Test func movingAnUnknownPanelChangesNothing() {
    let layout = Engine.defaultLayout()
    #expect(Engine.move(layout, id: ModuleID(rawValue: "x"), x: 0, y: 0) == layout)
  }

  // MARK: Resizing

  @Test func growingWiderPushesTheNeighbourDown() {
    let start = [place(.email, 0, 0, 6, 4), place(.tasks, 6, 0, 6, 4)]
    let resized = Engine.resize(start, id: .email, w: 8, h: 4)
    #expect(resized == [place(.email, 0, 0, 8, 4), place(.tasks, 6, 4, 6, 4)])
  }

  @Test func shrinkingLetsThePanelsBelowRise() {
    let start = [place(.email, 0, 0, 6, 10), place(.tasks, 0, 10, 6, 4)]
    let resized = Engine.resize(start, id: .email, w: 6, h: 4)
    #expect(resized == [place(.email, 0, 0, 6, 4), place(.tasks, 0, 4, 6, 4)])
  }

  @Test func resizingRespectsTheLimits() {
    let start = [place(.email, 4, 0, 6, 10)]
    #expect(Engine.resize(start, id: .email, w: 1, h: 1) == [place(.email, 4, 0, 3, 4)])
    #expect(Engine.resize(start, id: .email, w: 20, h: 500) == [place(.email, 4, 0, 8, 80)])
  }

  @Test func resizingTheDefaultNeverOverlaps() {
    for module in ModuleID.known {
      for w in [3, 5, 8, 12] {
        for h in [4, 9, 20] {
          let resized = Engine.resize(Engine.defaultLayout(), id: module, w: w, h: h)
          #expect(!hasOverlaps(resized), "resizing \(module) to \(w)x\(h)")
          #expect(resized.allSatisfy { $0.x + $0.w <= Engine.columns })
        }
      }
    }
  }

  // MARK: Points

  @Test func framesFollowTheGridMetrics() {
    // 12 columns of 56 pt with 24 pt gaps fill 936 pt.
    let width: CGFloat = 12 * 56 + 11 * 24
    #expect(Engine.columnWidth(containerWidth: width) == 56)
    #expect(
      Engine.frame(for: place(.email, 0, 0, 7, 14), containerWidth: width)
        == CGRect(x: 0, y: 0, width: 7 * 56 + 6 * 24, height: 14 * 32 + 13 * 24))
    #expect(
      Engine.frame(for: place(.agenda, 7, 9, 5, 12), containerWidth: width)
        == CGRect(x: 7 * 80, y: 9 * 56, width: 5 * 56 + 4 * 24, height: 12 * 32 + 11 * 24))
  }

  @Test func pointsMapBackToGridUnits() {
    let width: CGFloat = 12 * 56 + 11 * 24
    let dropped = Engine.gridPosition(
      origin: CGPoint(x: 7 * 80 + 30, y: 9 * 56 - 20), w: 5, h: 4, containerWidth: width)
    #expect(dropped.x == 7 && dropped.y == 9)
    let outside = Engine.gridPosition(origin: CGPoint(x: 5000, y: -300), w: 5, h: 4, containerWidth: width)
    #expect(outside.x == 7 && outside.y == 0)
    let size = Engine.gridSize(
      size: CGSize(width: 5 * 56 + 4 * 24, height: 12 * 32 + 11 * 24), x: 7, containerWidth: width)
    #expect(size.w == 5 && size.h == 12)
    let tooWide = Engine.gridSize(size: CGSize(width: 5000, height: 10), x: 7, containerWidth: width)
    #expect(tooWide.w == 5 && tooWide.h == 1)
    let height: CGFloat = 36 * 32 + 35 * 24
    #expect(Engine.contentHeight(Engine.defaultLayout()) == height)
  }
}
