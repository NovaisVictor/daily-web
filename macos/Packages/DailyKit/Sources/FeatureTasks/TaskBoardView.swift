import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The tasks as notes pinned to a board (`components/tasks/TaskBoard.tsx`).
///
/// A card's drag payload is a `FocusSource`, the same one the agenda accepts,
/// so a single drag can either change column here or book focus time there.
struct TaskBoardView: View {
  @Environment(\.theme) private var theme
  let tasks: [TodoTask]
  let today: Date
  let store: TasksStore
  let actions: TaskActions
  @State private var showAllDone = false
  @State private var targeted: BoardColumn?

  var body: some View {
    let columns = TaskBoard.byColumn(tasks)
    HStack(alignment: .top, spacing: 16) {
      ForEach(BoardColumn.allCases) { column in
        lane(column, list: columns[column] ?? [])
      }
    }
  }

  private func lane(_ column: BoardColumn, list: [TodoTask]) -> some View {
    let shown = column == .done && !showAllDone ? Array(list.prefix(TaskBoard.doneLimit)) : list
    return VStack(alignment: .leading, spacing: theme.metrics.boardNoteSpacing) {
      HStack(spacing: 8) {
        Text(column.label).typeRole(.caption).foregroundStyle(theme.inkMid)
        Text("\(list.count)")
          .font(.daily(size: 12).monospacedDigit())
          .foregroundStyle(theme.inkDim)
          .accessibilityHidden(true)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(column.label), \(list.count) \(list.count == 1 ? "tarefa" : "tarefas")")
      .accessibilityAddTraits(.isHeader)

      if list.isEmpty {
        Text(column == .done ? "Arraste uma nota para cá." : "Arraste uma nota para cá ou adicione.")
          .font(.daily(size: 13))
          .foregroundStyle(theme.inkDim)
          .padding(.vertical, 8)
      } else {
        ForEach(shown) { task in
          NoteCard(task: task, overdue: TaskGrouping.isOverdue(task, today: today), store: store, actions: actions)
            .modifier(RevealRing(taskID: task.id))
        }
      }
      if column == .done, list.count > TaskBoard.doneLimit {
        Button(showAllDone ? "Mostrar menos" : "Mostrar todas (\(list.count))") { showAllDone.toggle() }
          .pillButtonStyle(.ghost, size: .small)
          .accessibilityValue(showAllDone ? "expandido" : "recolhido")
      }
      if column != .done {
        AddNoteField(column: column, store: store)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      targeted == column ? theme.brandTint : theme.lineSoft.opacity(0.3), in: .rect(cornerRadius: Radius.large)
    )
    .overlay {
      RoundedRectangle(cornerRadius: Radius.large)
        .strokeBorder(targeted == column ? theme.brandEdge : theme.lineSoft)
    }
    .dropDestination(for: FocusSource.self) { items, _ in
      guard let source = items.first, source.kind == .task, let task = store.task(id: source.ref) else {
        return false
      }
      actions.move(task, column)
      return true
    } isTargeted: { inside in
      if inside {
        targeted = column
      } else if targeted == column {
        targeted = nil
      }
    }
  }
}

/// One post-it.
struct NoteCard: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let task: TodoTask
  let overdue: Bool
  let store: TasksStore
  let actions: TaskActions
  @State private var checklistOpen = false
  @State private var addingSubtask = false
  @State private var coloursOpen = false

  private var ink: Color { theme.postitInk }

  var body: some View {
    let column = TaskBoard.column(of: task)
    let neighbours = column.neighbours
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 4) {
        Button {
          actions.open(task)
        } label: {
          Text(task.title)
            .font(.daily(size: 14, weight: .medium))
            .strikethrough(task.completed)
            .foregroundStyle(ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        TaskActionsMenu(
          task: task, actions: actions, coloursOpen: $coloursOpen,
          startAddingSubtask: {
            checklistOpen = true
            addingSubtask = true
          }, tint: ink.opacity(0.75))
      }

      if task.priority != .normal || !task.recur.isEmpty || !task.due.isEmpty || !task.subtasks.isEmpty {
        FlowLayout(spacing: 6) {
          if task.priority != .normal {
            tag(
              "\(task.priority == .high ? StatusGlyph.alert.rawValue : StatusGlyph.idle.rawValue) "
                + TaskText.priorityLabel(task.priority))
          }
          if !task.recur.isEmpty { tag("repete").help("tarefa recorrente") }
          if !task.due.isEmpty { DueLabel(task: task, overdue: overdue, ink: ink.opacity(0.75)) }
          if !task.subtasks.isEmpty { progress }
        }
      }

      if checklistOpen {
        SubtaskListView(task: task, store: store, adding: $addingSubtask, ink: ink)
      }

      // Dragging is pointer-only; these are the same moves for the keyboard
      // and VoiceOver.
      HStack {
        if let previous = neighbours.previous {
          Button {
            actions.move(task, previous)
          } label: {
            Label(previous.label, systemImage: "arrow.left").font(.daily(size: 12))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("mover \(task.title) para \(previous.label)")
        }
        Spacer(minLength: 0)
        if let next = neighbours.next {
          Button {
            actions.move(task, next)
          } label: {
            HStack(spacing: 4) {
              Text(next.label)
              Image(systemName: "arrow.right")
            }
            .font(.daily(size: 12))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("mover \(task.title) para \(next.label)")
        }
      }
      .foregroundStyle(ink.opacity(0.8))
    }
    .padding(theme.metrics.notePadding)
    .padding(.top, 6)
    .background(theme.postitPaper(TaskBoard.paper(of: task).rawValue) ?? theme.surface2, in: .rect(cornerRadius: 3))
    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    .overlay(alignment: .top) {
      PushPinView(color: TaskBoard.pin(of: task), shape: TaskBoard.pinShape(of: task)).offset(y: -8)
    }
    .opacity(task.completed ? 0.85 : 1)
    .rotationEffect(.degrees(reduceMotion ? 0 : TaskBoard.tilt(task.id)))
    .contextMenu {
      TaskMenuItems(
        task: task, actions: actions,
        startAddingSubtask: {
          checklistOpen = true
          addingSubtask = true
        }, openColours: { coloursOpen = true })
    }
    // Typing in the subtask field inside a draggable note would start a drag
    // as soon as text is selected with the mouse.
    .draggableIfPresent(addingSubtask ? nil : FocusSource(kind: .task, ref: task.id, title: task.title))
    .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
      // ⌘← / ⌘→ move the focused note one column, like the buttons.
      guard press.modifiers.contains(.command) else { return .ignored }
      let target = press.key == .leftArrow ? neighbours.previous : neighbours.next
      guard let target else { return .ignored }
      actions.move(task, target)
      return .handled
    }
    .accessibilityElement(children: .contain)
  }

  private func tag(_ text: String) -> some View {
    Text(text)
      .font(.daily(size: 11, weight: .medium))
      .foregroundStyle(ink.opacity(0.85))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(ink.opacity(0.08), in: .capsule)
  }

  private var progress: some View {
    let done = task.subtasks.filter(\.completed).count
    let total = task.subtasks.count
    return Button {
      checklistOpen.toggle()
      addingSubtask = false
    } label: {
      HStack(spacing: 6) {
        ProgressView(value: Double(done), total: Double(total))
          .progressViewStyle(.linear)
          .frame(width: 36)
          .tint(ink.opacity(0.7))
        Text("\(done)/\(total)").font(.daily(size: 11).monospacedDigit())
      }
      .foregroundStyle(ink.opacity(0.8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("subtarefas de \(task.title): \(done) de \(total) concluídas")
    .accessibilityValue(checklistOpen ? "expandido" : "recolhido")
  }
}

/// "+ Adicionar" at the foot of a column. Return creates and keeps the field
/// open, because notes usually come in a batch; Escape closes it.
struct AddNoteField: View {
  @Environment(\.theme) private var theme
  let column: BoardColumn
  let store: TasksStore
  @State private var open = false
  @State private var title = ""
  @State private var saving = false
  @FocusState private var focused: Bool

  var body: some View {
    if open {
      TextField("nova tarefa em \(column.label)", text: $title, prompt: Text("Título, e Enter para adicionar"))
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .accessibilityLabel("nova tarefa em \(column.label)")
        .onAppear { focused = true }
        .onSubmit(submit)
        .onChange(of: title) { _, value in
          if value.utf16.count > TaskDraft.titleLimit { title = String(value.prefix(TaskDraft.titleLimit)) }
        }
        .onChange(of: focused) { _, isFocused in
          // Leaving an empty field closes it; one with text stays, so a stray
          // click does not throw away what was typed.
          if !isFocused, title.trimmingCharacters(in: .whitespaces).isEmpty, !saving { open = false }
        }
        .onKeyPress(.escape) {
          title = ""
          open = false
          return .handled
        }
        .disabled(saving)
    } else {
      Button {
        open = true
      } label: {
        Label("Adicionar", systemImage: "plus").font(.daily(size: 13))
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.inkMid)
      .accessibilityLabel("adicionar tarefa em \(column.label)")
    }
  }

  private func submit() {
    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    // A second Return while the first is on its way would create the same note twice.
    guard !value.isEmpty, !saving else { return }
    saving = true
    Task {
      let created = await store.quickCreate(title: value, in: column)
      saving = false
      if created { title = "" }
      focused = true
    }
  }
}
