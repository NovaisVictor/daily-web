import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The tasks module: list and board, filters, the task form and "agendar foco"
/// (`components/TasksPanel.tsx`).
public struct TasksScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: TasksStore
  private let environment: AppEnvironment

  @State private var editing: Editing?
  @State private var focusRequest: FocusRequest?
  @State private var confirm: ConfirmRequest?
  @State private var addingSubtaskFor: String?

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
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("Nova tarefa")
        .help("Nova tarefa (⌘N)")
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
      }
    } else {
      LoadingState()
    }
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

#Preview("Tarefas") {
  TasksScreen(environment: .preview(state: TasksPreviewData.state))
    .frame(width: 1000, height: 700)
}
