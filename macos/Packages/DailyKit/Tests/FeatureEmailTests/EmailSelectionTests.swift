import Testing

@testable import FeatureEmail

/// The cases of `tests/lib/emailSelection.test.ts`.
@Suite struct EmailSelectionTests {
  let order = ["a", "b", "c", "d", "e"]

  func reduce(_ state: EmailSelection = .empty, _ events: EmailSelection.Event...) -> EmailSelection {
    events.reduce(state) { $0.reduced($1, order: order) }
  }

  @Test func clickSelectsOnlyTheRow() {
    let state = reduce(.empty, .click("b"))
    #expect(state.selected == ["b"])
    #expect(state.anchor == "b")
  }

  @Test func clickReplacesInsteadOfAdding() {
    #expect(reduce(.empty, .click("b"), .click("d")).selected == ["d"])
  }

  @Test func commandClickAddsAndRemoves() {
    #expect(reduce(.empty, .click("b"), .click("d", meta: true)).selected == ["b", "d"])
    #expect(reduce(.empty, .click("b"), .click("d", meta: true), .click("b", meta: true)).selected == ["d"])
    #expect(reduce(.empty, .click("b"), .click("d", meta: true)).anchor == "d")
  }

  @Test func shiftClickMarksTheRangeBothWays() {
    #expect(reduce(.empty, .click("b"), .click("d", shift: true)).selected == ["b", "c", "d"])
    #expect(reduce(.empty, .click("d"), .click("b", shift: true)).selected == ["b", "c", "d"])
  }

  @Test func shiftClickRedoesTheRangeFromTheSameAnchor() {
    let state = reduce(.empty, .click("b"), .click("e", shift: true), .click("c", shift: true))
    #expect(state.selected == ["b", "c"])
    #expect(state.anchor == "b")
  }

  @Test func shiftCommandClickAddsTheRange() {
    let state = reduce(.empty, .click("a"), .click("c", meta: true), .click("e", shift: true, meta: true))
    #expect(state.selected == ["a", "c", "d", "e"])
  }

  @Test func shiftWithoutAnchorIsAPlainClick() {
    #expect(reduce(.empty, .click("c", shift: true)).selected == ["c"])
  }

  @Test func arrowsWalkOneRow() {
    let state = reduce(.empty, .click("b"), .move(down: true))
    #expect(state.selected == ["c"])
    #expect(state.cursor == "c")
  }

  @Test func shiftArrowsExtend() {
    let state = reduce(.empty, .click("b"), .move(down: true, extend: true), .move(down: true, extend: true))
    #expect(state.selected == ["b", "c", "d"])
  }

  @Test func shiftArrowUpShrinksTowardsTheAnchor() {
    let state = reduce(
      .empty, .click("b"), .move(down: true, extend: true), .move(down: true, extend: true),
      .move(down: false, extend: true))
    #expect(state.selected == ["b", "c"])
  }

  @Test func cursorStopsAtTheEnds() {
    #expect(reduce(.empty, .click("e"), .move(down: true)).cursor == "e")
    #expect(reduce(.empty, .click("a"), .move(down: false)).cursor == "a")
  }

  @Test func startsAtTheTopOrBottomWithNothingSelected() {
    #expect(reduce(.empty, .move(down: true)).selected == ["a"])
    #expect(reduce(.empty, .move(down: false)).selected == ["e"])
  }

  @Test func spaceTogglesTheCursorRow() {
    #expect(reduce(.empty, .click("b"), .move(down: true), .toggle("c")).selected == [])
    #expect(reduce(.empty, .click("b"), .toggle("d")).selected == ["b", "d"])
  }

  @Test func selectAllAndClear() {
    let all = reduce(.empty, .all)
    #expect(all.selected == order)
    #expect(all.anchor == "a")
    #expect(all.cursor == "e")
    let cleared = reduce(.empty, .click("b"), .clear)
    #expect(cleared == .empty)
  }

  @Test func syncDropsWhatLeftTheList() {
    let state = reduce(.empty, .all)
    #expect(state.reduced(.sync, order: ["a", "c"]).selected == ["a", "c"])
    let anchored = reduce(.empty, .click("e"))
    #expect(anchored.reduced(.sync, order: ["a", "b"]).anchor == nil)
    let same = reduce(.empty, .click("b"))
    #expect(same.reduced(.sync, order: order) == same)
  }

  @Test func groupCheckbox() {
    #expect(reduce(.empty, .click("a"), .group(["c", "d"])).selected == ["a", "c", "d"])
    #expect(reduce(.empty, .click("c"), .group(["c", "d", "e"])).selected == ["c", "d", "e"])
    #expect(reduce(.empty, .click("a"), .group(["c", "d"]), .group(["c", "d"])).selected == ["a"])
    #expect(reduce(.empty, .group(["b", "c"]), .click("e", shift: true)).selected == ["b", "c", "d", "e"])
    #expect(reduce(.empty, .group(["sumiu"])) == .empty)
  }

  @Test func rightClick() {
    let before = reduce(.empty, .group(["b", "c", "d"]))
    #expect(before.reduced(.context("c"), order: order) == before)
    let outside = reduce(.empty, .group(["b", "c"]), .context("e"))
    #expect(outside.selected == ["e"])
    #expect(outside.anchor == "e")
    #expect(reduce(.empty, .context("a")).selected == ["a"])
  }
}
