import SwiftUI

/// "Agendar foco" (`components/FocusBlockProvider.tsx:107-177`): day, start,
/// one of the durations and, with more than one writable calendar, the
/// calendar. Presentational only: every feature that books a focus block wraps
/// it and maps `FocusScheduler`'s result to `errorMessage`/`reconnectMessage`.
public struct FocusBlockForm: View {
  /// A writable calendar the block can go to.
  public struct CalendarOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
      self.id = id
      self.label = label
    }
  }

  /// The duration the web preselects (`FocusBlockProvider.tsx:61`).
  public static let defaultMinutes = 50

  @Environment(\.theme) private var theme
  private let title: String
  private let calendars: [CalendarOption]
  private let durations: [Int]
  private let isSaving: Bool
  private let errorMessage: String?
  private let reconnectMessage: String?
  private let reconnectAccount: (_ connectionId: String) -> String?
  private let onSubmit: (_ start: Date, _ minutes: Int, _ connectionId: String) -> Void
  private let onReconnect: (_ connectionId: String) -> Void
  private let onCancel: () -> Void

  @State private var start: Date
  @State private var minutes: Int
  @State private var connectionId: String

  /// - Parameters:
  ///   - calendars: the writable calendars only; empty shows the reconnect text.
  ///   - reconnectAccount: the account named on "Reconectar …" for the chosen
  ///     calendar (empty when none is chosen); nil hides the link.
  public init(
    title: String,
    calendars: [CalendarOption],
    durations: [Int],
    defaultStart: Date,
    isSaving: Bool,
    errorMessage: String?,
    reconnectMessage: String?,
    reconnectAccount: @escaping (_ connectionId: String) -> String?,
    onSubmit: @escaping (_ start: Date, _ minutes: Int, _ connectionId: String) -> Void,
    onReconnect: @escaping (_ connectionId: String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.calendars = calendars
    self.durations = durations
    self.isSaving = isSaving
    self.errorMessage = errorMessage
    self.reconnectMessage = reconnectMessage
    self.reconnectAccount = reconnectAccount
    self.onSubmit = onSubmit
    self.onReconnect = onReconnect
    self.onCancel = onCancel
    _start = State(initialValue: defaultStart)
    _minutes = State(
      initialValue: durations.contains(Self.defaultMinutes)
        ? Self.defaultMinutes : durations.first ?? Self.defaultMinutes)
    _connectionId = State(initialValue: calendars.first?.id ?? "")
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Agendar foco")
          .typeRole(.subhead)
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        Text(title)
          .font(.geist(size: TextSize.small))
          .foregroundStyle(theme.inkMid)
      }

      if calendars.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Para criar blocos de foco, reconecte sua conta do Google.")
            .font(.geist(size: TextSize.small))
          reconnectButton
        }
      } else {
        fields
      }

      if let errorMessage {
        announced(errorMessage)
      }
      if let reconnectMessage {
        VStack(alignment: .leading, spacing: 8) {
          announced(reconnectMessage)
          reconnectButton
        }
      }

      HStack {
        Spacer()
        Button("Cancelar", action: onCancel)
          .pillButtonStyle(.outline)
          .keyboardShortcut(.cancelAction)
          .disabled(isSaving)
        if !calendars.isEmpty {
          Button(isSaving ? "Criando…" : "Criar bloco") { onSubmit(start, minutes, connectionId) }
            .pillButtonStyle(.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
      }
    }
    .padding(24)
    .frame(width: 420)
    .interactiveDismissDisabled(isSaving)
  }

  private var fields: some View {
    Form {
      DatePicker("Dia", selection: $start, displayedComponents: .date)
      DatePicker("Início", selection: $start, displayedComponents: .hourAndMinute)
      // One small button per duration, the chosen one on the primary face
      // (`FocusBlockProvider.tsx:135-149`).
      LabeledContent("Duração") {
        FlowLayout(spacing: 8) {
          ForEach(durations, id: \.self) { duration in
            Button("\(duration) min") { minutes = duration }
              .pillButtonStyle(minutes == duration ? .primary : .outline, size: .small)
              .accessibilityAddTraits(minutes == duration ? .isSelected : [])
          }
        }
      }
      if calendars.count > 1 {
        Picker("Agenda", selection: $connectionId) {
          ForEach(calendars) { calendar in
            Text(calendar.label).tag(calendar.id)
          }
        }
      }
    }
    .formStyle(.columns)
  }

  /// `role="alert"` on the web.
  private func announced(_ message: String) -> some View {
    Text(message)
      .font(.geist(size: TextSize.small))
      .foregroundStyle(theme.danger)
      .onAppear { AccessibilityNotification.Announcement(message).post() }
  }

  @ViewBuilder private var reconnectButton: some View {
    if let account = reconnectAccount(connectionId) {
      Button("Reconectar \(account)") { onReconnect(connectionId) }
        .buttonStyle(.link)
    }
  }

  /// `defaultStart` (`lib/focusBlock.ts:39-49`): the next half hour, or the
  /// next whole hour past :20; past 20:00, 09:00 the next day.
  public static func defaultStart(now: Date, calendar: Calendar = .current) -> Date {
    var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    let minutes = parts.minute ?? 0
    parts.minute = 0
    let hourStart = calendar.date(from: parts) ?? now
    let rounded = hourStart.addingTimeInterval(TimeInterval((minutes <= 20 ? 30 : 60) * 60))
    let hour = calendar.component(.hour, from: rounded)
    let minute = calendar.component(.minute, from: rounded)
    guard hour > 20 || (hour == 20 && minute > 0) else { return rounded }
    let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rounded)) ?? rounded
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? nextDay
  }
}

#Preview("Agendar foco") {
  FocusBlockForm(
    title: "Escrever relatório",
    calendars: [.init(id: "a", label: "Pessoal"), .init(id: "b", label: "Trabalho")],
    durations: [25, 50, 90, 120],
    defaultStart: FocusBlockForm.defaultStart(now: .now),
    isSaving: false,
    errorMessage: nil,
    reconnectMessage: nil,
    reconnectAccount: { _ in "voce@example.com" },
    onSubmit: { _, _, _ in },
    onReconnect: { _ in },
    onCancel: {}
  )
}
