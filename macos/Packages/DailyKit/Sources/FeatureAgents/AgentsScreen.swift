import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The agent tasks board (`components/agents/AgentBoard.tsx`). In `.kanban` it is
/// the "Kanban de tarefas" page; in `.workspace` it is "Agentes e atividades",
/// with the sessions tab. Each task's page opens inside the screen.
public struct AgentsScreen: View {
  @State private var store: AgentsStore
  @State private var searchPresented = false
  /// The card "N aguardando você" moves the keyboard to (`card.focus()` in the web).
  @FocusState private var focusedCard: String?
  @Environment(\.theme) private var theme
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let navigator: AppNavigator

  public init(environment: AppEnvironment) {
    self.init(environment: environment, mode: .workspace)
  }

  public init(environment: AppEnvironment, mode: AgentsMode) {
    self.init(store: AgentsStore(environment: environment, mode: mode), navigator: environment.navigator)
  }

  init(store: AgentsStore, navigator: AppNavigator) {
    _store = State(initialValue: store)
    self.navigator = navigator
  }

  public var body: some View {
    // Re-renders every 30 s so "há N min" moves even when a poll brings nothing new.
    TimelineView(.periodic(from: .now, by: 30)) { context in
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let detail = store.detail {
              AgentTaskDetailView(
                store: detail,
                now: context.date,
                back: { store.closeTask() },
                openTask: { store.openTask($0) },
                openSession: { store.openSessionTasks($0) })
            } else {
              header(proxy: proxy)
              board(now: context.date)
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }
    .onAppear {
      store.setVisible(true)
      openPendingTask()
    }
    .onDisappear { store.setVisible(false) }
    .onChange(of: navigator.pending) { openPendingTask() }
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  /// The request names the agents route, so the Kanban leaves it to that screen.
  private func openPendingTask() {
    guard isPrimaryWindow, store.mode == .workspace else { return }
    store.openPendingTask(from: navigator)
  }

  // MARK: - Header

  private func header(proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      // `flex flex-wrap items-center justify-between gap-4` (`AgentBoard.tsx:57`).
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 16) {
          title
          Spacer(minLength: 0)
          controls(proxy: proxy)
        }
        VStack(alignment: .leading, spacing: 16) {
          title
          FlowLayout(spacing: 8) { controls(proxy: proxy) }
        }
      }
      if store.mode.showsTabs {
        SegmentedPills(
          "Visão de agentes",
          items: [
            .init(id: AgentsTab.tasks, label: "Tarefas"),
            .init(id: AgentsTab.sessions, label: "Sessões"),
          ],
          selection: Binding(get: { store.query.tab }, set: { store.setTab($0) }))
      }
    }
  }

  private var title: some View {
    Text(store.mode.title)
      .typeRole(.heading)
      .foregroundStyle(theme.ink)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private func controls(proxy: ScrollViewProxy) -> some View {
    HStack(spacing: 8) {
      waitingButton(proxy: proxy)
      AgentsAlertsToggle(store: store)
      Button {
        Task { await store.loadBoard() }
      } label: {
        Label("Atualizar", systemImage: "arrow.clockwise")
      }
      .pillButtonStyle(.outline, size: .small)
      .accessibilityLabel("Atualizar agentes")
      .keyboardShortcut("r", modifiers: .command)
      searchButton
      AgentsFilterMenu(store: store)
    }
  }

  /// "N aguardando você": jumps to the first card that needs the user.
  @ViewBuilder private func waitingButton(proxy: ScrollViewProxy) -> some View {
    let waiting = store.waitingOnYou
    if !waiting.isEmpty, store.query.tab == .tasks {
      Button {
        guard let first = waiting.first else { return }
        withAnimation { proxy.scrollTo(first.id, anchor: .center) }
        focusedCard = first.id
      } label: {
        HStack(spacing: 6) {
          Circle().fill(theme.danger).frame(width: 6, height: 6).accessibilityHidden(true)
          Text("\(waiting.count) aguardando você").font(.daily(size: 12, weight: .semibold))
        }
        .foregroundStyle(theme.danger)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.dangerTint, in: .capsule)
        .contentShape(.capsule)
      }
      .buttonStyle(.plain)
      .help("Ir para a primeira tarefa que precisa de você")
    }
  }

  /// Search behind an icon, with a dot while a search is on (`BoardSearch`).
  private var searchButton: some View {
    Button {
      searchPresented.toggle()
    } label: {
      Label("Buscar tarefas", systemImage: "magnifyingglass")
    }
    .iconButtonStyle(variant: .outline, isActive: searchPresented)
    .help("Buscar tarefas")
    .accessibilityLabel("Buscar tarefas")
    .keyboardShortcut("f", modifiers: .command)
    .overlay(alignment: .topTrailing) {
      if !store.query.search.isEmpty {
        Circle().fill(theme.brand).frame(width: 10, height: 10).offset(x: 2, y: -2)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .popover(isPresented: $searchPresented, arrowEdge: .bottom) {
      SearchField(
        text: Binding(get: { store.searchText }, set: { store.setSearchText($0) }),
        label: "Buscar tarefas",
        placeholder: "Buscar tarefa…"
      )
      .frame(width: 300)
      .padding(8)
    }
  }

  // MARK: - Board

  @ViewBuilder private func board(now: Date) -> some View {
    if let error = store.error {
      ErrorState(
        store.board == nil ? "Não foi possível carregar os agentes" : "Exibindo a última atualização recebida",
        description: error
      ) {
        Task { await store.loadBoard() }
      }
    }
    if store.board == nil {
      if store.error == nil { LoadingState("Carregando seu workspace…") }
    } else if store.query.tab == .sessions {
      AgentSessionGrid(sessions: store.sessions, now: now) { store.showSession($0) }
    } else {
      let tasks = store.tasks
      if tasks.isEmpty {
        let text = AgentsLogic.emptyBoardText(store.query)
        EmptyState(text.title, description: text.description, systemImage: "rectangle.split.3x1") {
          Button("Configurar acesso") { navigator.open(.access) }
            .pillButtonStyle()
        }
      }
      AgentKanbanView(
        tasks: tasks,
        status: store.query.status,
        progress: store.progress,
        board: store.board,
        showFinished: $store.showFinished,
        now: now,
        focusedCard: $focusedCard,
        open: { store.openTask($0) })
    }
    if store.board != nil { pagination }
  }

  /// "Próxima página" / "Primeira página" (`AgentBoard.tsx:78`).
  @ViewBuilder private var pagination: some View {
    let next = store.nextCursor
    if next != nil || store.query.cursor != nil {
      HStack(spacing: 8) {
        if next != nil {
          Text("Mais resultados disponíveis; esta página não representa todo o workspace.")
            .font(.daily(size: 12))
            .foregroundStyle(theme.inkMid)
        }
        Spacer()
        if store.query.cursor != nil {
          Button("Primeira página") { store.setCursor(nil) }
            .pillButtonStyle(.outline, size: .small)
        }
        if let next {
          Button("Próxima página") { store.setCursor(next) }
            .pillButtonStyle(.outline, size: .small)
        }
      }
    }
  }
}

#Preview("Kanban") {
  AgentsScreen(store: AgentsPreview.store(mode: .kanban), navigator: AppNavigator())
    .frame(width: 1100, height: 760)
}

#Preview("Agentes") {
  AgentsScreen(store: AgentsPreview.store(), navigator: AppNavigator())
    .frame(width: 1100, height: 760)
}
