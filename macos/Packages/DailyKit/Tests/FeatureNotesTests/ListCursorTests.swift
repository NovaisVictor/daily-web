import Testing

@testable import FeatureNotes

/// The arrow keys of the notes tree, the search results and the action list.
@Suite struct ListCursorTests {
  let ids = ["a", "b", "c"]

  @Test func movesOneRowEachWay() {
    #expect(ListCursor.step(from: "b", in: ids, by: 1) == "c")
    #expect(ListCursor.step(from: "b", in: ids, by: -1) == "a")
  }

  @Test func stopsAtTheEndsInsteadOfWrapping() {
    #expect(ListCursor.step(from: "c", in: ids, by: 1) == "c")
    #expect(ListCursor.step(from: "a", in: ids, by: -1) == "a")
  }

  @Test func withoutACurrentRowDownTakesTheFirstAndUpTheLast() {
    #expect(ListCursor.step(from: nil, in: ids, by: 1) == "a")
    #expect(ListCursor.step(from: nil, in: ids, by: -1) == "c")
    #expect(ListCursor.step(from: "gone", in: ids, by: 1) == "a")
  }

  @Test func anEmptyListHasNoRow() {
    #expect(ListCursor.step(from: "a", in: [String](), by: 1) == nil)
  }
}
