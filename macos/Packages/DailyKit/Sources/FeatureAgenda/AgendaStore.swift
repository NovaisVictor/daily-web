import DailyAPI
import DailyCore
import DailyDesign
import DailyModels
import Foundation
import Observation
import os

/// A focus block being set up in the sheet (`FocusBlockProvider.tsx` state).
struct FocusDraft: Identifiable, Equatable {
  let id = UUID()
  var source: FocusSource
  var start: Date
  var minutes: Int
  var connectionId: String
}

/// The agenda screen: period, events and the focus-block drop
/// (`components/AgendaPanel.tsx`, `components/FocusBlockProvider.tsx`).
@Observable
final class AgendaStore {
  var draft: FocusDraft?
  /// The last refusal or failure of the sheet, shown under its fields.
  private(set) var draftError: String?
  /// A 409 from the server: the calendar lacks write permission.
  private(set) var reconnectMessage: String?

  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let preferences: PreferencesStore
  @ObservationIgnored private let focus: FocusScheduler
  @ObservationIgnored private let now: Now
  @ObservationIgnored let calendar: Calendar

  init(
    dashboard: DashboardStore,
    preferences: PreferencesStore,
    focus: FocusScheduler,
    now: @escaping Now = LiveTime.now,
    calendar: Calendar = .current
  ) {
    self.dashboard = dashboard
    self.preferences = preferences
    self.focus = focus
    self.now = now
    // The server's dates are Gregorian whatever the system calendar is.
    self.calendar = AgendaLogic.gregorian(in: calendar.timeZone)
  }

  var state: DashboardState? { dashboard.state }
  var agenda: PanelResult<[AgendaItem]>? { state?.agenda }
  var items: [AgendaItem] { agenda?.data ?? [] }
  var groups: [AgendaDayGroup] { AgendaLogic.group(items) }
  var showsAccountLabels: Bool { AgendaLogic.showsAccountLabels(items) }
  /// `DEFAULT_AGENDA_DAYS` until the first state arrives.
  var days: Int { state?.agendaDays ?? 2 }
  var isChangingRange: Bool { preferences.isUpdatingAgendaDays }
  var isSaving: Bool { focus.isSaving }

  var calendars: [AgendaCalendarRef] { state?.agendaCalendars ?? [] }
  var writableCalendars: [AgendaCalendarRef] { calendars.filter(\.canWrite) }
  /// The drop zone only shows with a calendar to book on (`FocusBlockProvider.tsx:105`).
  var acceptsDrops: Bool { !calendars.isEmpty }

  func dayLabel(_ iso: String) -> String {
    AgendaLogic.relativeDayLabel(iso, today: now(), calendar: calendar)
  }

  /// Changing the period changes what the server fetches, so it is saved, not
  /// filtered locally. The same period again does nothing.
  func chooseRange(_ next: Int) async {
    guard next != days else { return }
    // `PreferencesStore` shows its own error toast and keeps the old period.
    await preferences.setAgendaDays(next)
  }

  /// Opens the sheet for the first valid dropped item. Returns whether one was accepted.
  @discardableResult
  func receiveDrop(_ items: [FocusSource]) -> Bool {
    guard acceptsDrops, let source = AgendaLogic.acceptedSource(items) else {
      Logger.agenda.notice("Ignored a focus drop with no valid item")
      return false
    }
    draft = FocusDraft(
      source: source,
      start: FocusBlockForm.defaultStart(now: now(), calendar: calendar),
      minutes: FocusBlockForm.defaultMinutes,
      connectionId: (writableCalendars.first ?? calendars.first)?.id ?? ""
    )
    draftError = nil
    reconnectMessage = nil
    return true
  }

  func cancelDraft() {
    guard !isSaving else { return }
    draft = nil
    draftError = nil
    reconnectMessage = nil
  }

  /// Books the block the sheet set up; the sheet edits its own copy of the draft.
  func schedule(_ current: FocusDraft) async {
    guard !writableCalendars.isEmpty else { return }
    draftError = nil
    reconnectMessage = nil
    let result = await focus.schedule(
      current.source, connectionId: current.connectionId, start: current.start, minutes: current.minutes)
    switch result {
    case .created:
      draft = nil
    case .invalid(let message):
      draftError = message
    case .reconnect(let message):
      reconnectMessage = message
    case .failed(let error):
      draftError = error.userMessage
    }
  }

  /// The account to reconnect: the chosen calendar's, else the first one's.
  func reconnectAccount(for connectionId: String) -> AgendaCalendarRef? {
    FocusReconnect.calendar(for: connectionId, in: calendars)
  }

  func reconnectURL(server: URL?, connectionId: String) -> URL? {
    guard let server, let calendar = reconnectAccount(for: connectionId) else { return nil }
    return FocusReconnect.url(server: server, account: calendar.account)
  }
}
