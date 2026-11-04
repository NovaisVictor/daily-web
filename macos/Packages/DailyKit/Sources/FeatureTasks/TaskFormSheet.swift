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
  @State private var error: String?
  @State private var saving = false
  @State private var deleting = false
  @State private var confirm: ConfirmRequest?
  @FocusState private var titleFocused: Bool

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
              .onChange(of: draft.title) {
                draft.clipTitle()
                titleError = nil
              }
            if let titleError {
              Text(titleError).font(.system(size: 13)).foregroundStyle(theme.danger)
            }
          }

          field("Data") {
            FlowLayout(spacing: 8) {
              Chip("Hoje", isOn: draft.dayPart == days.today) { draft.setDay(days.today) }
              Chip("Amanhã", isOn: draft.dayPart == days.tomorrow) { draft.setDay(days.tomorrow) }
              Chip("Próx. semana", isOn: draft.dayPart == days.monday && days.monday != days.tomorrow) {
                draft.setDay(days.monday)
              }
              Chip("Sem data", isOn: !draft.hasDue) { draft.setDay(nil) }
            }
            dayAndTimePickers
            TextField("Data em texto", text: $draft.dueText, prompt: Text("amanhã 14:30"))
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Data em texto")
            let hint = draft.dueHint(now: now)
            Text(hint.text)
              .typeRole(.caption)
              .foregroundStyle(hint.isError ? theme.danger : theme.inkDim)
              .accessibilityAddTraits(.updatesFrequently)
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
              Picker("Coluna", selection: $draft.column) {
                Text(BoardColumn.todo.label).tag(BoardColumn.todo)
                Text(BoardColumn.doing.label).tag(BoardColumn.doing)
              }
              .pickerStyle(.segmented)
              .labelsHidden()
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
        Text(error).font(.system(size: 13)).foregroundStyle(theme.danger)
      }

      HStack {
        if task != nil {
          Button(deleting ? "Apagando…" : "Apagar", role: .destructive, action: askDelete)
            .disabled(busy)
        }
        Spacer()
        Button("Cancelar", action: requestClose)
          .keyboardShortcut(.cancelAction)
          .disabled(busy)
        Button(saving ? "Salvando…" : "Salvar", action: save)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
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

  /// "Dia" and "Hora" (`TaskFormModal.tsx:375-389`). They follow the text while
  /// it parses and write back into it; "Hora" waits for a day, as on the web.
  private var dayAndTimePickers: some View {
    let parsed = draft.parsedDue(now: now)
    let calendar = Calendar.current
    return HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Dia").typeRole(.caption).foregroundStyle(theme.inkDim)
        DatePicker(
          "Dia",
          selection: Binding(
            get: { parsed.flatMap { Self.date(day: $0.day, time: "", calendar: calendar) } ?? now },
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
                parsed.flatMap { Self.date(day: $0.day, time: $0.time.isEmpty ? "09:00" : $0.time, calendar: calendar) }
                  ?? now
              },
              set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                draft.setTime(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
              }),
            displayedComponents: .hourAndMinute
          )
          .labelsHidden()
          .datePickerStyle(.field)
          .disabled(parsed == nil)
          if let parsed, !parsed.time.isEmpty {
            Button {
              draft.setTime(nil)
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Sem hora")
            .accessibilityLabel("Sem hora")
          }
        }
      }
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
      Text(label).font(.system(size: 14)).foregroundStyle(theme.inkMid)
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
