import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Create or edit a task (`components/TaskFormModal.tsx`).
struct TaskFormSheet: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let task: TodoTask?
  let store: TasksStore
  let now: Date

  @State private var draft: TaskDraft
  private let initial: TaskDraft
  @State private var titleError: String?
  /// What the last cut at `titleLimit` left, for the limit hint.
  @State private var cutTitle: String?
  @State private var error: String?
  @State private var saving = false
  @State private var deleting = false
  @State private var confirm: ConfirmRequest?
  @State private var typing = false
  @FocusState private var titleFocused: Bool
  @FocusState private var typedFocused: Bool

  init(task: TodoTask?, store: TasksStore, now: Date) {
    self.task = task
    self.store = store
    self.now = now
    let initial = TaskDraft(task: task)
    self.initial = initial
    _draft = State(initialValue: initial)
  }

  private var busy: Bool { saving || deleting }
  private var dirty: Bool { draft.isDirty(comparedTo: initial) }

  var body: some View {
    let days = TaskDraft.quickDays(now: now)
    VStack(alignment: .leading, spacing: 20) {
      Text(task == nil ? "Nova tarefa" : "Editar tarefa").typeRole(.subhead).foregroundStyle(theme.ink)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          field("Título") {
            TextField("Título", text: $draft.title, prompt: Text("O que precisa ser feito?"))
              .textFieldStyle(.roundedBorder)
              .focused($titleFocused)
              .singleLine($draft.title)
              .onChange(of: draft.title) { _, value in
                let clipped = TaskDraft.clipped(value)
                if clipped != value {
                  cutTitle = clipped
                  draft.title = clipped
                }
                titleError = nil
              }
            if TaskDraft.showsLimitHint(title: draft.title, cutTitle: cutTitle) {
              TitleLimitHint()
            }
            if let titleError {
              Text(titleError).font(.daily(size: 13)).foregroundStyle(theme.danger)
            }
          }

          field("Data") {
            FlowLayout(spacing: 8) {
              Chip("Hoje", isOn: draft.day == days.today) { draft.setDay(days.today) }
              Chip("Amanhã", isOn: draft.day == days.tomorrow) { draft.setDay(days.tomorrow) }
              Chip("Próx. semana", isOn: draft.day == days.monday && days.monday != days.tomorrow) {
                draft.setDay(days.monday)
              }
              Chip("Sem data", isOn: !draft.hasDue) { draft.setDay(nil) }
            }
            dayAndTimePickers
            typedDate
          }

          HStack(alignment: .top, spacing: 16) {
            field("Prioridade") {
              Picker("Prioridade", selection: $draft.priority) {
                ForEach(TaskDraft.priorities, id: \.self) { priority in
                  Text(TaskText.priorityLabel(priority)).tag(priority)
                }
              }
              .labelsHidden()
            }
            field("Repetição") {
              Picker(
                "Repetição",
                selection: Binding(get: { draft.effectiveRecur }, set: { draft.recur = $0 })
              ) {
                ForEach(TaskRecur.allCases) { recur in
                  Text(recur.label).tag(recur)
                }
              }
              .labelsHidden()
              .disabled(!draft.hasDue)
              if !draft.hasDue {
                Text("Defina uma data para repetir.").typeRole(.caption).foregroundStyle(theme.inkDim)
              }
            }
          }

          if task == nil {
            field("Coluna") {
              SegmentedPills(
                "Coluna",
                items: [
                  .init(id: BoardColumn.todo, label: BoardColumn.todo.label),
                  .init(id: BoardColumn.doing, label: BoardColumn.doing.label),
                ],
                selection: $draft.column,
                style: .toggle
              )
            }
          }

          field("Cor da nota") {
            NoteColourPicker(
              paper: draft.paper,
              pin: draft.pin,
              pinShape: draft.pinShape,
              automaticPaper: TaskBoard.derivedPaper(completed: task?.completed ?? false, priority: draft.priority)
            ) { patch in
              if case .some(let value) = patch.paper { draft.paper = value }
              if case .some(let value) = patch.pin { draft.pin = value }
              if case .some(let value) = patch.pinShape { draft.pinShape = value }
            }
          }
        }
        .padding(.vertical, 2)
      }

      if let error {
        Text(error).font(.daily(size: 13)).foregroundStyle(theme.danger)
      }

      HStack {
        if task != nil {
          Button(deleting ? "Apagando…" : "Apagar", role: .destructive, action: askDelete)
            .pillButtonStyle(.destructive)
            .disabled(busy)
        }
        Spacer()
        Button("Cancelar", action: requestClose)
          .keyboardShortcut(.cancelAction)
          .pillButtonStyle(.outline)
          .disabled(busy)
        Button(saving ? "Salvando…" : "Salvar", action: save)
          .keyboardShortcut(.defaultAction)
          .pillButtonStyle(.primary)
          .disabled(busy)
      }
    }
    .padding(20)
    .frame(width: 480)
    .frame(maxHeight: 640)
    .interactiveDismissDisabled(true)
    .onAppear { titleFocused = true }
    .confirmDialog($confirm)
  }

  /// "Dia" and "Hora" (`TaskFormModal.tsx:375-389`): the date the form sends.
  /// "Hora" waits for a day, as on the web.
  private var dayAndTimePickers: some View {
    // The day the pickers write is Gregorian `YYYY-MM-DD`, whatever the system calendar is.
    let calendar = TaskDay.calendar
    return HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Dia").typeRole(.caption).foregroundStyle(theme.inkDim)
        DatePicker(
          "Dia",
          selection: Binding(
            get: { Self.date(day: draft.day, time: "", calendar: calendar) ?? now },
            set: { draft.setDay(TaskGrouping.localISO($0, calendar: calendar)) }),
          displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.field)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Hora").typeRole(.caption).foregroundStyle(theme.inkDim)
        HStack(spacing: 6) {
          DatePicker(
            "Hora",
            selection: Binding(
              get: {
                Self.date(day: draft.day, time: draft.time.isEmpty ? "09:00" : draft.time, calendar: calendar) ?? now
              },
              set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                draft.setTime(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
              }),
            displayedComponents: .hourAndMinute
          )
          .labelsHidden()
          .datePickerStyle(.field)
          .disabled(!draft.hasDue)
          // An app-only extra: the web's time input is cleared with the keyboard.
          if !draft.time.isEmpty {
            IconButton("Sem hora", systemImage: "xmark.circle.fill", size: .extraSmall) { draft.setTime(nil) }
          }
        }
      }
    }
  }

  /// "Digitar data" (`TaskFormModal.tsx:391-436`): the free text is a way of
  /// filling "Dia" and "Hora", folded away until asked for.
  @ViewBuilder
  private var typedDate: some View {
    Button {
      if typing { draft.clearTyped() }
      typing.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .disclosureRotation(open: typing)
          .accessibilityHidden(true)
        Text("Digitar data")
      }
      .font(.daily(size: 14))
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .foregroundStyle(theme.inkMid)
    .accessibilityValue(typing ? "expandido" : "recolhido")
    if typing {
      let typed = Binding(get: { draft.typed }, set: { draft.setTyped($0, now: now) })
      TextField("Data em texto", text: typed, prompt: Text("amanhã 14:30"))
        .textFieldStyle(.roundedBorder)
        .focused($typedFocused)
        .accessibilityLabel("Data em texto")
        .singleLine(typed)
        .onAppear { typedFocused = true }
      let hint = draft.typedHint(now: now)
      Text(hint.text)
        .typeRole(.caption)
        .foregroundStyle(hint.isError ? theme.danger : theme.inkDim)
        .accessibilityAddTraits(.updatesFrequently)
    }
  }

  private static func date(day: String, time: String, calendar: Calendar) -> Date? {
    let dayParts = day.split(separator: "-").compactMap { Int($0) }
    let timeParts = time.split(separator: ":").compactMap { Int($0) }
    guard dayParts.count == 3 else { return nil }
    return calendar.date(
      from: DateComponents(
        year: dayParts[0], month: dayParts[1], day: dayParts[2],
        hour: timeParts.first ?? 0, minute: timeParts.count > 1 ? timeParts[1] : 0))
  }

  private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.daily(size: 14)).foregroundStyle(theme.inkMid)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func requestClose() {
    guard !busy else { return }
    guard dirty else {
      dismiss()
      return
    }
    confirm = ConfirmRequest(
      title: "Descartar as alterações?",
      message: "O que você mudou nesta tarefa ainda não foi salvo.",
      confirmLabel: "Descartar",
      cancelLabel: "Continuar editando",
      destructive: true,
      onConfirm: { dismiss() }
    )
  }

  private func save() {
    guard !busy else { return }
    guard !draft.trimmedTitle.isEmpty else {
      titleError = "Dê um título à tarefa."
      titleFocused = true
      return
    }
    // `typedError`: the date the text stands for is unknown, so nothing is sent.
    guard !draft.typedIsInvalid(now: now) else {
      typedFocused = true
      return
    }
    saving = true
    error = nil
    Task {
      let outcome = await store.save(draft, initial: initial, editing: task)
      saving = false
      switch outcome {
      case .saved, .savedWithoutStyle: dismiss()
      case .failed(let message): error = message
      }
    }
  }

  private func askDelete() {
    guard let task, !busy else { return }
    confirm = ConfirmRequest(
      title: "Apagar a tarefa?",
      message: "\"\(task.title)\" será removida. Isso não tem volta.",
      confirmLabel: "Apagar",
      destructive: true,
      onConfirm: { remove(task) }
    )
  }

  private func remove(_ task: TodoTask) {
    deleting = true
    error = nil
    Task {
      let failure = await store.delete(task)
      deleting = false
      if let failure {
        error = failure.userMessage
      } else {
        dismiss()
      }
    }
  }
}
