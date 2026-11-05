import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// Which dialog a row opened (`IssueDialog`, `components/jira/IssueActions.tsx`),
/// plus the approval and the focus booking, which the row opens itself.
enum JiraDialog: Identifiable {
  case comment(JiraItem)
  case flag(JiraItem)
  case due(JiraItem)
  case priority(JiraItem)
  case assign(JiraItem)
  case createStory(JiraItem)
  case approval(JiraItem)
  case focus(FocusSource)

  var id: String {
    switch self {
    case .comment(let issue): "comment-\(issue.key)"
    case .flag(let issue): "flag-\(issue.key)"
    case .due(let issue): "due-\(issue.key)"
    case .priority(let issue): "priority-\(issue.key)"
    case .assign(let issue): "assign-\(issue.key)"
    case .createStory(let issue): "story-\(issue.key)"
    case .approval(let issue): "approval-\(issue.key)"
    case .focus(let source): "focus-\(source.ref)"
    }
  }
}

/// `lib/jiraLimits.ts`.
enum JiraLimits {
  static let comment = 5000
  static let flagReason = 2000
  static let summary = 255
  static let description = 10_000
}

/// A dialog's title, description, body and buttons (`EditDialog`).
struct JiraDialogChrome<Content: View, Footer: View>: View {
  @Environment(\.theme) private var theme
  let title: String
  let description: String
  @ViewBuilder let content: Content
  @ViewBuilder let footer: Footer

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).typeRole(.subhead).foregroundStyle(theme.ink).accessibilityAddTraits(.isHeader)
        Text(description).font(.daily(size: 13)).foregroundStyle(theme.inkMid)
          .fixedSize(horizontal: false, vertical: true)
      }
      content
      HStack(spacing: 8) {
        Spacer()
        footer
      }
    }
    .padding(20)
    .frame(width: 440)
  }
}

/// `CommentDialog` and `CommentForm`.
struct CommentSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let store: JiraStore

  @State private var text = ""
  @State private var sending = false
  @State private var refusal: String?
  @State private var published = false

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var tooLong: Bool { trimmed.count > JiraLimits.comment }
  private var ready: Bool { !trimmed.isEmpty && !tooLong && !sending }

  var body: some View {
    JiraDialogChrome(title: "Comentar em \(issue.key)", description: issue.summary) {
      if published {
        HStack(spacing: 4) {
          Text("comentário publicado ·")
          Button("abrir \(issue.key) no Jira") {
            if let url = URL(string: issue.url) { openURL(url) }
          }
          .linkButtonStyle()
        }
        .font(.daily(size: 13))
      } else {
        VStack(alignment: .leading, spacing: 6) {
          TextEditor(text: $text)
            .font(.daily(size: 13))
            .frame(minHeight: 96)
            .disabled(sending)
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.lineStrong) }
            .accessibilityLabel("comentário em \(issue.key)")
          if let problem = refusal ?? (tooLong ? "passou de \(JiraLimits.comment) caracteres (\(trimmed.count))" : nil)
          {
            Text(problem).font(.daily(size: 12)).foregroundStyle(theme.danger)
          }
          Text("vai aparecer como seu comentário em \(issue.key)")
            .font(.daily(size: 12)).foregroundStyle(theme.inkDim)
        }
      }
    } footer: {
      if published {
        Button("Fechar") { dismiss() }.pillButtonStyle(.outline).keyboardShortcut(.defaultAction)
      } else {
        Button("Cancelar") { dismiss() }.pillButtonStyle(.outline).disabled(sending).keyboardShortcut(.cancelAction)
        Button(sending ? "Comentando…" : "Comentar", action: submit)
          .pillButtonStyle()
          .disabled(!ready)
          .keyboardShortcut(.return, modifiers: .command)
      }
    }
  }

  private func submit() {
    guard ready else { return }
    sending = true
    refusal = nil
    Task {
      let problem = await store.comment(issue.key, text: trimmed)
      sending = false
      if let problem {
        refusal = problem
      } else {
        published = true
      }
    }
  }
}

/// `FlagDialogBody`: flag with a reason, or unflag with an optional note.
struct FlagSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let store: JiraStore

  @State private var flagging: Bool
  @State private var text = ""
  @State private var sending = false
  @State private var error: String?
  @State private var warning: String?

  init(issue: JiraItem, store: JiraStore) {
    self.issue = issue
    self.store = store
    // Fixed at opening: the row refreshes after the write and would flip it.
    _flagging = State(initialValue: issue.flag != .impediment)
  }

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var valid: Bool {
    trimmed.count <= JiraLimits.flagReason && (!flagging || !trimmed.isEmpty)
  }

  var body: some View {
    if let warning {
      JiraDialogChrome(
        title: flagging ? "Impedimento marcado" : "Impedimento removido", description: "\(issue.key) — \(issue.summary)"
      ) {
        Text(warning).font(.daily(size: 13)).foregroundStyle(theme.warning)
      } footer: {
        Button("Fechar") { dismiss() }.pillButtonStyle(.outline).keyboardShortcut(.defaultAction)
      }
    } else {
      JiraDialogChrome(
        title: flagging ? "Marcar \(issue.key) como impedida?" : "Remover o impedimento de \(issue.key)?",
        description: "\(issue.key) — \(issue.summary)"
      ) {
        VStack(alignment: .leading, spacing: 6) {
          Text(flagging ? "Motivo" : "Observação (opcional)").font(.daily(size: 13, weight: .medium))
          TextEditor(text: $text)
            .font(.daily(size: 13))
            .frame(minHeight: 72)
            .disabled(sending)
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.lineStrong) }
            .accessibilityLabel(flagging ? "Motivo" : "Observação (opcional)")
            .onChange(of: text) { _, next in
              // `maxLength` on the web's textarea.
              if next.count > JiraLimits.flagReason { text = String(next.prefix(JiraLimits.flagReason)) }
            }
          Text(
            flagging
              ? "o motivo vira um comentário na issue" : "se preenchida, a observação vira um comentário na issue"
          )
          .font(.daily(size: 11)).foregroundStyle(theme.inkDim)
          if let error { Text(error).font(.daily(size: 13)).foregroundStyle(theme.danger) }
        }
      } footer: {
        Button("Cancelar") { dismiss() }.pillButtonStyle(.outline).disabled(sending).keyboardShortcut(.cancelAction)
        Button(sending ? "enviando…" : (flagging ? "Marcar impedimento" : "Remover impedimento"), action: submit)
          .pillButtonStyle(flagging ? .destructive : .primary)
          .disabled(sending || !valid)
          .keyboardShortcut(.defaultAction)
      }
    }
  }

  private func submit() {
    sending = true
    error = nil
    Task {
      let result = await store.setFlag(issue.key, flagging: flagging, text: text)
      sending = false
      switch result {
      case .failure(let failure): error = failure.userMessage
      case .success(let response):
        if let message = response.warning {
          warning = message
        } else {
          dismiss()
        }
      }
    }
  }
}

/// `ApprovalDialogBody`: the user's pending approvals on the issue, each
/// answered after a confirmation.
struct ApprovalSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let store: JiraStore

  enum Load {
    case loading
    case failed(String)
    case ready([JiraPendingApproval])
  }

  @State private var load: Load = .loading
  @State private var confirming: (approval: JiraPendingApproval, decision: JiraEndpoints.Decision)?
  @State private var sending = false
  @State private var error: String?
  @State private var request = 0

  var body: some View {
    JiraDialogChrome(title: title, description: "\(issue.key) — \(issue.summary)") {
      VStack(alignment: .leading, spacing: 10) {
        switch load {
        case .loading:
          Text("carregando aprovações…").foregroundStyle(theme.inkDim)
        case .failed(let message):
          Text(message).foregroundStyle(theme.danger)
        case .ready(let approvals):
          if approvals.isEmpty {
            HStack(spacing: 4) {
              Text("nenhuma aprovação sua pendente nesta issue —").foregroundStyle(theme.inkDim)
              Button("abrir no Jira") {
                if let url = URL(string: issue.url) { openURL(url) }
              }
              .linkButtonStyle()
            }
          }
          if confirming == nil {
            if let error { Text(error).foregroundStyle(theme.danger) }
            ForEach(approvals) { approval in
              HStack {
                Text(approval.name).foregroundStyle(theme.ink)
                Spacer()
                Button("Recusar") { confirming = (approval, .decline) }.pillButtonStyle(.outline, size: .small)
                Button("Aprovar") { confirming = (approval, .approve) }.pillButtonStyle(.primary, size: .small)
              }
            }
          }
        }
        if let confirming {
          Text(confirming.approval.name).foregroundStyle(theme.ink)
          if let error { Text(error).foregroundStyle(theme.danger) }
        }
      }
      .font(.daily(size: 13))
    } footer: {
      if let confirming {
        Button("Voltar") {
          error = nil
          self.confirming = nil
        }
        .pillButtonStyle(.outline)
        .disabled(sending)
        .keyboardShortcut(.cancelAction)
        Button(
          sending
            ? "enviando…" : (confirming.decision == .approve ? "Confirmar aprovação" : "Confirmar recusa")
        ) {
          submit(confirming.approval, confirming.decision)
        }
        .pillButtonStyle(confirming.decision == .decline ? .destructive : .primary)
        .disabled(sending)
        .keyboardShortcut(.defaultAction)
      } else {
        Button("Fechar") { dismiss() }.pillButtonStyle(.outline).keyboardShortcut(.cancelAction)
      }
    }
    .task { reload() }
  }

  private var title: String {
    guard let confirming else { return "Aprovação de \(issue.key)" }
    return "Confirmar \(confirming.decision == .approve ? "aprovação" : "recusa") de \(issue.key)?"
  }

  private func reload() {
    request += 1
    let mine = request
    load = .loading
    Task {
      let result = await store.approvals(issue.key)
      guard mine == request else { return }
      switch result {
      case .success(let approvals): load = .ready(approvals)
      case .failure(let failure): load = .failed(failure.userMessage)
      }
    }
  }

  private func submit(_ approval: JiraPendingApproval, _ decision: JiraEndpoints.Decision) {
    sending = true
    error = nil
    Task {
      let failure = await store.decide(issue.key, approval: approval, decision: decision)
      sending = false
      guard let failure else {
        dismiss()
        return
      }
      error = failure.userMessage
      // Someone else decided in the meantime: what is still pending is the new choice.
      if case .server(409, _, _, _) = failure {
        confirming = nil
        reload()
      }
    }
  }
}

/// The two buttons of an edit dialog (`Actions`).
struct JiraDialogActions: View {
  let sending: Bool
  var disabled = false
  let idle: String
  let busy: String
  let cancel: () -> Void
  let confirm: () -> Void

  var body: some View {
    Button("Cancelar", action: cancel).pillButtonStyle(.outline).disabled(sending).keyboardShortcut(.cancelAction)
    Button(sending ? busy : idle, action: confirm)
      .pillButtonStyle()
      .disabled(disabled || sending)
      .keyboardShortcut(.defaultAction)
  }
}

/// `DueForm`: a new due date, or none.
struct DueSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let store: JiraStore

  @State private var value: String
  @State private var sending = false
  @State private var refusal: String?

  init(issue: JiraItem, store: JiraStore) {
    self.issue = issue
    self.store = store
    _value = State(initialValue: issue.dueDate)
  }

  private var changed: Bool { value != issue.dueDate }

  var body: some View {
    JiraDialogChrome(title: "Prazo de \(issue.key)", description: issue.summary) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Novo prazo").font(.daily(size: 13, weight: .medium))
        HStack(spacing: 8) {
          if value.isEmpty {
            Button("Escolher data") { value = JiraDates.dayString(store.now()) }
              .pillButtonStyle(.outline, size: .small)
              .disabled(sending)
          } else {
            DatePicker("Novo prazo", selection: dateBinding, displayedComponents: .date)
              .labelsHidden()
              .disabled(sending)
          }
          Button("Remover prazo") { value = "" }
            .pillButtonStyle(.ghost, size: .small)
            .disabled(value.isEmpty || sending)
        }
        if changed {
          Text("de \(JiraText.formatDate(issue.dueDate)) para \(JiraText.formatDate(value))")
            .font(.daily(size: 12)).foregroundStyle(theme.ink)
        }
        JiraRefusal(message: refusal, issue: issue)
      }
    } footer: {
      JiraDialogActions(
        sending: sending, disabled: !changed, idle: "Salvar", busy: "Salvando…", cancel: { dismiss() }, confirm: save)
    }
  }

  private var dateBinding: Binding<Date> {
    Binding(
      get: { JiraDates.localDate(value) ?? store.now() },
      set: { value = JiraDates.dayString($0) })
  }

  private func save() {
    sending = true
    refusal = nil
    Task {
      let failure = await store.edit(issue.key, .due(value.isEmpty ? nil : value))
      sending = false
      if let failure { refusal = failure.userMessage } else { dismiss() }
    }
  }
}

/// `PriorityForm`: the priorities Jira offers for the issue.
struct PrioritySheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let store: JiraStore

  enum Load {
    case loading
    case failed(String)
    case ready(JiraPriorityOptions)
  }

  @State private var load: Load = .loading
  @State private var chosen: String?
  @State private var sending = false
  @State private var refusal: String?

  private var options: JiraPriorityOptions? {
    if case .ready(let options) = load { return options }
    return nil
  }

  private var target: JiraPriorityOption? {
    options?.priorities.first { $0.id == chosen }
  }

  private var changed: Bool {
    guard let target else { return false }
    return target.id != options?.current?.id
  }

  var body: some View {
    JiraDialogChrome(title: "Prioridade de \(issue.key)", description: issue.summary) {
      VStack(alignment: .leading, spacing: 8) {
        switch load {
        case .loading:
          Text("carregando prioridades…").foregroundStyle(theme.inkDim)
        case .failed(let message):
          Text(message).foregroundStyle(theme.danger)
          Button("Tentar de novo", action: fetch).pillButtonStyle(.outline, size: .small)
        case .ready(let options):
          Picker(
            "Prioridade",
            selection: Binding(get: { chosen ?? options.current?.id ?? "" }, set: { chosen = $0 })
          ) {
            ForEach(options.priorities) { Text($0.name).tag($0.id) }
          }
          .pickerStyle(.radioGroup)
          .labelsHidden()
          .disabled(sending)
          if changed, let target {
            Text("de \(options.current?.name ?? "sem prioridade") para \(target.name)")
              .foregroundStyle(theme.ink)
          }
          JiraRefusal(message: refusal, issue: issue)
        }
      }
      .font(.daily(size: 13))
    } footer: {
      JiraDialogActions(
        sending: sending, disabled: !changed, idle: "Salvar", busy: "Salvando…", cancel: { dismiss() }, confirm: save)
    }
    .task { fetch() }
  }

  private func fetch() {
    load = .loading
    Task {
      switch await store.priorities(issue.key) {
      case .success(let options): load = .ready(options)
      case .failure(let failure): load = .failed(failure.userMessage)
      }
    }
  }

  private func save() {
    guard let target else { return }
    sending = true
    refusal = nil
    Task {
      let failure = await store.edit(issue.key, .priority(target.id))
      sending = false
      if let failure { refusal = failure.userMessage } else { dismiss() }
    }
  }
}

/// `AssignForm`.
struct AssignSheet: View {
  @Environment(\.dismiss) private var dismiss
  let issue: JiraItem
  let store: JiraStore

  @State private var sending = false
  @State private var refusal: String?

  var body: some View {
    JiraDialogChrome(title: "Atribuir a mim", description: "\(issue.key) passa a ter você como responsável") {
      JiraRefusal(message: refusal, issue: issue)
    } footer: {
      JiraDialogActions(sending: sending, idle: "Atribuir", busy: "Atribuindo…", cancel: { dismiss() }) {
        sending = true
        refusal = nil
        Task {
          let failure = await store.edit(issue.key, .assignSelf)
          sending = false
          if let failure { refusal = failure.userMessage } else { dismiss() }
        }
      }
    }
  }
}

/// `CreateStoryForm`: a story inside the epic.
struct CreateStorySheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let store: JiraStore

  @State private var summary = ""
  @State private var description = ""
  @State private var sending = false
  @State private var refusal: String?
  @State private var created: JiraCreatedStory?

  private var trimmed: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var valid: Bool { !trimmed.isEmpty && trimmed.count <= JiraLimits.summary }

  var body: some View {
    if let created {
      JiraDialogChrome(title: "História criada", description: "dentro de \(issue.key)") {
        HStack(spacing: 4) {
          Button(created.key) {
            if let url = URL(string: created.url) { openURL(url) }
          }
          .linkButtonStyle()
          Text("criada")
        }
        .font(.daily(size: 13))
      } footer: {
        Button("Fechar") { dismiss() }.pillButtonStyle(.outline).keyboardShortcut(.defaultAction)
      }
    } else {
      JiraDialogChrome(
        title: "Criar história", description: "nova história em \(issue.project) dentro de \(issue.key)"
      ) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Resumo").font(.daily(size: 13, weight: .medium))
          TextField("Resumo", text: $summary)
            .labelsHidden()
            .disabled(sending)
            .onChange(of: summary) { _, next in
              if next.count > JiraLimits.summary { summary = String(next.prefix(JiraLimits.summary)) }
            }
          Text("Descrição (opcional)").font(.daily(size: 13, weight: .medium))
          TextEditor(text: $description)
            .font(.daily(size: 13))
            .frame(minHeight: 72)
            .disabled(sending)
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.lineStrong) }
            .accessibilityLabel("Descrição (opcional)")
            .onChange(of: description) { _, next in
              if next.count > JiraLimits.description { description = String(next.prefix(JiraLimits.description)) }
            }
          JiraRefusal(message: refusal, issue: issue)
        }
      } footer: {
        JiraDialogActions(
          sending: sending, disabled: !valid, idle: "Criar", busy: "Criando…", cancel: { dismiss() }, confirm: create)
      }
    }
  }

  private func create() {
    sending = true
    refusal = nil
    Task {
      let result = await store.createStory(issue.key, summary: summary, description: description)
      sending = false
      switch result {
      case .success(let story): created = story
      case .failure(let failure): refusal = failure.userMessage
      }
    }
  }
}
