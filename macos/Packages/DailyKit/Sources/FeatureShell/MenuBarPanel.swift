import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The intents of the menu bar panel; the app wires them to its windows and stores.
public struct MenuBarActions {
  public let openApp: () -> Void
  public let openTasks: () -> Void
  public let openAgenda: () -> Void
  public let openNotifications: () -> Void
  public let togglePomodoro: () -> Void
  public let resetPomodoro: () -> Void
  public let quit: () -> Void

  public init(
    openApp: @escaping () -> Void,
    openTasks: @escaping () -> Void,
    openAgenda: @escaping () -> Void,
    openNotifications: @escaping () -> Void,
    togglePomodoro: @escaping () -> Void,
    resetPomodoro: @escaping () -> Void,
    quit: @escaping () -> Void
  ) {
    self.openApp = openApp
    self.openTasks = openTasks
    self.openAgenda = openAgenda
    self.openNotifications = openNotifications
    self.togglePomodoro = togglePomodoro
    self.resetPomodoro = resetPomodoro
    self.quit = quit
  }
}

/// The pomodoro as the panel draws it.
public struct MenuBarPomodoro {
  public let display: PomodoroDisplay
  public let isBusy: Bool
  public let errorMessage: String?

  public init(display: PomodoroDisplay, isBusy: Bool, errorMessage: String?) {
    self.display = display
    self.isBusy = isBusy
    self.errorMessage = errorMessage
  }
}

/// The window of the menu bar item: pomodoro, today's agenda and tasks, unread
/// notifications and the way back to the app.
public struct MenuBarPanel: View {
  /// Nil while signed out.
  private let state: DashboardState?
  private let isSignedIn: Bool
  private let pomodoro: MenuBarPomodoro?
  private let actions: MenuBarActions
  @Environment(\.theme) private var theme

  public init(isSignedIn: Bool, state: DashboardState?, pomodoro: MenuBarPomodoro?, actions: MenuBarActions) {
    self.isSignedIn = isSignedIn
    self.state = state
    self.pomodoro = pomodoro
    self.actions = actions
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isSignedIn {
        signedIn
      } else {
        Button("Entrar…", action: actions.openApp)
          .buttonStyle(.borderedProminent)
      }
      Divider()
      HStack {
        Button("Abrir Daily Web", action: actions.openApp)
        Spacer()
        Button("Sair", action: actions.quit)
          .keyboardShortcut("q", modifiers: .command)
      }
    }
    .padding(14)
    .frame(width: 320, alignment: .leading)
  }

  @ViewBuilder private var signedIn: some View {
    if let pomodoro, pomodoro.display.enabled {
      pomodoroRow(pomodoro)
      Divider()
    }
    if let state {
      // Re-evaluated every minute so "hoje" and the events ahead follow the clock;
      // only while the panel is open.
      TimelineView(.everyMinute) { context in
        summary(MenuBarSummary(state: state, now: context.date))
      }
    } else {
      LoadingState()
        .frame(height: 60)
    }
  }

  @ViewBuilder private func summary(_ summary: MenuBarSummary) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let events = summary.events {
        section("Agenda", action: actions.openAgenda, error: summary.agendaError) {
          if events.isEmpty {
            // `components/AgendaPanel.tsx:149` with the one-day range.
            emptyLine("Nada agendado para hoje.")
          }
          ForEach(events) { event in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(event.time).monospacedDigit().foregroundStyle(theme.inkDim)
              Text(event.title).lineLimit(1)
            }
          }
        }
      }
      if let tasks = summary.tasks {
        section("Tarefas", action: actions.openTasks, error: summary.tasksError) {
          if tasks.isEmpty {
            emptyLine("Nenhuma tarefa atrasada ou para hoje.")
          }
          ForEach(tasks) { task in
            Button(action: actions.openTasks) {
              HStack(spacing: 6) {
                Text(task.title).lineLimit(1)
                if task.isOverdue {
                  Text("atrasada").font(.caption).foregroundStyle(theme.danger)
                }
                Spacer(minLength: 0)
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
          }
        }
      }
      HStack {
        Label(unreadCaption(summary.unreadNotifications), systemImage: "bell")
        Spacer()
        Button("Abrir notificações", action: actions.openNotifications)
      }
    }
  }

  private func pomodoroRow(_ pomodoro: MenuBarPomodoro) -> some View {
    let display = pomodoro.display
    // Labels from `components/Pomodoro.tsx:99-122`.
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(display.isFocus ? "foco" : "descanso").font(.caption).foregroundStyle(theme.inkDim)
          Text("\(display.completedFocusCount) focos").font(.caption).foregroundStyle(theme.inkDim)
            .help("focos concluídos")
        }
        Text(display.formattedRemaining)
          .font(.title2.monospacedDigit())
        Spacer()
        Button(
          display.running ? "pausar foco" : "iniciar foco",
          systemImage: display.running ? "pause.fill" : "play.fill",
          action: actions.togglePomodoro
        )
        .labelStyle(.iconOnly)
        Button("zerar pomodoro", systemImage: "arrow.counterclockwise", action: actions.resetPomodoro)
          .labelStyle(.iconOnly)
      }
      .disabled(pomodoro.isBusy)
      if let error = pomodoro.errorMessage {
        Text(error).font(.caption).foregroundStyle(theme.danger)
      }
    }
  }

  private func section(
    _ title: String,
    action: @escaping () -> Void,
    error: String?,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Button(action: action) {
        Text(title).font(.headline)
      }
      .buttonStyle(.plain)
      .help("Abrir \(title)")
      if let error {
        Text(error).font(.caption).foregroundStyle(theme.danger)
      }
      content()
    }
  }

  private func emptyLine(_ text: String) -> some View {
    Text(text).foregroundStyle(theme.inkDim)
  }

  /// `unreadCaption` of the bell.
  private func unreadCaption(_ count: Int) -> String {
    count == 1 ? "1 não lida" : "\(count) não lidas"
  }
}

#Preview("Conectado") {
  let environment = AppEnvironment.preview()
  MenuBarPanel(
    isSignedIn: true,
    state: environment.dashboard.state,
    pomodoro: environment.pomodoro.display.map { MenuBarPomodoro(display: $0, isBusy: false, errorMessage: nil) },
    actions: PreviewData.menuBarActions
  )
}

#Preview("Desconectado") {
  MenuBarPanel(isSignedIn: false, state: nil, pomodoro: nil, actions: PreviewData.menuBarActions)
}
