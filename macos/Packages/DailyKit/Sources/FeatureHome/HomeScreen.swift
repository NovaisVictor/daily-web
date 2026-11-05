import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The "Hoje" screen (`app/(app)/page.tsx`): greeting, pomodoro and clock on top
/// (`components/NowBand.tsx`), then one panel per module that is on, in two
/// columns when the window is wide enough. The panels are read-only previews of
/// the web's panels; their rows open the module on the item they show.
public struct HomeScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: HomeStore
  @State private var gridWidth: CGFloat = 0
  private let open: (AppRoute) -> Void
  private let navigator: AppNavigator

  /// Below this width the panels stack in one column: two would squeeze each
  /// row's title next to its lead column.
  private static let twoColumnWidth: CGFloat = 820

  /// A chosen panel moves the window through the app's navigator.
  public init(environment: AppEnvironment) {
    let navigator = environment.navigator
    self.init(environment: environment, open: { route in navigator.open(route) })
  }

  /// - Parameter open: Called with `.module(id)` when a panel's "Abrir" is chosen.
  ///   A row that points at one item goes through the navigator, which reveals it.
  public init(environment: AppEnvironment, open: @escaping (AppRoute) -> Void) {
    _store = State(initialValue: HomeStore(environment: environment))
    self.open = open
    navigator = environment.navigator
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        NowBand(store: store)
        // Re-evaluated every minute so "hoje", ages and the upcoming events follow the clock.
        TimelineView(.everyMinute) { context in
          content(store.panels(at: context.date))
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    // No fill of its own: the glass panels sit on the window's backdrop (FR-013-03).
  }

  @ViewBuilder
  private func content(_ home: HomePanels?) -> some View {
    if let home {
      if home.nothingOn {
        NothingOnState(navigator: navigator)
      } else {
        columns(home.panels)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: {
            gridWidth = $0
          }
      }
    } else {
      LoadingState()
    }
  }

  /// Two independent columns (panels alternate left and right in the web's
  /// order), so a short panel never leaves a gap under it.
  @ViewBuilder
  private func columns(_ panels: [HomePanel]) -> some View {
    if gridWidth >= Self.twoColumnWidth {
      HStack(alignment: .top, spacing: 16) {
        column(panels.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
        column(panels.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element))
      }
    } else {
      column(panels)
    }
  }

  private func column(_ panels: [HomePanel]) -> some View {
    VStack(spacing: 16) {
      ForEach(panels) { panel in
        ModulePanel(panel: panel) { route, itemID in
          if let itemID {
            navigator.open(route, itemID: itemID)
          } else {
            open(route)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
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
        .font(.daily(size: 14))
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
            // `IconAction variant="default"` (Pomodoro.tsx:106-117): the brand face.
            IconButton(label, systemImage: timer.running ? "pause.fill" : "play.fill", variant: .primary) {
              Task { await store.toggleTimer() }
            }
            IconButton("zerar pomodoro", systemImage: "arrow.counterclockwise") {
              Task { await store.resetTimer() }
            }
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

/// One module's panel: title, count, "Abrir ›", the web panel's tabs and the
/// first rows of the selected tab.
private struct ModulePanel: View {
  @Environment(\.theme) private var theme
  let panel: HomePanel
  /// The route and, for a row that points at one item, the item to reveal.
  let open: (AppRoute, String?) -> Void
  @State private var selectedTab: String?

  private var tab: HomeTab? {
    panel.tabs.first { $0.id == selectedTab } ?? panel.tabs.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(panel.title, count: tab?.countText) {
        Button {
          open(panel.route, nil)
        } label: {
          HStack(spacing: 4) {
            Text("Abrir")
            Image(systemName: "chevron.right").imageScale(.small)
          }
          .typeRole(.caption)
          .foregroundStyle(theme.brand)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(panel.title)")
      }
      if panel.hasTabs, let tab {
        // A narrow column scrolls the tabs sideways instead of clipping them.
        ScrollView(.horizontal, showsIndicators: false) {
          SegmentedPills(
            "abas de \(panel.title)",
            items: panel.tabs.map { .init(id: $0.id, label: $0.label, count: $0.count) },
            selection: Binding(get: { tab.id }, set: { selectedTab = $0 })
          )
          .fixedSize()
          .padding(4)
        }
        .scrollClipDisabled()
      }
      if let tab {
        TabBody(tab: tab) { open(panel.route, $0.itemID) }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .glassSurface(.panel)
  }
}

private struct TabBody: View {
  @Environment(\.theme) private var theme
  let tab: HomeTab
  let choose: (HomeRow) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if tab.isOff {
        Text(HomePanels.offText)
          .typeRole(.data)
          .foregroundStyle(theme.inkDim)
      }
      ForEach(tab.errors, id: \.self) { PanelError($0) }
      if let empty = tab.emptyText {
        Text(empty)
          .typeRole(.data)
          .foregroundStyle(theme.inkDim)
      }
      if !tab.rows.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(tab.rows.enumerated()), id: \.element.id) { index, row in
            ListRow(index: index, isLast: index == tab.rows.count - 1) {
              PanelRow(row: row) { choose(row) }
            }
          }
        }
      }
    }
  }
}

/// A read-only row; choosing it opens the module, on the item when it has one.
private struct PanelRow: View {
  @Environment(\.theme) private var theme
  let row: HomeRow
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(row.lead)
          .typeRole(.data)
          .foregroundStyle(row.leadIsLate ? theme.warning : theme.brand)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(width: 84, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            if row.emphasized {
              StatusDot(.info)
            }
            Text(row.title)
              .typeRole(.data)
              .fontWeight(row.emphasized ? .semibold : nil)
              .foregroundStyle(theme.ink)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          if !row.pills.isEmpty || !row.meta.isEmpty {
            FlowLayout(spacing: 8) {
              ForEach(row.pills, id: \.label) { pill in
                StatusPill(pill.label, glyph: pill.glyph, tone: pill.tone)
              }
              if !row.meta.isEmpty {
                Text(row.metaText)
                  .typeRole(.caption)
                  .foregroundStyle(theme.inkMid)
                  .lineLimit(1)
                  .truncationMode(.tail)
              }
            }
          }
        }
        Spacer(minLength: 0)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityValue(row.emphasized ? "não lido" : "")
  }
}

/// The empty state of `app/(app)/page.tsx:126-137`. The web's link goes to the
/// integrations page, the app's Ferramentas.
private struct NothingOnState: View {
  let navigator: AppNavigator

  var body: some View {
    EmptyState(
      "Nenhum módulo ligado ainda",
      description:
        "Conecte seu e-mail, agenda, Jira ou GitHub para o painel começar a mostrar alguma coisa. "
        + "Cada um é opcional e leva menos de um minuto.",
      systemImage: "powerplug"
    ) {
      Button("Conectar minhas contas") {
        navigator.open(.ferramentas)
      }
      .pillButtonStyle()
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
