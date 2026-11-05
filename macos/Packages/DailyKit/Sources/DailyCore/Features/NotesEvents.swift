/// "The notes changed outside the notes panel" (`notesChanged` in the web's
/// `lib/notesBus.ts`, spec 015 FR-015-07). The real case is a note created
/// from an e-mail: the notes store reads its list once, and without this
/// notice the new note would only show after a manual reload.
///
/// Lives in core so the e-mail feature can tell the notes feature without
/// importing it.
public final class NotesEvents {
  public struct Change: Equatable, Sendable {
    /// The note to open once the list is read again; nil only reloads.
    public let activate: String?

    public init(activate: String?) {
      self.activate = activate
    }
  }

  private struct Observer {
    weak var owner: AnyObject?
    let handler: (Change) -> Void
  }

  private var observers: [Observer] = []

  public init() {}

  /// Calls `handler` on every change for as long as `owner` lives. Tying the
  /// subscription to the owner keeps a signed-out session's store from being
  /// called, or kept alive, after `FeatureStores` let it go.
  public func observe(_ owner: AnyObject, _ handler: @escaping (Change) -> Void) {
    observers.removeAll { $0.owner == nil }
    observers.append(Observer(owner: owner, handler: handler))
  }

  public func post(_ change: Change) {
    observers.removeAll { $0.owner == nil }
    for observer in observers { observer.handler(change) }
  }

  /// How many owners are still listening; for tests.
  public var observerCount: Int {
    observers.filter { $0.owner != nil }.count
  }
}
