import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Jira "agendar foco": `FocusBlockForm` over a `FocusBooking`, booking through the store.
struct FocusScheduleSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var booking: FocusBooking
  private let store: JiraStore

  init(source: FocusSource, calendars: [AgendaCalendarRef], serverURL: URL?, store: JiraStore) {
    _booking = State(initialValue: FocusBooking(source: source, calendars: calendars, server: serverURL))
    self.store = store
  }

  var body: some View {
    FocusBlockForm(
      title: booking.source.title,
      calendars: booking.writableCalendars.map { FocusBlockForm.CalendarOption(id: $0.id, label: $0.label) },
      durations: FocusScheduler.durations,
      defaultStart: FocusBlockForm.defaultStart(now: store.now()),
      isSaving: booking.isSaving,
      errorMessage: booking.errorMessage,
      reconnectMessage: booking.reconnectMessage,
      reconnectAccount: booking.reconnectAccount(for:),
      onSubmit: { start, minutes, connectionId in
        Task {
          let created = await booking.save(
            start: start, minutes: minutes, connectionId: connectionId, using: store.scheduleFocus)
          if created { dismiss() }
        }
      },
      onReconnect: { connectionId in booking.reconnectURL(for: connectionId).map { openURL($0) } },
      onCancel: { dismiss() }
    )
  }
}
