import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The tasks module: list and board, filters, the task form and "agendar foco"
/// (`components/TasksPanel.tsx`).
public struct TasksScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: TasksStore
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let environment: AppEnvironment

  @State private var editing: Editing?
  @State private var focusRequest: FocusRequest?
  @State private var confirm: ConfirmRequest?
  @State private var addingSubtaskFor: String?
  /// The task just revealed from outside, drawn with a ring for a moment.
  @State private var revealed: String?

  public init(environment: AppEnvironment) {
    self.environment = environment
    _store = State(initialValue: TasksStore(environment: environment))
  }

  private enum Editing: Identifiable {
    case new
    case task(TodoTask)

    var id: String {
      switch self {
      case .new: "new"
      case .task(let task): task.id
      }
    }

    var task: TodoTask? {
      if case .task(let task) = self { return task }
      return nil
    }
  }

  private struct FocusRequest: Identifiable {
    let id = UUID()
    let source: FocusSource
  }

  public var body: some View {
    let today = store.now()
    VStack(alignment: .leading, spacing: 16) {
      header(today: today)
      filters(today: today)
      ActiveFiltersRow(filters: store.activeFilters, remove: store.clear, clearAll: store.clearFilters)
      content(today: today)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .sheet(item: $editing) { target in
      TaskFormSheet(task: target.task, store: store, now: today)
    }
    .sheet(item: $focusRequest) { request in
      FocusScheduleSheet(
        source: request.source, calendars: store.calendars, serverURL: environment.session.serverURL, store: store)
    }
    .confirmDialog($confirm)
  }

  // MARK: - Header and filters

  private func header(today: Date) -> some View {
    let count = store.activeFilters.isEmpty ? nil : "\(store.visibleCount(today: today)) de \(store.all.count)"
    return SectionHeader("Tarefas", count: count) {
      HStack(spacing: 8) {
        Picker(
          "Visualização das tarefas",
          selection: Binding(get: { store.view }, set: { next in Task { await store.choose(next) } })
        ) {
          Label("Lista", systemImage: "list.bullet").tag(TasksView.list)
          Label("Quadro", systemImage: "note.text").tag(TasksView.board)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Visualização das tarefas")
        Button {
          editing = .new
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderedProminent)
        // ⌘T, not the web-like ⌘N: on the Mac ⌘N is "Nova janela" (File menu),
        // ⇧⌘N "Abrir em nova janela" and ⌥⌘N the notes tree's new folder.
        .keyboardShortcut("t", modifiers: .command)
        .accessibilityLabel("Nova tarefa")
        .help("Nova tarefa (⌘T)")
      }
    }
  }

  private func filters(today: Date) -> some View {
    FilterBar("Filtrar tarefas") {
      SearchField(text: $store.query, label: "buscar tarefas", placeholder: "título")
      Chip("Alta", isOn: store.priorityFilter == .high) { store.togglePriority(.high) }
      Chip("Baixa", isOn: store.priorityFilter == .low) { store.togglePriority(.low) }
      if store.view == .list {
        Chip("Concluídas", isOn: store.showCompleted) { store.showCompleted.toggle() }
      }
      ForEach(store.availableWindows(today: today), id: \.self) { key in
        Chip(key.chipLabel, isOn: store.window == key) { store.toggleWindow(key) }
      }
    }
  }

  // MARK: - Content

  @ViewBuilder
  private func content(today: Date) -> some View {
    if let panel = store.panel {
      if let message = panel.error { PanelError(message) }
      if let message = store.actionError { PanelError(message) }
      let all = store.all
      if store.view == .list, all.isEmpty, panel.error == nil {
        EmptyState("Nenhuma tarefa por aqui. Crie a primeira.") {
          Button("Nova tarefa", systemImage: "plus") { editing = .new }
            .buttonStyle(.borderedProminent)
        }
      } else if !all.isEmpty, store.visibleCount(today: today) == 0 {
        EmptyState("Nenhuma tarefa com esses filtros.")
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            // The board needs no empty state of its own: its empty columns say
            // where a note goes, and each has its own "Adicionar".
            if store.view == .board {
              TaskBoardView(tasks: store.boardTasks(today: today), today: today, store: store, actions: actions)
                .padding(.top, 8)
            } else {
              TaskListView(
                groups: store.listGroups(today: today), today: today, store: store, actions: actions,
                addingSubtaskFor: $addingSubtaskFor)
            }
          }
          .onAppear { revealPendingTask(proxy) }
          .onChange(of: environment.navigator.pending) { revealPendingTask(proxy) }
          .onChange(of: store.all) { revealPendingTask(proxy) }
          .environment(\.revealedTaskID, revealed)
          .task(id: revealed) { await fadeRevealed() }
        }
      }
    } else {
      LoadingState()
    }
  }

  /// A task chosen elsewhere (the menu bar) scrolls into view and is marked
  /// for a moment. A task the filters hide, or one gone, finishes the request
  /// too: it is never shown, and waiting would only move the list later.
  private func revealPendingTask(_ proxy: ScrollViewProxy) {
    let route = AppRoute.module(.tasks)
    // Only the main window takes the request; it is the one the navigator moved.
    guard isPrimaryWindow, let id = environment.navigator.pendingItem(for: route), store.panel?.data != nil
    else { return }
    environment.navigator.finishPendingItem(id, for: route)
    guard store.all.contains(where: { $0.id == id }) else { return }
    withAnimation { proxy.scrollTo(id, anchor: .center) }
    revealed = id
  }

  /// Takes the reveal mark away after a moment.
  private func fadeRevealed() async {
    guard revealed != nil else { return }
    do {
      try await Task.sleep(for: .seconds(2))
    } catch {
      // Cancelled by a newer reveal or by leaving the screen; either drops this mark.
      return
    }
    revealed = nil
  }

  private var actions: TaskActions {
    let store = self.store
    return TaskActions(
      open: { editing = .task($0) },
      toggleComplete: { task in Task { await store.toggleComplete(task) } },
      scheduleFocus: store.focusEnabled
        ? { task in focusRequest = FocusRequest(source: FocusSource(kind: .task, ref: task.id, title: task.title)) }
        : nil,
      move: { task, column in Task { await store.move(task, to: column) } },
      changeStyle: { task, patch in Task { await store.changeStyle(task, patch) } },
      delete: { task in askDelete(task) }
    )
  }

  /// Deleting asks first: with Microsoft To Do behind the panel there is no trash.
  private func askDelete(_ task: TodoTask) {
    confirm = ConfirmRequest(
      title: "Apagar a tarefa?",
      message: "\"\(task.title)\" será removida. Isso não tem volta.",
      confirmLabel: "Apagar",
      destructive: true,
      onConfirm: { Task { await store.delete(task) } }
    )
  }
}

extension EnvironmentValues {
  /// The task the screen just scrolled to for the menu bar; rows and notes ring it.
  @Entry var revealedTaskID: String?
}

/// The scroll target of a task, ringed while it is the one just revealed.
struct RevealRing: ViewModifier {
  let taskID: String
  @Environment(\.revealedTaskID) private var revealed
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    content
      .id(taskID)
      .overlay {
        if revealed == taskID {
          RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.brand, lineWidth: 2)
            .allowsHitTesting(false)
        }
      }
  }
}

#Preview("Tarefas") {
  TasksScreen(environment: .preview(state: TasksPreviewData.state))
    .frame(width: 1000, height: 700)
}
