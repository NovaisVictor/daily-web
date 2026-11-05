/// Arrow-key movement over the rows that can be chosen, for the lists that draw
/// their own active row instead of the system selection (spec 013 FR-013-07).
enum ListCursor {
  /// The id `step` rows away from `current` among `ids`, stopping at the ends as a
  /// system list does. With no current row (or one no longer listed), down starts
  /// at the first row and up at the last.
  static func step<ID: Equatable>(from current: ID?, in ids: [ID], by step: Int) -> ID? {
    guard !ids.isEmpty else { return nil }
    guard let current, let index = ids.firstIndex(of: current) else {
      return step > 0 ? ids.first : ids.last
    }
    return ids[min(max(index + step, 0), ids.count - 1)]
  }
}
