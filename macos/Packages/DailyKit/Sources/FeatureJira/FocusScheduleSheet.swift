import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Jira "agendar foco": `FocusBlockForm` booking through the store.
struct FocusScheduleSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  let source: FocusSource
  let calendars: [AgendaCalendarRef]
  let serverURL: URL?
  let store: JiraStore

  @State private var saving = false
  @State private var error: String?
  @State private var reconnect: String?

  var body: some View {
    FocusBlockForm(
      title: source.title,
      calendars: calendars.filter(\.canWrite).map { FocusBlockForm.CalendarOption(id: $0.id, label: $0.label) },
      durations: FocusScheduler.durations,
      defaultStart: FocusBlockForm.defaultStart(now: store.now()),
      isSaving: saving,
      errorMessage: error,
      reconnectMessage: reconnect,
      reconnectAccount: { connectionId in
        guard let calendar = account(for: connectionId), reconnectURL(calendar) != nil else { return nil }
        return calendar.account.isEmpty ? calendar.label : calendar.account
      },
      onSubmit: save,
      onReconnect: { connectionId in
        guard let calendar = account(for: connectionId), let url = reconnectURL(calendar) else { return }
        openURL(url)
      },
      onCancel: { dismiss() }
    )
  }

  /// The chosen calendar's account, else the first one's (the web links `calendars[0]`).
  private func account(for connectionId: String) -> AgendaCalendarRef? {
    calendars.first { $0.id == connectionId } ?? calendars.first
  }

  private func reconnectURL(_ calendar: AgendaCalendarRef) -> URL? {
    guard let serverURL else { return nil }
    var components = URLComponents(
      url: serverURL.appending(path: "api/integrations/agenda/google/start"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "login_hint", value: calendar.account)]
    return components?.url
  }

  private func save(start: Date, minutes: Int, connectionId: String) {
    guard !saving else { return }
    saving = true
    error = nil
    reconnect = nil
    Task {
      let result = await store.scheduleFocus(source, connectionId: connectionId, start: start, minutes: minutes)
      saving = false
      switch result {
      case .created: dismiss()
      case .invalid(let message): error = message
      case .reconnect(let message): reconnect = message
      case .failed(let apiError): error = apiError.userMessage
      }
    }
  }
}
