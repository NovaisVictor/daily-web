import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Agentes e atividades" (`components/agents/AgentBoard.tsx`, workspace mode):
/// the kanban of agent tasks and the sessions, with each task's page opening
/// inside the screen.
public struct AgentsScreen: View {
  @State private var store: AgentsStore
  @State private var searchPresented = false
  /// The card "N aguardando você" moves the keyboard to (`card.focus()` in the web).
  @FocusState private var focusedCard: String?
  @Environment(\.theme) private var theme
  private let navigator: AppNavigator

  public init(environment: AppEnvironment) {
    self.init(store: AgentsStore(environment: environment), navigator: environment.navigator)
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
      store.openPendingTask(from: navigator)
    }
    .onDisappear { store.setVisible(false) }
    .onChange(of: navigator.pending) { store.openPendingTask(from: navigator) }
  }

  // MARK: - Header

  private func header(proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        Text("Agentes e atividades")
          .typeRole(.subhead)
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        waitingButton(proxy: proxy)
        Button {
          Task { await store.loadBoard() }
        } label: {
          Label("Atualizar", systemImage: "arrow.clockwise")
        }
        .accessibilityLabel("Atualizar agentes")
        .keyboardShortcut("r", modifiers: .command)
        searchButton
        AgentsFilterMenu(store: store)
      }
      .buttonStyle(.bordered)
      Picker(
        "Visão de agentes",
        selection: Binding(get: { store.query.tab }, set: { store.setTab($0) })
      ) {
        Text("Tarefas").tag(AgentsTab.tasks)
        Text("Sessões").tag(AgentsTab.sessions)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("Visão de agentes")
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
          Text("\(waiting.count) aguardando você").fontWeight(.semibold)
        }
        .foregroundStyle(theme.danger)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(theme.dangerTint, in: .capsule)
      .help("Ir para a primeira tarefa que precisa de você")
    }
  }

  /// Search behind an icon, with a dot while a search is on (`BoardSearch`).
  private var searchButton: some View {
    Button {
      searchPresented.toggle()
    } label: {
      Label("Buscar tarefas", systemImage: "magnifyingglass").labelStyle(.iconOnly)
    }
    .help("Buscar tarefas")
    .accessibilityLabel("Buscar tarefas")
    .keyboardShortcut("f", modifiers: .command)
    .overlay(alignment: .topTrailing) {
      if !store.query.search.isEmpty {
        Circle().fill(theme.brand).frame(width: 8, height: 8).offset(x: 3, y: -3).accessibilityHidden(true)
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
            .buttonStyle(.borderedProminent)
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
            .font(.system(size: 11))
            .foregroundStyle(theme.inkMid)
        }
        Spacer()
        if store.query.cursor != nil {
          Button("Primeira página") { store.setCursor(nil) }
        }
        if let next {
          Button("Próxima página") { store.setCursor(next) }
        }
      }
      .controlSize(.small)
    }
  }
}

#Preview("Agentes") {
  AgentsScreen(store: AgentsPreview.store(), navigator: AppNavigator())
    .frame(width: 1100, height: 760)
}
