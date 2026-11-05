import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// `TaskDetail.tsx`: the task, its live session, subtasks, activity and the side facts.
struct AgentTaskDetailView: View {
  @Environment(\.theme) private var theme
  let store: AgentTaskDetailStore
  let now: Date
  let back: () -> Void
  let openTask: (String) -> Void
  let openSession: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Button(action: back) {
        Label("Voltar ao kanban", systemImage: "arrow.left")
      }
      .pillButtonStyle(.ghost)
      .keyboardShortcut("[", modifiers: .command)

      if let error = store.error {
        ErrorState(store.detail == nil ? "Tarefa indisponível" : "Último estado recebido", description: error) {
          Task { await store.load() }
        }
      }
      if let detail = store.detail {
        content(detail)
      } else if store.error == nil {
        LoadingState("Carregando tarefa…")
      }
    }
    .frame(maxWidth: 960, alignment: .leading)
  }

  @ViewBuilder private func content(_ detail: AgentTaskDetail) -> some View {
    let task = detail.task
    if let waiting = AgentsLogic.needsYou(task) {
      NeedsYouLine(needsYou: waiting, now: now)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.dangerTint, in: .rect(cornerRadius: Radius.medium))
        .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.danger) }
    }
    header(task)
    if let live = store.live { AgentLivePanel(store: live, now: now) }
    if task.parentTaskId == nil { subtasks(detail) }
    HStack(alignment: .top, spacing: 20) {
      activity(detail).frame(maxWidth: .infinity, alignment: .topLeading)
      aside(task).frame(width: 280, alignment: .topLeading)
    }
  }

  // MARK: - Header

  private func header(_ task: AgentTask) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let parent = task.parentTaskId {
        Button {
          openTask(parent)
        } label: {
          Label("Ver tarefa principal", systemImage: "arrow.left")
        }
        .buttonStyle(.link)
      }
      HStack(spacing: 8) {
        AgentStatusBadge(text: AgentsLogic.statusLabel(task.status), status: task.status)
        if let hold = task.hold {
          AgentStatusBadge(text: AgentsLogic.holdLabel(hold.reason, status: task.status), status: task.status)
          if let note = hold.note { Text(note).font(.geist(12)).foregroundStyle(theme.inkMid) }
        }
      }
      Text(task.title)
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
        .textSelection(.enabled)
        .accessibilityAddTraits(.isHeader)
      if !task.description.isEmpty {
        Text(task.description)
          .font(.geist(13))
          .foregroundStyle(theme.inkMid)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text("Referência: \(task.externalId) · Versão \(task.version)")
        .font(.geist(11))
        .foregroundStyle(theme.inkDim)
        .textSelection(.enabled)
      Divider()
      AgentTaskActions(store: store, task: task)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .agentsCard()
  }

  // MARK: - Subtasks

  private func subtasks(_ detail: AgentTaskDetail) -> some View {
    let items = detail.subtasks.items
    let statuses = AgentTaskStatus.known.filter { status in items.contains { $0.status == status } }
    return VStack(alignment: .leading, spacing: 12) {
      Text("Subtarefas").font(.geist(14, weight: .semibold)).accessibilityAddTraits(.isHeader)
      Text("Subtarefas agrupadas por status. O status da tarefa principal é definido separadamente.")
        .font(.geist(11))
        .foregroundStyle(theme.inkMid)
      if items.isEmpty {
        EmptyState(
          store.subtaskCursor == nil ? "Nenhuma subtarefa criada" : "Nenhuma subtarefa nesta página",
          description: "Os agentes podem dividir esta tarefa em subtarefas pela API ou pelo MCP.")
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8, alignment: .top)], spacing: 8) {
          ForEach(statuses, id: \.self) { status in
            let children = items.filter { $0.status == status }
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                AgentStatusBadge(text: AgentsLogic.statusLabel(status), status: status)
                Spacer()
                Text("\(children.count)").font(.geist(11)).foregroundStyle(theme.inkDim)
              }
              ForEach(children) { child in
                AgentTaskCard(task: child, now: now, open: openTask)
              }
            }
            .padding(8)
            .background(theme.surface2.opacity(0.4), in: .rect(cornerRadius: Radius.medium))
            .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.line) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AgentsLogic.statusLabel(status))
          }
        }
      }
      HStack(spacing: 12) {
        Text("\(items.count) nesta página\(detail.subtasks.nextCursor == nil ? "" : " · Há mais subtarefas")")
          .font(.geist(11))
          .foregroundStyle(theme.inkDim)
        if store.subtaskCursor != nil {
          Button("Primeiras subtarefas") { store.setSubtaskCursor(nil) }
            .pillButtonStyle(.outline, size: .small)
        }
        if let next = detail.subtasks.nextCursor {
          Button("Ver mais subtarefas") { store.setSubtaskCursor(next) }
            .pillButtonStyle(.outline, size: .small)
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .agentsCard()
  }

  // MARK: - Activity

  private func activity(_ detail: AgentTaskDetail) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Atividade recente").font(.geist(14, weight: .semibold)).accessibilityAddTraits(.isHeader)
      if detail.activity.items.isEmpty {
        EmptyState("Sem atualizações de atividade", description: "Novos relatos do agente aparecerão aqui.")
      } else {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(detail.activity.items) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.summary)
                .font(.geist(13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
              Text("\(AgentsLogic.formatTime(item.receivedAt)) · \(item.kind.rawValue)")
                .font(.geist(11))
                .foregroundStyle(theme.inkDim)
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
            .accessibilityElement(children: .combine)
          }
        }
      }
      HStack(spacing: 8) {
        if store.activityCursor != nil {
          Button("Mais recentes") { store.setActivityCursor(nil) }
            .pillButtonStyle(.outline, size: .small)
        }
        if let next = detail.activity.nextCursor {
          Button("Ver mais atividade") { store.setActivityCursor(next) }
            .pillButtonStyle(.outline, size: .small)
        }
      }
    }
    .padding(20)
    .agentsCard()
  }

  // MARK: - Aside

  private func aside(_ task: AgentTask) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Label("Agente responsável", systemImage: "cpu")
          .font(.geist(13, weight: .semibold))
          .accessibilityAddTraits(.isHeader)
        if let assignment = task.assignment {
          Text(assignment.displayName).font(.geist(13))
          Text(assignment.provider.rawValue).font(.geist(11)).foregroundStyle(theme.inkMid)
          Button("Sessão \(assignment.sessionId)") { openSession(assignment.sessionId) }
            .buttonStyle(.link)
            .font(.geist(11))
          Text(AgentsLogic.freshnessLabel(assignment.freshness)).font(.geist(11)).foregroundStyle(theme.inkMid)
        } else {
          Text("Nenhum agente atribuído.").font(.geist(13)).foregroundStyle(theme.inkMid)
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Label("Histórico", systemImage: "clock")
          .font(.geist(13, weight: .semibold))
          .accessibilityAddTraits(.isHeader)
        fact("Criada em", AgentsLogic.formatTime(task.createdAt))
        fact("Última atividade", AgentsLogic.formatTime(task.lastActivityAt))
        Text("A tarefa e seu histórico expiram após 30 dias sem atividade aceita. Consultas não renovam esse prazo.")
          .font(.geist(11))
          .foregroundStyle(theme.inkMid)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let source = task.source {
        VStack(alignment: .leading, spacing: 4) {
          Text("Origem vinculada").font(.geist(13, weight: .semibold)).accessibilityAddTraits(.isHeader)
          Text("\(source.provider.rawValue): \(source.resource)")
            .font(.geist(11))
            .foregroundStyle(theme.inkMid)
            .textSelection(.enabled)
          Text("O vínculo não altera o item de origem automaticamente.")
            .font(.geist(11))
            .foregroundStyle(theme.inkDim)
        }
      }
    }
    .padding(20)
    .agentsCard()
  }

  private func fact(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).foregroundStyle(theme.inkDim)
      Text(value)
    }
    .font(.geist(11))
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Actions

/// `TaskActions.tsx`: the transitions the status allows, edit and delete.
struct AgentTaskActions: View {
  @Environment(\.theme) private var theme
  let store: AgentTaskDetailStore
  let task: AgentTask

  @State private var holdTarget: HoldTarget?
  @State private var editing: EditDraft?
  @State private var confirmation: ConfirmRequest?

  struct HoldTarget: Identifiable {
    var status: AgentTaskStatus
    var id: String { status.rawValue }
  }

  struct EditDraft: Identifiable {
    let id = UUID()
    var title: String
    var description: String
    /// The version the edit started from.
    let version: Int
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      FlowLayout(spacing: 8) {
        ForEach(store.availableTransitions, id: \.self) { target in
          Button(AgentsLogic.actionLabel(for: target, from: task.status)) { start(target) }
            .pillButtonStyle(.outline, size: .small)
        }
        Button("Editar") {
          editing = EditDraft(title: task.title, description: task.description, version: task.version)
        }
        .pillButtonStyle(.ghost, size: .small)
        Button("Excluir", role: .destructive) { confirmDelete() }
          .pillButtonStyle(.ghost, size: .small)
      }
      .disabled(store.isSaving)
      if let error = store.actionError {
        Text(error)
          .font(.geist(13))
          .foregroundStyle(theme.danger)
          .accessibilityAddTraits(.isStaticText)
      }
    }
    .sheet(item: $holdTarget) { target in
      HoldReasonSheet(store: store, status: target.status)
    }
    .sheet(item: $editing) { draft in
      EditTaskSheet(store: store, draft: draft)
    }
    .confirmDialog($confirmation)
  }

  private func start(_ target: AgentTaskStatus) {
    store.clearActionError()
    if AgentsLogic.isHeld(target) {
      holdTarget = HoldTarget(status: target)
    } else {
      Task { await store.transition(to: target) }
    }
  }

  private func confirmDelete() {
    let title = task.title
    confirmation = ConfirmRequest(
      title: "Excluir esta tarefa?",
      message: "A tarefa “\(title)” e seu histórico serão removidos. O item vinculado no Jira ou GitHub permanece.",
      confirmLabel: "Excluir tarefa",
      destructive: true
    ) { [store] in
      Task { await store.delete() }
    }
  }
}

/// "Aguardando o quê?" / "Por que está bloqueada?" (`TaskActions.tsx:34`).
struct HoldReasonSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  let store: AgentTaskDetailStore
  let status: AgentTaskStatus
  @State private var reason: AgentHoldReason?
  @State private var note = ""

  private var hold: AgentTaskHold? { AgentsLogic.hold(status: status, reason: reason, note: note) }

  var body: some View {
    Form {
      Picker("Motivo", selection: $reason) {
        Text("Escolha um motivo").tag(AgentHoldReason?.none)
        ForEach(AgentsLogic.holdReasons(for: status), id: \.self) { value in
          Text(AgentsLogic.holdLabel(value, status: status)).tag(AgentHoldReason?.some(value))
        }
      }
      TextField(
        reason == .other ? "Detalhe" : "Detalhe (opcional)",
        text: Binding(get: { note }, set: { note = String($0.prefix(AgentsLogic.holdNoteMax)) }),
        prompt: Text(status == .waiting ? "Ex.: PR #81" : "Ex.: escolher entre A e B"))
      if let error = store.actionError {
        Text(error).foregroundStyle(theme.danger)
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .top) {
      Text(status == .waiting ? "Aguardando o quê?" : "Por que está bloqueada?")
        .typeRole(.subhead)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 20)
        .accessibilityAddTraits(.isHeader)
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button("Cancelar", role: .cancel) { dismiss() }
          .pillButtonStyle(.outline)
          .keyboardShortcut(.cancelAction)
        Button(AgentsLogic.actionLabel(status)) { submit() }
          .pillButtonStyle()
          .keyboardShortcut(.defaultAction)
          .disabled(hold == nil || store.isSaving)
      }
      .padding(20)
    }
    .frame(width: 420)
  }

  private func submit() {
    guard let hold else { return }
    Task {
      if await store.transition(to: status, hold: hold) { dismiss() }
    }
  }
}

/// "Editar tarefa" (`TaskActions.tsx:34`).
struct EditTaskSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  let store: AgentTaskDetailStore
  @State var draft: AgentTaskActions.EditDraft

  var body: some View {
    Form {
      TextField(
        "Título",
        text: Binding(get: { draft.title }, set: { draft.title = String($0.prefix(AgentsLogic.titleMax)) }))
      VStack(alignment: .leading, spacing: 4) {
        Text("Descrição")
        TextEditor(
          text: Binding(
            get: { draft.description },
            set: { draft.description = String($0.prefix(AgentsLogic.descriptionMax)) })
        )
        .font(.geist(13))
        .frame(minHeight: 120)
        .accessibilityLabel("Descrição")
      }
      if let error = store.actionError {
        Text(error).foregroundStyle(theme.danger)
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .top) {
      Text("Editar tarefa")
        .typeRole(.subhead)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 20)
        .accessibilityAddTraits(.isHeader)
    }
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button("Cancelar", role: .cancel) { dismiss() }
          .pillButtonStyle(.outline)
          .keyboardShortcut(.cancelAction)
        Button("Salvar alterações") { submit() }
          .pillButtonStyle()
          .keyboardShortcut(.defaultAction)
          .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
      }
      .padding(20)
    }
    .frame(width: 520)
  }

  private func submit() {
    let draft = self.draft
    Task {
      if await store.edit(title: draft.title, description: draft.description, version: draft.version) { dismiss() }
    }
  }
}

extension View {
  /// The glass panel every block of the screen sits on (`rounded-2xl border
  /// bg-surface-1` on the web, Liquid Glass here as on the Home panels).
  func agentsCard() -> some View {
    modifier(AgentsCard())
  }
}

private struct AgentsCard: ViewModifier {
  func body(content: Content) -> some View {
    content.glassSurface(.panel)
  }
}
