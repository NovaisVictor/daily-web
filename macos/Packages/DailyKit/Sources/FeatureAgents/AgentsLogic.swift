import DailyAPI
import DailyModels
import Foundation
import os

nonisolated extension Logger {
  static let agents = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureAgents")
}

/// The board's two views (`AgentBoard.tsx:53`).
nonisolated enum AgentsTab: String, Sendable, Equatable, CaseIterable {
  case tasks
  case sessions
}

/// `sort` (`AgentBoard.tsx:25`).
nonisolated enum AgentsSort: String, Sendable, Equatable, CaseIterable {
  case newest
  case oldest

  var label: String {
    switch self {
    case .newest: "Atividade recente"
    case .oldest: "Atividade mais antiga"
    }
  }
}

/// Why a task needs the user (`NeedsYouKind`, `components/agents/contracts.ts:19`).
nonisolated struct NeedsYou: Equatable, Sendable {
  /// `permission`, `input`, `menu`, `decision`, `access` or `credential`.
  var kind: String
  var since: String

  /// `NEEDS_YOU_LABELS` (`contracts.ts:20-22`).
  var label: String {
    switch kind {
    case "permission": "Pedindo sua permissão"
    case "input": "Aguardando sua resposta"
    case "menu": "Esperando sua escolha no terminal"
    case "decision": "Precisa da sua decisão"
    case "access": "Precisa de acesso"
    case "credential": "Precisa de credencial"
    default: kind
    }
  }
}

/// The pure rules of `components/agents/contracts.ts` and `lib/agents/model.ts`.
nonisolated enum AgentsLogic {
  // MARK: - Statuses

  static let activeStatuses: [AgentTaskStatus] = [.queued, .working, .waiting, .blocked]
  static let finishedStatuses: [AgentTaskStatus] = [.completed, .failed, .cancelled]

  /// `STATUS_LABELS` (`contracts.ts:6-9`).
  static func statusLabel(_ status: AgentTaskStatus) -> String {
    switch status {
    case .queued: "Na fila"
    case .working: "Em andamento"
    case .waiting: "Aguardando processo"
    case .blocked: "Bloqueadas"
    case .completed: "Concluídas"
    case .failed: "Falharam"
    case .cancelled: "Canceladas"
    default: status.rawValue
    }
  }

  /// `transitions` (`lib/agents/model.ts:5-9`). A status this build does not
  /// know offers nothing rather than a guess.
  static func transitions(from status: AgentTaskStatus) -> [AgentTaskStatus] {
    switch status {
    case .queued: [.working, .blocked, .completed, .cancelled]
    case .working: [.waiting, .blocked, .completed, .failed, .cancelled]
    case .waiting: [.working, .waiting, .blocked, .completed, .failed, .cancelled]
    case .blocked: [.queued, .working, .waiting, .blocked, .completed, .failed, .cancelled]
    case .completed: [.queued]
    case .failed, .cancelled: [.queued, .completed]
    default: []
    }
  }

  /// The button for moving `task` to `target` (`TaskActions.tsx:11`, `:32`).
  static func actionLabel(for target: AgentTaskStatus, from current: AgentTaskStatus) -> String {
    if target == .queued && finishedStatuses.contains(current) { return "Reabrir tarefa" }
    if target == current { return "Trocar motivo" }
    return actionLabel(target)
  }

  /// `actionLabels` (`TaskActions.tsx:11`).
  static func actionLabel(_ target: AgentTaskStatus) -> String {
    switch target {
    case .queued: "Retornar à fila"
    case .working: "Iniciar"
    case .waiting: "Aguardar processo"
    case .blocked: "Bloquear"
    case .completed: "Concluir"
    case .failed: "Marcar falha"
    case .cancelled: "Cancelar"
    default: target.rawValue
    }
  }

  // MARK: - Holds

  /// `HOLD_NOTE_MAX` (`lib/agents/model.ts:16`).
  static let holdNoteMax = 140

  static func isHeld(_ status: AgentTaskStatus) -> Bool { status == .waiting || status == .blocked }

  /// `holdReasons[status]` (`lib/agents/model.ts:10-13`).
  static func holdReasons(for status: AgentTaskStatus) -> [AgentHoldReason] {
    switch status {
    case .waiting: AgentHoldReason.waiting
    case .blocked: AgentHoldReason.blocked
    default: []
    }
  }

  /// `HOLD_LABELS` and `holdLabel` (`contracts.ts:14-18`).
  static func holdLabel(_ reason: AgentHoldReason, status: AgentTaskStatus) -> String {
    switch (status, reason) {
    case (.waiting, .pullRequest): "Revisão de PR"
    case (.waiting, .build): "CI/Build"
    case (.waiting, .deploy): "Deploy"
    case (.waiting, .external): "Processo externo"
    case (.blocked, .decision): "Decisão do usuário"
    case (.blocked, .access): "Permissão/acesso"
    case (.blocked, .credential): "Credencial"
    case (.blocked, .dependency): "Dependência"
    case (.blocked, .environment): "Erro de ambiente"
    case (.waiting, .other), (.blocked, .other): "Outro"
    default: reason.rawValue
    }
  }

  /// The hold a dialog would send, or nil while the form cannot be submitted:
  /// a reason of that status is required, and "other" needs a note
  /// (`TaskActions.tsx:34`, `schema.hold` in `lib/agents/schemas.ts:15-23`).
  static func hold(status: AgentTaskStatus, reason: AgentHoldReason?, note: String) -> AgentTaskHold? {
    guard let reason, holdReasons(for: status).contains(reason) else { return nil }
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count > holdNoteMax { return nil }
    if reason == .other && trimmed.isEmpty { return nil }
    return AgentTaskHold(reason: reason, note: trimmed.isEmpty ? nil : trimmed)
  }

  // MARK: - Needs you

  /// `needsYou` (`contracts.ts:34-45`). The hooks raise "input" whenever a turn
  /// ends; the terminal's live state and the agent's own "waiting" status are
  /// stronger evidence than that signal.
  static func needsYou(_ task: AgentTask) -> NeedsYou? {
    guard activeStatuses.contains(task.status) else { return nil }
    let live = task.assignment?.live
    if live?.state == .working { return nil }
    if task.status == .blocked, let hold = task.hold, [.decision, .access, .credential].contains(hold.reason) {
      return NeedsYou(kind: hold.reason.rawValue, since: task.lastActivityAt)
    }
    let attention = task.assignment?.attention
    if let live, live.state == .prompt {
      return NeedsYou(
        kind: attention?.kind == .permission ? "permission" : "menu",
        since: attention?.since ?? live.since ?? task.lastActivityAt)
    }
    guard let attention else { return nil }
    if let live, [.working, .background, .stopped].contains(live.state) { return nil }
    if attention.kind == .input && task.status == .waiting { return nil }
    return NeedsYou(kind: attention.kind.rawValue, since: attention.since)
  }

  /// `sessionNeedsYou` (`BoardViews.tsx:57-61`).
  static func needsYou(_ session: AgentSession) -> NeedsYou? {
    if let live = session.live, live.state == .prompt {
      return NeedsYou(
        kind: session.attention?.kind == .permission ? "permission" : "menu",
        since: session.attention?.since ?? live.since ?? session.lastActivityAt)
    }
    if let live = session.live, live.state != .idle { return nil }
    return session.attention.map { NeedsYou(kind: $0.kind.rawValue, since: $0.since) }
  }

  // MARK: - Board

  /// `activityWindows` (`lib/agents/model.ts:35`).
  static let activityWindows = [3, 7, 15, 30]
  static let defaultActivityWindow = 3

  /// `activityWindow` (`contracts.ts:48-51`): an unknown value falls back to the default.
  static func activityWindow(_ days: Int) -> Int {
    activityWindows.contains(days) ? days : defaultActivityWindow
  }

  /// The cards the board shows: root tasks active within the window
  /// (`AgentBoard.tsx:34`), even if the server sent more.
  static func boardTasks(_ tasks: [AgentTask], days: Int, now: Date) -> [AgentTask] {
    let start = now.addingTimeInterval(-Double(days) * 86_400)
    return tasks.filter { task in
      guard task.parentTaskId == nil, let at = date(task.lastActivityAt) else { return false }
      return at > start
    }
  }

  /// The finished strip: server totals for the whole period when present,
  /// else the loaded page (`KanbanColumns`, `BoardViews.tsx:37-40`).
  static func finishedCounts(_ tasks: [AgentTask], board: AgentsBoard?) -> [(status: AgentTaskStatus, count: Int)] {
    finishedStatuses.map { status in
      let total = board?.statusCounts[status.rawValue] ?? tasks.filter { $0.status == status }.count
      return (status, total)
    }
  }

  /// `FINISHED_COUNTS` (`BoardViews.tsx:24`).
  static func finishedCountLabel(_ status: AgentTaskStatus, count: Int) -> String {
    let words: (String, String) =
      switch status {
      case .completed: ("concluída", "concluídas")
      case .failed: ("falhou", "falharam")
      default: ("cancelada", "canceladas")
      }
    return "\(count) \(count == 1 ? words.0 : words.1)"
  }

  /// The number on the filter icon: filters that differ from the default
  /// (`BoardFilterMenu`, `BoardViews.tsx:153-156`).
  static func activeFilterCount(_ query: AgentsEndpoints.BoardQuery) -> Int {
    (query.status == nil ? 0 : 1) + (query.days == defaultActivityWindow ? 0 : 1)
      + (query.sort == .newest ? 0 : 1) + (query.sessionID == nil ? 0 : 1)
  }

  /// The board's empty state (`AgentBoard.tsx:70`).
  static func emptyBoardText(_ query: AgentsEndpoints.BoardQuery) -> (title: String, description: String) {
    let filtered =
      !query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query.status != nil
      || query.sessionID != nil
    let title =
      filtered
      ? "Nenhuma tarefa neste filtro"
      : query.days < 30 ? "Nenhuma tarefa nos últimos \(query.days) dias" : "Seu próximo trabalho começa aqui"
    let description =
      query.days < 30
      ? "Amplie o período para ver tarefas mais antigas, ou conecte um agente para começar."
      : "Conecte Claude, Codex ou Gemini para acompanhar as tarefas conforme os agentes trabalham."
    return (title, description)
  }

  // MARK: - Labels

  /// `LIVE_LABELS` (`contracts.ts:23-25`).
  static func liveLabel(_ state: AgentLiveState) -> String {
    switch state {
    case .working: "Executando agora"
    case .background: "Rodando em segundo plano"
    case .prompt: "Menu aberto no terminal"
    case .idle: "Parado no prompt"
    case .stopped: "Sessão encerrada"
    default: state.rawValue
    }
  }

  /// `FRESHNESS_LABELS` of the card (`TaskCard.tsx:6`).
  static func cardFreshnessLabel(_ freshness: AgentFreshness) -> String {
    switch freshness {
    case .fresh: "Reportando"
    case .stale: "Sem atualização recente"
    default: "Sem contato há mais de 10 min"
    }
  }

  /// `freshnessLabels` of the sessions grid and detail (`BoardViews.tsx:62`, `TaskDetail.tsx:54`).
  static func freshnessLabel(_ freshness: AgentFreshness) -> String {
    switch freshness {
    case .fresh: "Reportando recentemente"
    case .stale: "Sem atualização há mais de 2 minutos"
    default: "Sem contato há mais de 10 minutos"
    }
  }

  // MARK: - Time

  /// Server timestamps are `toISOString()` output; older rows may lack the fraction.
  static func date(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }

  /// `waitedFor` (`contracts.ts:52-55`).
  static func waitedFor(_ since: String, now: Date) -> String {
    guard let start = date(since) else { return "agora" }
    let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
    if minutes < 1 { return "agora" }
    if minutes < 60 { return "há \(minutes) min" }
    return "há \(minutes / 60) h"
  }

  /// `formatTime` (`contracts.ts:153-156`): pt-BR short date and time.
  static func formatTime(_ text: String, timeZone: TimeZone = .current) -> String {
    guard let date = date(text) else { return text }
    var style = Date.FormatStyle(
      date: .numeric, time: .shortened, locale: Locale(identifier: "pt_BR"), timeZone: timeZone)
    style = style.day(.twoDigits).month(.twoDigits).year(.defaultDigits)
    return date.formatted(style)
  }

  // MARK: - Errors

  /// The text for a failed task change (`accessRequest`, `components/agents/request.ts`).
  /// The agents routes answer English messages, so the web shows its own words.
  static func changeMessage(_ error: APIError) -> String {
    guard case .server(let status, _, let code, _) = error else { return error.userMessage }
    switch status {
    case 409 where code == "task_has_subtasks": return "Exclua as subtarefas antes de excluir a tarefa principal."
    case 409: return "O item mudou. Atualize os dados antes de tentar novamente."
    case 404: return "Este item não está mais disponível."
    case 503: return "O acesso dos agentes ainda não está configurado neste servidor."
    default: return "Não foi possível concluir a operação. Tente novamente."
    }
  }

  /// The text for a failed poll (`useAgentPolling.ts:16`).
  static func pollMessage(_ error: APIError) -> String {
    guard case .server(let status, _, _, _) = error else { return error.userMessage }
    return status == 404 ? "Este item não está disponível ou expirou." : "Não foi possível atualizar os dados."
  }

  /// A poll that says the data is gone or no longer ours drops what was shown
  /// (`useAgentPolling.ts:15`).
  static func dropsData(_ error: APIError) -> Bool {
    if case .server(let status, _, _, _) = error { return status == 403 || status == 404 }
    return error == .unauthorized
  }

  /// `SEND_ERRORS` (`LivePanel.tsx:17-27`).
  static func sendMessage(_ error: APIError) -> String {
    let uncertain = "Não deu para confirmar a entrega. Confira o terminal antes de reenviar."
    switch error {
    case .timedOut, .cancelled: return uncertain
    case .server(_, _, let code, _):
      switch code {
      case "terminal_not_local": return "Esta sessão não está em nenhum agent-deck alcançável."
      case "terminal_not_enabled": return "O envio não está habilitado para a sua conta."
      case "session_stopped": return "A sessão do agente está encerrada."
      case "uncertain_outcome", "idempotency_conflict": return uncertain
      case "send_refused": return "O agent-deck recusou a mensagem. Tente de novo."
      case "deck_unavailable": return "A máquina desta sessão não respondeu. Tente de novo."
      case "operation_pending": return "O envio anterior ainda está em andamento."
      case "unauthenticated": return "Sua sessão expirou. Entre novamente."
      default: return "Não foi possível enviar a mensagem."
      }
    default: return error.userMessage
    }
  }

  /// `UNAVAILABLE` (`LivePanel.tsx:12-16`).
  static func unavailableText(_ reason: AgentTerminalUnavailableReason) -> String {
    switch reason {
    case .notEnabled: "O terminal ao vivo não está habilitado para a sua conta neste servidor."
    case .notLocal:
      "Esta sessão não está no agent-deck deste servidor nem no das máquinas conectadas. Aqui aparecem só os relatos do agente."
    default: "A máquina desta sessão não respondeu (o Mac pode estar dormindo ou offline). Tentando de novo…"
    }
  }

  /// `MESSAGE_MAX` (`lib/agents/deck.ts:24`).
  static let messageMax = 4000
  static let titleMax = 200
  static let descriptionMax = 4000
}
