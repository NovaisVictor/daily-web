import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The agenda's "Agendar foco": `FocusBlockForm` over the store's draft.
struct FocusBlockSheet: View {
  @Environment(\.openURL) private var openURL
  let store: AgendaStore
  /// Captured when the sheet opens, so the form never reads a draft the store
  /// already dropped while the sheet animates away.
  let draft: FocusDraft
  let server: URL?

  var body: some View {
    FocusBlockForm(
      title: draft.source.title,
      calendars: store.writableCalendars.map { FocusBlockForm.CalendarOption(id: $0.id, label: $0.label) },
      durations: FocusScheduler.durations,
      defaultStart: draft.start,
      isSaving: store.isSaving,
      errorMessage: store.draftError,
      reconnectMessage: store.reconnectMessage,
      reconnectAccount: { connectionId in
        guard store.reconnectURL(server: server, connectionId: connectionId) != nil,
          let account = store.reconnectAccount(for: connectionId)
        else { return nil }
        return account.account.isEmpty ? account.label : account.account
      },
      onSubmit: { start, minutes, connectionId in
        var current = draft
        current.start = start
        current.minutes = minutes
        current.connectionId = connectionId
        Task { await store.schedule(current) }
      },
      onReconnect: { connectionId in
        guard let url = store.reconnectURL(server: server, connectionId: connectionId) else { return }
        openURL(url)
      },
      onCancel: store.cancelDraft
    )
  }
}
