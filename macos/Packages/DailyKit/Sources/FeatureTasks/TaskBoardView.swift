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
  /// The tab shown on a narrow board.
  @State private var active: BoardColumn = .todo
  /// Wide until measured: the first frame of a wide board should not flash tabs.
  @State private var width: CGFloat = BoardTabs.breakpoint
  @FocusState private var focusedNote: String?
  /// A note moved by a button is drawn again in its new lane and the focus
  /// went with the old one. This is where it lands (`TaskBoard.tsx:344-380`).
  @State private var pendingFocus: PendingFocus?

  private struct PendingFocus: Equatable {
    let id: String
    let to: BoardColumn
  }

  var body: some View {
    let columns = TaskBoard.byColumn(tasks)
    VStack(alignment: .leading, spacing: 12) {
      if BoardTabs.usesTabs(width: width) {
        SegmentedPills(
          "Colunas do quadro",
          items: BoardColumn.allCases.map { .init(id: $0, label: $0.label, count: columns[$0]?.count ?? 0) },
          selection: $active,
          style: .toggle
        )
      }
      HStack(alignment: .top, spacing: 16) {
        ForEach(BoardTabs.columns(width: width, active: active)) { column in
          lane(column, list: columns[column] ?? [])
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onChange(of: tasks) { landPendingFocus() }
    .onChange(of: showAllDone) { landPendingFocus() }
    .onChange(of: active) { landPendingFocus() }
  }

  private func lane(_ column: BoardColumn, list: [TodoTask]) -> some View {
    let shown = column == .done && !showAllDone ? Array(list.prefix(TaskBoard.doneLimit)) : list
    let over = targeted == column
    // `.board-lane` (`globals.css:1316-1368`).
    return VStack(alignment: .leading, spacing: 12) {
      laneTitle(column, count: list.count)

      if list.isEmpty {
        Text(column == .done ? "Arraste uma nota para cá." : "Arraste uma nota para cá ou adicione.")
          .font(.daily(size: 14))
          .foregroundStyle(theme.inkDim)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
          .padding(.horizontal, 8)
      } else {
        VStack(alignment: .leading, spacing: theme.metrics.boardNoteSpacing) {
          ForEach(shown) { task in
            NoteCard(
              task: task, overdue: TaskGrouping.isOverdue(task, today: today), store: store, actions: actions,
              focusedNote: $focusedNote, move: moveKeepingFocus
            )
            .modifier(RevealRing(taskID: task.id))
          }
        }
        // Room for the pin's head, which stands above the first note.
        .padding(.top, 28)
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
    .padding(EdgeInsets(top: 12, leading: 12, bottom: 16, trailing: 12))
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(over ? theme.brandTint : theme.lineSoft.opacity(0.35), in: .rect(cornerRadius: Radius.large))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.large)
        .strokeBorder(over ? theme.brandEdge : theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .dropDestination(for: FocusSource.self) { items, _ in
      guard let source = items.first, source.kind == .task, let task = store.task(id: source.ref) else {
        return false
      }
      // A drop needs no focus work: the pointer already knows where it went.
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

  /// `.board-lane-title` and `.board-lane-count`.
  private func laneTitle(_ column: BoardColumn, count: Int) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(column.label)
        .font(.daily(size: 13, weight: .semibold))
        .tracking(13 * 0.02)
        .foregroundStyle(theme.inkMid)
      Text("\(count)")
        .font(.daily(size: 13, weight: .medium).monospacedDigit())
        .foregroundStyle(theme.inkMid)
        .padding(.horizontal, 7)
        .frame(minWidth: 24)
        .background(theme.neutralTint, in: .capsule)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(column.label), \(count) \(count == 1 ? "tarefa" : "tarefas")")
    .accessibilityAddTraits(.isHeader)
  }

  /// A move by button, menu or ⌘←/⌘→: the note's new lane is the one on
  /// screen afterwards, and the focus follows it there. The narrow board
  /// changes tab only once the server took the move; a refused one puts the
  /// focus back on the note, in the lane it never left.
  private func moveKeepingFocus(_ task: TodoTask, _ to: BoardColumn) {
    pendingFocus = PendingFocus(id: task.id, to: to)
    Task {
      let moved = await store.move(task, to: to)
      active = BoardTabs.tab(afterMoveTo: to, moved: moved, current: active)
      guard !moved else { return }
      let wasPending = pendingFocus?.id == task.id
      if wasPending { pendingFocus = nil }
      // The rollback redraws the note in its old lane; the focus goes back to
      // it unless the person has moved on to something else meanwhile.
      if wasPending || focusedNote == nil || focusedNote == task.id { focusedNote = task.id }
    }
  }

  private func landPendingFocus() {
    guard let pending = pendingFocus else { return }
    guard let task = tasks.first(where: { $0.id == pending.id }) else {
      pendingFocus = nil
      return
    }
    guard TaskBoard.column(of: task) == pending.to else { return }
    // A narrow board draws the new lane once its tab is chosen.
    guard BoardTabs.columns(width: width, active: active).contains(pending.to) else { return }
    if pending.to == .done, !showAllDone,
      !(TaskBoard.byColumn(tasks)[.done] ?? []).prefix(TaskBoard.doneLimit).contains(where: { $0.id == task.id })
    {
      // Past the first notes of "Feito": show them all so the focus has somewhere to go.
      showAllDone = true
      return
    }
    pendingFocus = nil
    focusedNote = task.id
  }
}

/// One post-it (`NoteCard`, `TaskBoard.tsx:69-235`).
struct NoteCard: View {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let task: TodoTask
  let overdue: Bool
  let store: TasksStore
  let actions: TaskActions
  var focusedNote: FocusState<String?>.Binding
  /// A move that keeps the keyboard focus on the note.
  let move: (TodoTask, BoardColumn) -> Void
  @State private var checklistOpen = false
  @State private var addingSubtask = false
  @State private var coloursOpen = false
  @State private var hovering = false

  /// `--curl`.
  private static let curlSize: CGFloat = 22

  private var inks: PostitInks { PostitInks(ink: theme.postitInk, scheme: scheme) }

  var body: some View {
    let curls = TaskBoard.curls(task.id)
    let lifted = hovering && !reduceMotion
    // The hover lift straightens the paper and raises it; under reduced
    // motion it stays put and only the shadow deepens (`globals.css:1444-1458`).
    paper(curls: curls, deepShadow: hovering)
      .rotationEffect(.degrees(lifted ? 0 : TaskBoard.tilt(task.id)))
      .offset(y: lifted ? -3 : 0)
      // Outside the rotation: only the paper tilts, the pin stays upright with
      // its needle in the top edge (`.postit-pin`, top -27px).
      .overlay(alignment: .top) {
        PushPinView(color: TaskBoard.pin(of: task), shape: TaskBoard.pinShape(of: task))
          .offset(y: -27 + (lifted ? -3 : 0))
          .allowsHitTesting(false)
      }
      .animation(Motion.ease(Motion.standard, reduceMotion: reduceMotion), value: hovering)
      .onHover { hovering = $0 }
      .contextMenu {
        TaskMenuItems(
          task: task, actions: menuActions,
          startAddingSubtask: startAddingSubtask, openColours: { coloursOpen = true })
      }
      // Typing in the subtask field inside a draggable note would start a drag
      // as soon as text is selected with the mouse.
      .draggableIfPresent(addingSubtask ? nil : FocusSource(kind: .task, ref: task.id, title: task.title))
      .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
        // ⌘← / ⌘→ move the focused note one column, like the buttons.
        guard press.modifiers.contains(.command) else { return .ignored }
        let neighbours = TaskBoard.column(of: task).neighbours
        let target = press.key == .leftArrow ? neighbours.previous : neighbours.next
        guard let target else { return .ignored }
        move(task, target)
        return .handled
      }
      .accessibilityElement(children: .contain)
  }

  /// The menu's "Mover para" keeps the focus too (`moveTakesFocus`).
  private var menuActions: TaskActions {
    var copy = actions
    copy.move = move
    return copy
  }

  private func paper(curls: Bool, deepShadow: Bool) -> some View {
    let shape = NotePaperShape(curl: curls ? Self.curlSize : 0)
    let paperColor = theme.postitPaper(TaskBoard.paper(of: task).rawValue) ?? theme.surface2
    return content(curls: curls)
      .padding(theme.metrics.notePadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        shape.fill(paperColor)
          .shadow(color: inks.drop, radius: 0, x: deepShadow ? 6 : 4, y: deepShadow ? 8 : 5)
          .overlay { shape.stroke(inks.outline, lineWidth: 1.5) }
          .overlay(alignment: .bottomTrailing) {
            if curls { CurlFlap(paper: paperColor, inks: inks).frame(width: Self.curlSize, height: Self.curlSize) }
          }
      }
  }

  private func content(curls: Bool) -> some View {
    let neighbours = TaskBoard.column(of: task).neighbours
    return VStack(alignment: .leading, spacing: theme.metrics.noteSpacing) {
      HStack(alignment: .top, spacing: 4) {
        Button {
          actions.open(task)
        } label: {
          // Only the title is handwritten (`.postit-title`, `globals.css:1661-1677`).
          Text(task.title)
            .font(.dailyHand(size: 17))
            .lineLimit(4)
            .strikethrough(task.completed, color: inks.mid)
            .foregroundStyle(theme.postitInk)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused(focusedNote, equals: task.id)
        TaskActionsMenu(
          task: task, actions: menuActions, coloursOpen: $coloursOpen,
          startAddingSubtask: startAddingSubtask, tint: inks.mid)
      }

      if task.priority != .normal || !task.recur.isEmpty || !task.due.isEmpty || !task.subtasks.isEmpty {
        meta
      }

      if checklistOpen {
        SubtaskListView(task: task, store: store, adding: $addingSubtask, ink: theme.postitInk)
          .padding(.top, 5.6)
          .overlay(alignment: .top) { DashedRule(color: theme.postitInk.opacity(0.18)) }
      }

      // Dragging is pointer-only; these are the same moves for the keyboard
      // and VoiceOver (`.postit-moves`).
      HStack(spacing: 8) {
        if let previous = neighbours.previous {
          Button {
            move(task, previous)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "arrow.left").accessibilityHidden(true)
              Text(previous.label)
            }
          }
          .buttonStyle(PaperButtonStyle(inks: inks))
          .accessibilityLabel("mover \(task.title) para \(previous.label)")
        }
        Spacer(minLength: 0)
        if let next = neighbours.next {
          Button {
            move(task, next)
          } label: {
            HStack(spacing: 4) {
              Text(next.label)
              Image(systemName: "arrow.right").accessibilityHidden(true)
            }
          }
          .buttonStyle(PaperButtonStyle(inks: inks))
          .accessibilityLabel("mover \(task.title) para \(next.label)")
        }
      }
      .font(.daily(size: 12))
      .padding(.top, 5.6)
      // The flap covers the corner, where the forward button sits.
      .padding(.trailing, curls ? Self.curlSize : 0)
      .overlay(alignment: .top) { DashedRule(color: theme.postitInk.opacity(0.18)) }
    }
    .opacity(task.completed ? 0.85 : 1)
  }

  /// `.postit-meta`: tags, due date and the checklist's progress.
  private var meta: some View {
    FlowLayout(spacing: 8) {
      if task.priority != .normal {
        tag(
          "\(task.priority == .high ? StatusGlyph.alert.rawValue : StatusGlyph.idle.rawValue) "
            + TaskText.priorityLabel(task.priority))
      }
      if !task.recur.isEmpty { tag("repete").help("tarefa recorrente") }
      if !task.due.isEmpty { due }
      if !task.subtasks.isEmpty { progress }
    }
    .font(.daily(size: 12))
    .foregroundStyle(inks.mid)
  }

  /// `.postit-tag`: an ink outline, no fill.
  private func tag(_ text: String) -> some View {
    Text(text)
      .padding(.horizontal, 7)
      .overlay { Capsule().strokeBorder(theme.postitInk.opacity(0.3)) }
  }

  /// `.postit-due`: late is said with the glyph, the weight and a darker warning ink.
  private var due: some View {
    HStack(spacing: 4) {
      if overdue { Text(StatusGlyph.alert.rawValue).accessibilityHidden(true) }
      Text(TaskText.formatDue(task.due, time: task.time))
    }
    .font(.daily(size: 12, weight: overdue ? .semibold : .regular).monospacedDigit())
    .foregroundStyle(overdue ? inks.overdue : inks.mid)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel((overdue ? "atrasada, prazo " : "prazo ") + TaskText.formatDue(task.due, time: task.time))
  }

  /// `.postit-progress`: a 36×4 bar and the count, opening the checklist.
  private var progress: some View {
    let done = task.subtasks.filter(\.completed).count
    let total = task.subtasks.count
    return Button {
      checklistOpen.toggle()
      addingSubtask = false
    } label: {
      HStack(spacing: 6) {
        Capsule()
          .fill(theme.postitInk.opacity(0.15))
          .frame(width: 36, height: 4)
          .overlay(alignment: .leading) {
            Capsule().fill(inks.mid).frame(width: 36 * CGFloat(done) / CGFloat(max(total, 1)))
          }
          .accessibilityHidden(true)
        Text("\(done)/\(total)").monospacedDigit()
      }
    }
    .buttonStyle(PaperButtonStyle(inks: inks, isOn: checklistOpen))
    .accessibilityLabel("subtarefas de \(task.title): \(done) de \(total) concluídas")
    .accessibilityValue(checklistOpen ? "expandido" : "recolhido")
  }

  private func startAddingSubtask() {
    checklistOpen = true
    addingSubtask = true
  }
}

/// The note's outline: 2pt corners, and with a curl the bottom-right
/// triangle cut away, as the web's mask does (`globals.css:1624-1640`).
struct NotePaperShape: Shape {
  let curl: CGFloat
  private let radius: CGFloat = 2

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
      radius: radius)
    if curl > 0 {
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - curl))
      path.addLine(to: CGPoint(x: rect.maxX - curl, y: rect.maxY))
    } else {
      path.addArc(
        tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
        radius: radius)
    }
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY),
      radius: radius)
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
      radius: radius)
    path.closeSubpath()
    return path
  }
}

/// The folded flap: the back of the paper, a shade darker, over the upper-left
/// half of the corner square, with an ink line on the fold.
struct CurlFlap: View {
  let paper: Color
  let inks: PostitInks

  var body: some View {
    let flap = FlapTriangle()
    flap.fill(paper)
      .overlay { flap.fill(inks.ink.opacity(0.1)) }
      .overlay { FoldLine().stroke(inks.outline, lineWidth: 1.5) }
      .accessibilityHidden(true)
  }

  private struct FlapTriangle: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.closeSubpath()
      return path
    }
  }

  private struct FoldLine: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      return path
    }
  }
}

/// The dashed ink line above the checklist and the move buttons.
struct DashedRule: View {
  let color: Color

  var body: some View {
    Rule()
      .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      .frame(height: 1)
      .accessibilityHidden(true)
  }

  private struct Rule: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      return path
    }
  }
}

/// A control drawn on the paper (`.postit-move`, `.postit-progress`): the
/// app's grey hover would smudge the pastel, so the wash is the note's ink.
struct PaperButtonStyle: ButtonStyle {
  let inks: PostitInks
  var isOn = false

  func makeBody(configuration: Configuration) -> some View {
    PaperButtonBody(configuration: configuration, inks: inks, isOn: isOn)
  }

  private struct PaperButtonBody: View {
    let configuration: Configuration
    let inks: PostitInks
    let isOn: Bool
    @State private var hovering = false

    var body: some View {
      let highlighted = hovering || isOn || configuration.isPressed
      configuration.label
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(highlighted ? inks.ink : inks.mid)
        .background(highlighted ? inks.wash : .clear, in: .capsule)
        .contentShape(.capsule)
        .onHover { hovering = $0 }
    }
  }
}

/// "+ Adicionar" at the foot of a column. Return creates and keeps the field
/// open, because notes usually come in a batch; Escape closes it and puts the
/// focus back on "Adicionar" (`AddNote`, `TaskBoard.tsx:249-330`).
struct AddNoteField: View {
  let column: BoardColumn
  let store: TasksStore
  @State private var open = false
  @State private var title = ""
  @State private var saving = false
  @State private var returnFocus = false
  @FocusState private var focus: Field?

  private enum Field: Hashable {
    case input, opener
  }

  var body: some View {
    Group {
      if open {
        TextField("nova tarefa em \(column.label)", text: $title, prompt: Text("Título, e Enter para adicionar"))
          .textFieldStyle(.roundedBorder)
          .focused($focus, equals: .input)
          .accessibilityLabel("nova tarefa em \(column.label)")
          .onAppear { focus = .input }
          .onSubmit(submit)
          .onChange(of: title) { _, value in
            let clipped = TaskDraft.clipped(value)
            if clipped != value { title = clipped }
          }
          .onChange(of: focus) { _, now in
            // Leaving an empty field closes it; one with text stays, so a stray
            // click does not throw away what was typed.
            if now != .input, title.trimmingCharacters(in: .whitespaces).isEmpty, !saving { close(withFocus: false) }
          }
          .onKeyPress(.escape) {
            close(withFocus: true)
            return .handled
          }
          .disabled(saving)
      } else {
        Button {
          open = true
        } label: {
          Label("Adicionar", systemImage: "plus")
        }
        .pillButtonStyle(.ghost, size: .small)
        .focused($focus, equals: .opener)
        .accessibilityLabel("adicionar tarefa em \(column.label)")
      }
    }
    .onChange(of: open) { _, isOpen in
      guard !isOpen, returnFocus else { return }
      returnFocus = false
      focus = .opener
    }
  }

  private func close(withFocus: Bool) {
    returnFocus = withFocus
    title = ""
    open = false
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
      focus = .input
    }
  }
}
