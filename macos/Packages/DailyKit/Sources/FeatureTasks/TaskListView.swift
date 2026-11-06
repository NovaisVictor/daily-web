import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The list view: tasks grouped by due window (`TasksPanel.tsx`, list branch).
struct TaskListView: View {
  @Environment(\.theme) private var theme
  let groups: [TaskGroup]
  let today: Date
  let store: TasksStore
  let actions: TaskActions
  @Binding var addingSubtaskFor: String?
  /// Subtasks stay folded until asked: ten tasks of three steps would
  /// otherwise be forty rows.
  @State private var expanded: Set<String> = []

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 20) {
      ForEach(groups, id: \.key) { group in
        VStack(alignment: .leading, spacing: 8) {
          Text(group.label)
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
            .accessibilityAddTraits(.isHeader)
          VStack(spacing: 0) {
            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
              TaskRow(
                task: task,
                overdue: TaskGrouping.isOverdue(task, today: today),
                striped: index % 2 == 1,
                store: store,
                actions: actions,
                expanded: Binding(
                  get: { expanded.contains(task.id) || addingSubtaskFor == task.id },
                  set: { open in
                    if open { expanded.insert(task.id) } else { expanded.remove(task.id) }
                  }),
                adding: Binding(
                  get: { addingSubtaskFor == task.id },
                  set: { addingSubtaskFor = $0 ? task.id : nil })
              )
              .modifier(RevealRing(taskID: task.id))
            }
          }
        }
      }
    }
  }
}

struct TaskRow: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let task: TodoTask
  let overdue: Bool
  let striped: Bool
  let store: TasksStore
  let actions: TaskActions
  @Binding var expanded: Bool
  @Binding var adding: Bool
  @State private var coloursOpen = false
  @State private var hovering = false
  /// Wide until measured, so a wide list does not start wrapped.
  @State private var width = TaskRow.wrapWidth

  /// `@max-[34rem]`: below it the tags, date and counter drop to a second line,
  /// or the title is the only thing left to shrink and goes to zero.
  static let wrapWidth: CGFloat = 544

  private var hasMeta: Bool {
    task.doing || task.priority != .normal || !task.recur.isEmpty || !task.due.isEmpty || !task.subtasks.isEmpty
  }

  var body: some View {
    let narrow = width < Self.wrapWidth
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        line(narrow: narrow)
        if narrow, hasMeta {
          // Indented to start under the title: caret, gap, checkbox, gap.
          FlowLayout(spacing: 12) { metaItems }
            .padding(.leading, 64)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, theme.metrics.rowVerticalPadding)
      .background(hovering ? theme.brandTint : (striped ? theme.lineSoft.opacity(0.25) : .clear))
      .clipShape(.rect(cornerRadius: Radius.tiny))
      .onHover { hovering = $0 }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
      .contextMenu {
        TaskMenuItems(
          task: task, actions: actions, startAddingSubtask: startAddingSubtask, openColours: { coloursOpen = true })
      }
      .draggableIfPresent(actions.focusSource(task))

      if expanded || adding {
        SubtaskListView(task: task, store: store, adding: $adding)
          .padding(.leading, 44)
          .padding(.bottom, 12)
          .overlay(alignment: .leading) {
            Rectangle().fill(theme.lineSoft).frame(width: 1).padding(.leading, 28).padding(.bottom, 12)
          }
          .transition(Motion.reveal(reduceMotion: reduceMotion))
      }
      Divider().overlay(theme.lineSoft)
    }
  }

  private func line(narrow: Bool) -> some View {
    HStack(spacing: 12) {
      caret
      Toggle(
        "concluir \(task.title)",
        isOn: Binding(get: { task.completed }, set: { _ in actions.toggleComplete(task) })
      )
      .toggleStyle(.checkbox)
      // The web's `accent-brand` checkbox (`TasksPanel.tsx:558-564`).
      .tint(theme.brand)
      .labelsHidden()
      .accessibilityLabel("concluir \(task.title)")
      if let paper = task.paper {
        Circle()
          .fill(theme.postitPaper(paper.rawValue) ?? theme.surface2)
          .overlay { Circle().strokeBorder(theme.lineStrong) }
          .frame(width: 10, height: 10)
          .accessibilityLabel("nota \(TaskBoard.paperLabel(paper))")
          .help("nota \(TaskBoard.paperLabel(paper))")
      }
      Button {
        actions.open(task)
      } label: {
        Text(task.title)
          .strikethrough(task.completed)
          .foregroundStyle(task.completed ? theme.inkDim : theme.ink)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      if !narrow, hasMeta {
        HStack(spacing: 12) { metaItems }.fixedSize()
      }
      if let schedule = actions.scheduleFocus, !task.completed {
        Button {
          schedule(task)
        } label: {
          Image(systemName: "calendar.badge.plus")
        }
        .iconButtonStyle(size: .extraSmall)
        .accessibilityLabel("agendar foco para \(task.title)")
        .help("agendar foco para \(task.title)")
      }
      TaskActionsMenu(
        task: task, actions: actions, coloursOpen: $coloursOpen, startAddingSubtask: startAddingSubtask)
    }
  }

  /// Only where there is something to reveal.
  @ViewBuilder
  private var caret: some View {
    if task.subtasks.isEmpty {
      Color.clear.frame(width: 24, height: 24)
    } else {
      Button {
        Motion.animate(reduceMotion: reduceMotion) { expanded.toggle() }
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .disclosureRotation(open: expanded)
          .frame(width: 24, height: 24)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.inkDim)
      .accessibilityLabel("\(expanded ? "recolher" : "expandir") subtarefas de \(task.title)")
      .accessibilityValue(expanded ? "expandido" : "recolhido")
    }
  }

  @ViewBuilder
  private var metaItems: some View {
    // "Fazendo" is a board column, but the list shows it too: otherwise a
    // task in progress looks exactly like one nobody started.
    if task.doing { StatusPill("Fazendo", glyph: .moving, tone: .info) }
    if task.priority != .normal { PriorityPill(priority: task.priority) }
    if !task.recur.isEmpty {
      StatusPill("repete", glyph: .idle, tone: .neutral).help("tarefa recorrente")
    }
    if !task.due.isEmpty { DueLabel(task: task, overdue: overdue) }
    if !task.subtasks.isEmpty {
      Text("\(task.subtasks.filter(\.completed).count)/\(task.subtasks.count)")
        .font(.daily(size: 12).monospacedDigit())
        .foregroundStyle(theme.inkDim)
        .help("subtarefas concluídas")
        .accessibilityLabel(
          "subtarefas concluídas: \(task.subtasks.filter(\.completed).count) de \(task.subtasks.count)")
    }
  }

  private func startAddingSubtask() {
    Motion.animate(reduceMotion: reduceMotion) {
      adding = true
      expanded = true
    }
  }
}
