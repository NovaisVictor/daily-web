import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The "Hoje" screen (`app/(app)/page.tsx`): greeting, pomodoro and clock on top
/// (`components/NowBand.tsx`), then one compact card per module that is on.
/// The web's draggable panel grid is web-only; each card here opens its module.
public struct HomeScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: HomeStore
  private let open: (AppRoute) -> Void
  private let navigator: AppNavigator

  /// A chosen card moves the window through the app's navigator.
  public init(environment: AppEnvironment) {
    let navigator = environment.navigator
    self.init(environment: environment, open: { route in navigator.open(route) })
  }

  /// - Parameter open: Called with `.module(id)` when a card is chosen.
  public init(environment: AppEnvironment, open: @escaping (AppRoute) -> Void) {
    _store = State(initialValue: HomeStore(environment: environment))
    self.open = open
    navigator = environment.navigator
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        NowBand(store: store)
        // Re-evaluated every minute so "hoje" and the upcoming events follow the clock.
        TimelineView(.everyMinute) { context in
          content(store.summary(at: context.date))
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(theme.surface0)
  }

  @ViewBuilder
  private func content(_ summary: HomeSummary?) -> some View {
    if let summary {
      if summary.nothingOn {
        NothingOnState(navigator: navigator)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], spacing: 16) {
          ForEach(summary.cards) { card in
            SummaryCard(card: card) { open(.module(card.module)) }
          }
        }
      }
    } else {
      LoadingState()
    }
  }
}

/// `components/NowBand.tsx`.
private struct NowBand: View {
  @Environment(\.theme) private var theme
  let store: HomeStore

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .bottom, spacing: 24) {
        greeting
        Spacer(minLength: 24)
        HStack(alignment: .bottom, spacing: 40) {
          PomodoroCard(store: store)
          ClockView(ticking: store.isOnScreen)
        }
      }
      VStack(alignment: .leading, spacing: 24) {
        greeting
        HStack(alignment: .bottom, spacing: 40) {
          PomodoroCard(store: store)
          ClockView(ticking: store.isOnScreen)
        }
      }
    }
  }

  private var greeting: some View {
    let greeting = store.greeting
    return VStack(alignment: .leading, spacing: 6) {
      Text(greeting.heading)
        .typeRole(.heading)
        .foregroundStyle(theme.ink)
        .accessibilityAddTraits(.isHeader)
      Text(greeting.welcome)
        .font(.system(size: 14))
        .foregroundStyle(theme.inkMid)
    }
  }
}

/// `components/Clock.tsx`: ticks every second.
private struct ClockView: View {
  let ticking: Bool
  @Environment(\.theme) private var theme

  var body: some View {
    TimelineView(ClockSchedule(ticking: ticking)) { context in
      VStack(alignment: .leading, spacing: 4) {
        Text(ClockText.time(context.date))
          .typeRole(.display)
          .monospacedDigit()
          .foregroundStyle(theme.ink)
        Text(ClockText.date(context.date))
          .typeRole(.body)
          .foregroundStyle(theme.inkMid)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

/// `components/Pomodoro.tsx`. Hidden when the timer is off.
private struct PomodoroCard: View {
  @Environment(\.theme) private var theme
  let store: HomeStore

  var body: some View {
    if let timer = store.timer {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 2) {
            Text(timer.isFocus ? "foco" : "descanso")
            Text("\(timer.completedFocusCount) focos")
              .monospacedDigit()
              .help("focos concluídos")
          }
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          Text(timer.formattedRemaining)
            .typeRole(.subhead)
            .monospacedDigit()
            .foregroundStyle(theme.ink)
          HStack(spacing: 8) {
            let label = timer.running ? "pausar foco" : "iniciar foco"
            Button {
              Task { await store.toggleTimer() }
            } label: {
              Image(systemName: timer.running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help(label)
            .accessibilityLabel(label)
            Button {
              Task { await store.resetTimer() }
            } label: {
              Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .help("zerar pomodoro")
            .accessibilityLabel("zerar pomodoro")
          }
          .disabled(store.timerBusy)
        }
        if let error = store.timerError {
          Text(error)
            .typeRole(.caption)
            .foregroundStyle(theme.danger)
            .accessibilityAddTraits(.isStaticText)
            .onAppear { AccessibilityNotification.Announcement(error).post() }
        }
      }
    }
  }
}

/// One module's summary; the whole card is the button that opens the module.
private struct SummaryCard: View {
  @Environment(\.theme) private var theme
  let card: HomeCard
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        Label(card.title, systemImage: card.systemImage)
          .typeRole(.subhead)
          .foregroundStyle(theme.ink)
        if card.isOff {
          Text(HomeSummary.offText)
            .typeRole(.data)
            .foregroundStyle(theme.inkDim)
        }
        ForEach(card.errors, id: \.self) { PanelError($0) }
        if !card.metrics.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 20) {
            ForEach(card.metrics, id: \.label) { metric in
              MetricView(metric: metric)
            }
          }
        }
        if let empty = card.emptyText {
          Text(empty)
            .typeRole(.data)
            .foregroundStyle(theme.inkDim)
        }
        if !card.lines.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
              Text(line)
                .typeRole(.data)
                .foregroundStyle(theme.inkMid)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(theme.surface1, in: .rect(cornerRadius: Radius.large))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.large).strokeBorder(theme.line)
      }
      .contentShape(.rect(cornerRadius: Radius.large))
    }
    .buttonStyle(.plain)
    .accessibilityHint("abrir \(card.title)")
  }
}

private struct MetricView: View {
  @Environment(\.theme) private var theme
  let metric: HomeMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(metric.value, format: .number)
        .typeRole(.title)
        .monospacedDigit()
        .foregroundStyle(metric.urgent && metric.value > 0 ? theme.danger : theme.ink)
      Text(metric.label)
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The empty state of `app/(app)/page.tsx:126-137`. The web's link goes to the
/// integrations page; the native app keeps integrations in Settings.
private struct NothingOnState: View {
  let navigator: AppNavigator
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    EmptyState(
      "Nenhum módulo ligado ainda",
      description:
        "Conecte seu e-mail, agenda, Jira ou GitHub para o painel começar a mostrar alguma coisa. "
        + "Cada um é opcional e leva menos de um minuto.",
      systemImage: "powerplug"
    ) {
      Button("Conectar minhas contas") {
        navigator.requestSettings(.integrations)
        openSettings()
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

#Preview("Hoje") {
  HomeScreen(environment: .preview())
    .frame(width: 960, height: 720)
}

#Preview("Nenhum módulo") {
  HomeScreen(environment: .preview(state: DashboardState(updatedAt: "2026-11-04T12:40:00.000Z", modules: [])))
    .frame(width: 960, height: 520)
}

/// Every second while on screen; a single entry (no redraws) while hidden.
private struct ClockSchedule: TimelineSchedule {
  let ticking: Bool

  func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
    guard ticking else {
      var done = false
      return AnyIterator {
        defer { done = true }
        return done ? nil : startDate
      }
    }
    var next = startDate
    return AnyIterator {
      defer { next = next.addingTimeInterval(1) }
      return next
    }
  }
}
