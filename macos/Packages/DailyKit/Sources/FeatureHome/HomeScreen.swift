import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Início (`app/(app)/page.tsx`): greeting, pomodoro and clock on top
/// (`components/NowBand.tsx`), the "Grade" / "Abas" switch, then the panels of
/// the modules that are on, in the free grid (`DashboardGrid.tsx`), one at a
/// time in a narrow window, or as tabs (`WorkspaceHome.tsx`). Each panel is the
/// module's full panel from `modulePanels`; without one, a read-only summary
/// whose rows open the module on the item they show.
public struct HomeScreen: View {
  /// The web gives the tabs `100dvh - 14rem`, at least 480 px (`WorkspaceHome.tsx`).
  static let reservedHeight: CGFloat = 224
  static let minimumTabsHeight: CGFloat = 480
  /// Room for the narrow module bar under the last panel.
  static let moduleBarHeight: CGFloat = 88

  @Environment(\.theme) private var theme
  @Environment(\.modulePanels) private var modulePanels
  private let store: HomeStore
  private let open: (AppRoute) -> Void
  private let navigator: AppNavigator
  /// The height Início is given, for the panels that need a bounded one.
  @State private var visibleHeight: CGFloat = 0

  /// A chosen panel moves the window through the app's navigator.
  public init(environment: AppEnvironment) {
    let navigator = environment.navigator
    self.init(environment: environment, open: { route in navigator.open(route) })
  }

  /// - Parameter open: Called with `.module(id)` when a summary panel's "Abrir" is chosen.
  ///   A row that points at one item goes through the navigator, which reveals it.
  public init(environment: AppEnvironment, open: @escaping (AppRoute) -> Void) {
    self.init(store: HomeStore.shared(in: environment), navigator: environment.navigator, open: open)
  }

  init(store: HomeStore, navigator: AppNavigator, open: @escaping (AppRoute) -> Void) {
    self.store = store
    self.navigator = navigator
    self.open = open
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        NowBand(store: store)
        banners
        if store.showsViewSwitch {
          toolbar
        }
        content
      }
      .padding(24)
      .padding(.bottom, bottomInset)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    // No fill of its own: the glass panels sit on the window's backdrop (FR-013-03).
    .overlay(alignment: .bottom) { bottomBar }
    .background {
      WindowSizeReader { size in store.updateWindowSize(size) }
        .accessibilityHidden(true)
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.height
    } action: { height in
      visibleHeight = height
    }
    .onChange(of: store.modules) { store.reconcileWorkspace() }
    .onExitCommand { store.discardArrangement() }
    .onDisappear { store.discardArrangement() }
  }

  // MARK: - Top

  @ViewBuilder
  private var banners: some View {
    if let error = store.layoutError {
      ErrorState("Não deu para guardar a disposição", description: error)
    }
    if let error = store.viewError {
      ErrorState("Não deu para trocar a disposição", description: error)
    }
  }

  /// `page.tsx:113-125`.
  private var toolbar: some View {
    HStack(spacing: 8) {
      // `HomeViewSwitch.tsx`.
      SegmentedPills(
        "Disposição do Início",
        items: [
          SegmentedPills<HomeView>.Item(id: HomeView.grid, label: "Grade"),
          SegmentedPills<HomeView>.Item(id: HomeView.workspace, label: "Abas"),
        ],
        selection: Binding(
          get: { store.showsTabs ? HomeView.workspace : HomeView.grid },
          set: { view in Task { await store.chooseView(view) } }
        ),
        style: .toggle
      )
      .fixedSize()
      Spacer(minLength: 8)
      if store.showsTabs {
        Button {
          store.restoreWorkspace()
        } label: {
          Label("Restaurar abas", systemImage: "arrow.counterclockwise")
        }
        .pillButtonStyle(.outline, size: .small)
      }
    }
  }

  // MARK: - Panels

  @ViewBuilder
  private var content: some View {
    if !store.hasState {
      LoadingState()
    } else if store.nothingOn {
      NothingOnState(navigator: navigator)
    } else if store.showsTabs {
      WorkspaceTabsView(
        modules: store.modules,
        title: { HomeModuleInfo.tabTitle($0) },
        panel: { panel(for: $0) },
        layout: Binding(get: { store.workspace.layout }, set: { store.workspace.update($0) })
      )
      .frame(height: max(Self.minimumTabsHeight, visibleHeight - Self.reservedHeight))
      .onAppear { store.loadWorkspace() }
      .onChange(of: store.workspaceAccount) { store.loadWorkspace() }
    } else if !store.isWindowMeasured {
      // Without the window's size there is no layout to choose yet; showing
      // another first would make the panels jump (`page.tsx:44-46`).
      EmptyView()
    } else if store.isNarrow {
      NarrowDashboardView(
        modules: store.narrowModules,
        active: store.activeNarrowModule,
        panelHeight: max(
          Self.minimumTabsHeight, visibleHeight - Self.reservedHeight - Self.moduleBarHeight),
        panel: { panel(for: $0) }
      )
    } else {
      GridDashboardView(store: store, panel: { panel(for: $0) })
    }
  }

  /// The module's full panel, else the read-only summary.
  private func panel(for module: ModuleID) -> AnyView {
    if let full = modulePanels.panel(for: module) { return full }
    return AnyView(
      SummaryPanel(store: store, module: module) { route, itemID in
        if let itemID {
          navigator.open(route, itemID: itemID)
        } else {
          open(route)
        }
      })
  }

  // MARK: - Bottom

  private var showsModuleBar: Bool {
    store.hasState && !store.nothingOn && !store.showsTabs && store.isNarrow
      && NarrowDashboard.showsBar(modules: store.narrowModules)
  }

  private var bottomInset: CGFloat {
    showsModuleBar ? Self.moduleBarHeight : 0
  }

  @ViewBuilder
  private var bottomBar: some View {
    if store.grid.isArranging {
      GridArrangeBar(
        windowSize: store.windowSize,
        isSaving: store.grid.isSaving,
        save: { Task { await store.saveArrangement() } },
        discard: { store.discardArrangement() }
      )
    } else if showsModuleBar {
      GridModuleBar(
        modules: store.narrowModules,
        active: store.activeNarrowModule,
        select: { store.selectNarrowModule($0) }
      )
    }
  }
}

/// A module without a full panel: its summary, refreshed every minute so
/// "hoje", ages and the upcoming events follow the clock.
private struct SummaryPanel: View {
  let store: HomeStore
  let module: ModuleID
  let open: (AppRoute, String?) -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      if let panel = store.panels(at: context.date)?.panels.first(where: { $0.module == module }) {
        ScrollView {
          ModulePanel(
            panel: panel,
            tab: store.selectedTab(of: panel),
            selectTab: { store.selectTab($0, of: panel.module) },
            open: open
          )
        }
        .scrollIndicators(.automatic)
      } else {
        Text(HomePanels.offText)
          .typeRole(.data)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
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
  /// The selected tab, held by `HomeStore` so it outlives this view.
  let tab: HomeTab?
  let selectTab: (String) -> Void
  /// The route and, for a row that points at one item, the item to reveal.
  let open: (AppRoute, String?) -> Void

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
            selection: Binding(get: { tab.id }, set: { selectTab($0) })
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
    .frame(maxWidth: .infinity, alignment: .topLeading)
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

/// Previews keep the tabs arrangement in memory.
@MainActor
private func previewScreen(_ environment: AppEnvironment) -> HomeScreen {
  HomeScreen(
    store: HomeStore.shared(in: environment, workspaceDirectory: nil), navigator: environment.navigator,
    open: { _ in })
}

#Preview("Início") {
  previewScreen(.preview())
    .frame(width: 1280, height: 800)
}

#Preview("Início estreito") {
  previewScreen(.preview())
    .frame(width: 760, height: 720)
}

#Preview("Nenhum módulo") {
  previewScreen(.preview(state: DashboardState(updatedAt: "2026-11-04T12:40:00.000Z", modules: [])))
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
