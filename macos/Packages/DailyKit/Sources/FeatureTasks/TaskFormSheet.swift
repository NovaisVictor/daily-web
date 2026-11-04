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
            TextField("Data em texto", text: $draft.dueText, prompt: Text("amanhã 14:30"))
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel("Data em texto")
            Text("hoje, amanhã, +3d ou AAAA-MM-DD, com hora opcional no fim")
              .typeRole(.caption)
              .foregroundStyle(theme.inkDim)
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
