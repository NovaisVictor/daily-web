import DailyAPI
import DailyModels
import Foundation
import Observation

/// "Reconectar" on a focus sheet: the server's Google flow, which the browser's
/// own session finishes (`app/api/integrations/agenda/google/start/route.ts`).
public enum FocusReconnect {
  public static let path = "/api/integrations/agenda/google/start"

  /// `…/start?login_hint=…` on the server. No account, or an empty one, sends
  /// no hint at all, so Google asks which account to use.
  public static func url(server: URL, account: String?) -> URL? {
    guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
    components.path = path
    components.fragment = nil
    guard let account, !account.isEmpty else {
      components.queryItems = nil
      return components.url
    }
    components.queryItems = [URLQueryItem(name: "login_hint", value: account)]
    // URLComponents leaves "+" alone, and the server's `URLSearchParams` reads it as a space.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url
  }

  /// The calendar whose account is reconnected: the chosen one, else the first
  /// (the web links `calendars[0]`).
  public static func calendar(for connectionId: String, in calendars: [AgendaCalendarRef]) -> AgendaCalendarRef? {
    calendars.first { $0.id == connectionId } ?? calendars.first
  }

  /// The name on "Reconectar …": the account, else the calendar's label.
  public static func accountName(_ calendar: AgendaCalendarRef) -> String {
    calendar.account.isEmpty ? calendar.label : calendar.account
  }
}

/// The state of a feature's "Agendar foco" sheet (`FocusBlockProvider.tsx`):
/// the saving flag, the refusal shown under the fields and the reconnect link.
/// Each feature books through its own store, so only the call is passed in.
@Observable
public final class FocusBooking {
  public typealias Schedule = (
    _ source: FocusSource, _ connectionId: String, _ start: Date, _ minutes: Int
  ) async -> FocusScheduleResult

  public let source: FocusSource
  public let calendars: [AgendaCalendarRef]
  public private(set) var isSaving = false
  public private(set) var errorMessage: String?
  public private(set) var reconnectMessage: String?
  @ObservationIgnored private let server: URL?

  public init(source: FocusSource, calendars: [AgendaCalendarRef], server: URL?) {
    self.source = source
    self.calendars = calendars
    self.server = server
  }

  /// Only these can receive a block; the others still name the account to reconnect.
  public var writableCalendars: [AgendaCalendarRef] { calendars.filter(\.canWrite) }

  public func reconnectURL(for connectionId: String) -> URL? {
    guard let server, let calendar = FocusReconnect.calendar(for: connectionId, in: calendars) else { return nil }
    return FocusReconnect.url(server: server, account: calendar.account)
  }

  /// The account named on the link; nil hides it, as when there is no server to open.
  public func reconnectAccount(for connectionId: String) -> String? {
    guard reconnectURL(for: connectionId) != nil,
      let calendar = FocusReconnect.calendar(for: connectionId, in: calendars)
    else { return nil }
    return FocusReconnect.accountName(calendar)
  }

  /// Books the block; true once it was created, so the sheet closes. A second
  /// submit while one is on its way is ignored.
  public func save(start: Date, minutes: Int, connectionId: String, using schedule: Schedule) async -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    errorMessage = nil
    reconnectMessage = nil
    defer { isSaving = false }
    switch await schedule(source, connectionId, start, minutes) {
    case .created: return true
    case .invalid(let message): errorMessage = message
    case .reconnect(let message): reconnectMessage = message
    case .failed(let error): errorMessage = error.userMessage
    }
    return false
  }
}
