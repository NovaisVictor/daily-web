import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Every action on one task, the same in the list and on the board
/// (`components/tasks/TaskActionsMenu.tsx`).
struct TaskActions {
  var open: (TodoTask) -> Void
  var toggleComplete: (TodoTask) -> Void
  /// Nil when no calendar is connected, as `focus.enabled` on the web.
  var scheduleFocus: ((TodoTask) -> Void)?
  var move: (TodoTask, BoardColumn) -> Void
  var changeStyle: (TodoTask, NoteStylePatch) -> Void
  var delete: (TodoTask) -> Void

  /// The drag payload for the agenda; nil for a finished task or without calendars.
  func focusSource(_ task: TodoTask) -> FocusSource? {
    guard scheduleFocus != nil, !task.completed else { return nil }
    return FocusSource(kind: .task, ref: task.id, title: task.title)
  }
}

/// The items, shared by the "…" button and the context menu.
struct TaskMenuItems: View {
  let task: TodoTask
  let actions: TaskActions
  let startAddingSubtask: () -> Void
  let openColours: () -> Void

  var body: some View {
    Button("Editar", systemImage: "pencil") { actions.open(task) }
    Button("Adicionar subtarefa", systemImage: "text.badge.plus", action: startAddingSubtask)
    if let schedule = actions.scheduleFocus, !task.completed {
      Button("Agendar foco", systemImage: "calendar.badge.plus") { schedule(task) }
    }
    Button("Cor da nota…", systemImage: "paintpalette", action: openColours)
    Divider()
    Picker(
      "Mover para",
      selection: Binding(
        get: { TaskBoard.column(of: task) },
        set: { to in
          if to != TaskBoard.column(of: task) { actions.move(task, to) }
        })
    ) {
      ForEach(BoardColumn.allCases) { column in
        Text(column.label).tag(column)
      }
    }
    .pickerStyle(.inline)
    Divider()
    Button("Apagar", systemImage: "trash", role: .destructive) { actions.delete(task) }
  }
}

/// The "…" button. The colours open in a popover beside it rather than inside
/// the menu, which would close on every pick.
struct TaskActionsMenu: View {
  @Environment(\.theme) private var theme
  let task: TodoTask
  let actions: TaskActions
  @Binding var coloursOpen: Bool
  let startAddingSubtask: () -> Void
  var tint: Color?

  var body: some View {
    Menu {
      TaskMenuItems(
        task: task, actions: actions, startAddingSubtask: startAddingSubtask, openColours: { coloursOpen = true })
    } label: {
      Image(systemName: "ellipsis")
        .foregroundStyle(tint ?? theme.inkMid)
        .frame(width: 24, height: 24)
        .contentShape(.rect)
    }
    .menuStyle(.button)
    .buttonStyle(.borderless)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel("ações de \(task.title)")
    .help("ações de \(task.title)")
    .popover(isPresented: $coloursOpen, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Cor da nota").font(.system(size: 14, weight: .medium)).foregroundStyle(theme.ink)
        NoteColourPicker(
          paper: task.paper,
          pin: task.pin,
          pinShape: task.pinShape,
          automaticPaper: TaskBoard.derivedPaper(completed: task.completed, priority: task.priority)
        ) { patch in
          actions.changeStyle(task, patch)
        }
      }
      .padding(16)
      .frame(width: 320)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("cor da nota de \(task.title)")
    }
  }
}

/// Paper, pin colour and pin shape of one note
/// (`components/tasks/NoteColourPicker.tsx`). The board saves each pick at
/// once; the form keeps them until "Salvar".
struct NoteColourPicker: View {
  @Environment(\.theme) private var theme
  let paper: NotePaper?
  let pin: PinColor?
  let pinShape: PinShape?
  /// What "Automático" stands for right now, from priority and completion.
  let automaticPaper: NotePaper
  /// Only the choice that changed.
  let onChange: (NoteStylePatch) -> Void

  private static let clashHint = "pode sumir neste papel"

  var body: some View {
    let shownPaper = paper ?? automaticPaper
    let clashing = pin.flatMap { TaskBoard.clashes($0, on: shownPaper) ? $0 : nil }
    VStack(alignment: .leading, spacing: 16) {
      group("Papel") {
        swatch(label: "Papel automático (\(TaskBoard.paperLabel(automaticPaper)))", selected: paper == nil) {
          onChange(NoteStylePatch(paper: .some(nil)))
        } content: {
          paperCircle(automaticPaper, automatic: true)
        }
        ForEach(TaskBoard.papers, id: \.self) { option in
          swatch(label: "Papel \(TaskBoard.paperLabel(option))", selected: paper == option) {
            onChange(NoteStylePatch(paper: .some(option)))
          } content: {
            paperCircle(option, automatic: false)
          }
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        group("Alfinete") {
          swatch(label: "Alfinete automático", selected: pin == nil) {
            onChange(NoteStylePatch(pin: .some(nil)))
          } content: {
            Circle().strokeBorder(theme.lineStrong).overlay { Text("A").font(.system(size: 11, weight: .semibold)) }
          }
          ForEach(TaskBoard.pins, id: \.self) { option in
            let clashes = TaskBoard.clashes(option, on: shownPaper)
            swatch(
              label: "Alfinete \(TaskBoard.pinLabel(option))" + (clashes ? ", \(Self.clashHint)" : ""),
              selected: pin == option
            ) {
              onChange(NoteStylePatch(pin: .some(option)))
            } content: {
              Circle().fill(PinPalette.color(option))
                .overlay { if clashes { Circle().strokeBorder(theme.warning, style: .init(lineWidth: 2, dash: [2])) } }
            }
          }
        }
        Text(
          clashing.map { "O alfinete \(TaskBoard.pinLabel($0)) \(Self.clashHint)." }
            ?? "Automático evita o alfinete que some no papel."
        )
        .typeRole(.caption)
        .foregroundStyle(clashing == nil ? theme.inkDim : theme.warning)
      }
      group("Formato do alfinete") {
        ForEach(TaskBoard.shapes, id: \.self) { shape in
          // The classic pin is the default, so it stands for "no choice".
          let value: PinShape? = shape == .classic ? nil : shape
          swatch(label: "Alfinete \(TaskBoard.shapeLabel(shape))", selected: pinShape == value) {
            onChange(NoteStylePatch(pinShape: .some(value)))
          } content: {
            Circle().fill(theme.surface2).overlay { PushPinView(color: pin ?? .red, shape: shape) }
          }
        }
      }
    }
  }

  private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.system(size: 14)).foregroundStyle(theme.inkMid)
      HStack(spacing: 6) { content() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
  }

  private func paperCircle(_ paper: NotePaper, automatic: Bool) -> some View {
    Circle()
      .fill(theme.postitPaper(paper.rawValue) ?? theme.surface2)
      .overlay { Circle().strokeBorder(theme.line) }
      .overlay {
        if automatic {
          Text("A").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.postitInk)
        }
      }
  }

  private func swatch<Content: View>(
    label: String,
    selected: Bool,
    action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Button(action: action) {
      content()
        .frame(width: 26, height: 26)
        .overlay {
          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(theme.ink)
              .padding(3)
              .background(theme.surface2.opacity(0.85), in: .circle)
              .offset(x: 9, y: -9)
          }
        }
        .padding(3)
        .overlay { Circle().strokeBorder(selected ? theme.brand : .clear, lineWidth: 2) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .help(label)
  }
}
