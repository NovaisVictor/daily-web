import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeatureAgents

/// Mirrors `tests/components/agents/NeedsYou.test.ts`.
@Suite struct NeedsYouTests {
  @Test func trustsTheRawAttentionWithoutLiveEvidence() {
    #expect(
      AgentsLogic.needsYou(agentTask(status: .working, attention: .input)) == NeedsYou(kind: "input", since: since))
    #expect(
      AgentsLogic.needsYou(agentTask(status: .working, attention: .permission))
        == NeedsYou(kind: "permission", since: since))
  }

  @Test func ignoresIdleSignalWhileWaitingForAProcess() {
    let hold = AgentTaskHold(reason: .build, note: nil)
    #expect(AgentsLogic.needsYou(agentTask(status: .waiting, attention: .input, hold: hold)) == nil)
    #expect(
      AgentsLogic.needsYou(agentTask(status: .waiting, attention: .permission, hold: hold))
        == NeedsYou(kind: "permission", since: since))
  }

  @Test func ignoresAttentionWhileTheTerminalIsBusy() {
    for live in [AgentLiveState.working, .background, .stopped] {
      #expect(AgentsLogic.needsYou(agentTask(status: .working, attention: .input, live: live)) == nil)
    }
    #expect(
      AgentsLogic.needsYou(agentTask(status: .working, attention: .input, live: .idle))
        == NeedsYou(kind: "input", since: since))
  }

  @Test func flagsAnOpenTerminalMenu() {
    #expect(AgentsLogic.needsYou(agentTask(status: .working, live: .prompt)) == NeedsYou(kind: "menu", since: since))
    #expect(
      AgentsLogic.needsYou(agentTask(status: .working, attention: .permission, live: .prompt))
        == NeedsYou(kind: "permission", since: since))
  }

  @Test func keepsDecisionBlocksUnlessVisiblyWorking() {
    let hold = AgentTaskHold(reason: .decision, note: "A ou B")
    #expect(
      AgentsLogic.needsYou(agentTask(status: .blocked, live: .background, hold: hold))
        == NeedsYou(kind: "decision", since: since))
    #expect(AgentsLogic.needsYou(agentTask(status: .blocked, live: .working, hold: hold)) == nil)
  }

  @Test func neverFlagsFinishedTasks() {
    for status in [AgentTaskStatus.completed, .failed, .cancelled] {
      #expect(AgentsLogic.needsYou(agentTask(status: status, attention: .input, live: .prompt)) == nil)
    }
  }

  @Test func labelsCopyTheWeb() {
    #expect(NeedsYou(kind: "menu", since: since).label == "Esperando sua escolha no terminal")
    #expect(NeedsYou(kind: "decision", since: since).label == "Precisa da sua decisão")
  }
}

@Suite struct TransitionTests {
  @Test func availabilityPerStatusMatchesTheModel() {
    #expect(AgentsLogic.transitions(from: .queued) == [.working, .blocked, .completed, .cancelled])
    #expect(AgentsLogic.transitions(from: .working) == [.waiting, .blocked, .completed, .failed, .cancelled])
    #expect(AgentsLogic.transitions(from: .waiting) == [.working, .waiting, .blocked, .completed, .failed, .cancelled])
    #expect(
      AgentsLogic.transitions(from: .blocked) == [
        .queued, .working, .waiting, .blocked, .completed, .failed, .cancelled,
      ])
    #expect(AgentsLogic.transitions(from: .completed) == [.queued])
    #expect(AgentsLogic.transitions(from: .failed) == [.queued, .completed])
    #expect(AgentsLogic.transitions(from: .cancelled) == [.queued, .completed])
    #expect(AgentsLogic.transitions(from: AgentTaskStatus(rawValue: "archived")).isEmpty)
  }

  /// `TaskActions.test.tsx`: a cancelled task offers "Reabrir tarefa" and "Concluir";
  /// a waiting task can change its reason.
  @Test func buttonLabels() {
    let cancelled = AgentsLogic.transitions(from: .cancelled).map { AgentsLogic.actionLabel(for: $0, from: .cancelled) }
    #expect(cancelled == ["Reabrir tarefa", "Concluir"])
    let waiting = AgentsLogic.transitions(from: .waiting).map { AgentsLogic.actionLabel(for: $0, from: .waiting) }
    #expect(waiting == ["Iniciar", "Trocar motivo", "Bloquear", "Concluir", "Marcar falha", "Cancelar"])
    #expect(AgentsLogic.actionLabel(for: .queued, from: .blocked) == "Retornar à fila")
  }

  @Test func blockedReasonsAreOnlyTheBlockedOnes() {
    let labels = AgentsLogic.holdReasons(for: .blocked).map { AgentsLogic.holdLabel($0, status: .blocked) }
    #expect(
      labels == ["Decisão do usuário", "Permissão/acesso", "Credencial", "Dependência", "Erro de ambiente", "Outro"])
    #expect(AgentsLogic.holdReasons(for: .working).isEmpty)
  }

  @Test func holdValidation() {
    #expect(AgentsLogic.hold(status: .waiting, reason: nil, note: "x") == nil)
    #expect(AgentsLogic.hold(status: .waiting, reason: .other, note: "  ") == nil)
    #expect(AgentsLogic.hold(status: .waiting, reason: .decision, note: "") == nil)
    #expect(
      AgentsLogic.hold(status: .waiting, reason: .pullRequest, note: " PR #81 ")
        == AgentTaskHold(reason: .pullRequest, note: "PR #81"))
    #expect(AgentsLogic.hold(status: .blocked, reason: .access, note: "") == AgentTaskHold(reason: .access, note: nil))
    #expect(AgentsLogic.hold(status: .blocked, reason: .other, note: String(repeating: "a", count: 141)) == nil)
    #expect(
      AgentsLogic.hold(status: .blocked, reason: .other, note: "A ou B")
        == AgentTaskHold(reason: .other, note: "A ou B"))
  }
}

@Suite struct BoardLogicTests {
  @Test func windowFallsBackToDefault() {
    #expect(AgentsLogic.activityWindow(7) == 7)
    #expect(AgentsLogic.activityWindow(5) == 3)
  }

  @Test func boardKeepsRootTasksInsideTheWindow() {
    let now = iso("2026-11-04T12:00:00.000Z")
    let tasks = [
      agentTask("recent", status: .working, lastActivityAt: "2026-11-03T12:00:00.000Z"),
      agentTask("old", status: .working, lastActivityAt: "2026-10-30T12:00:00.000Z"),
      agentTask("child", status: .working, parent: "recent", lastActivityAt: "2026-11-04T11:00:00.000Z"),
    ]
    #expect(AgentsLogic.boardTasks(tasks, days: 3, now: now).map(\.id) == ["recent"])
    #expect(AgentsLogic.boardTasks(tasks, days: 7, now: now).map(\.id) == ["recent", "old"])
  }

  /// `AgentWorkspace.test.tsx`: server totals win over the loaded page.
  @Test func finishedCountsPreferServerTotals() {
    let tasks = [agentTask(status: .completed)]
    let counts = AgentsLogic.finishedCounts(tasks, board: board(tasks, counts: ["completed": 5, "failed": 1]))
    #expect(counts.map(\.count) == [5, 1, 0])
    #expect(AgentsLogic.finishedCounts(tasks, board: nil).map(\.count) == [1, 0, 0])
    #expect(AgentsLogic.finishedCountLabel(.failed, count: 1) == "1 falhou")
    #expect(AgentsLogic.finishedCountLabel(.completed, count: 2) == "2 concluídas")
  }

  @Test func filterCountAndEmptyText() {
    var query = AgentsEndpoints.BoardQuery()
    #expect(AgentsLogic.activeFilterCount(query) == 0)
    #expect(AgentsLogic.emptyBoardText(query).title == "Nenhuma tarefa nos últimos 3 dias")
    query.days = 30
    #expect(AgentsLogic.emptyBoardText(query).title == "Seu próximo trabalho começa aqui")
    query.status = .failed
    query.sort = .oldest
    query.sessionID = "s"
    #expect(AgentsLogic.activeFilterCount(query) == 4)
    #expect(AgentsLogic.emptyBoardText(query).title == "Nenhuma tarefa neste filtro")
  }

  @Test func waitedFor() {
    let now = iso("2026-10-24T03:30:00.000Z")
    #expect(AgentsLogic.waitedFor("2026-10-24T03:29:30.000Z", now: now) == "agora")
    #expect(AgentsLogic.waitedFor("2026-10-24T03:00:00.000Z", now: now) == "há 30 min")
    #expect(AgentsLogic.waitedFor(since, now: now) == "há 2 h")
  }

  @Test func formatsTimeInPortuguese() {
    let text = AgentsLogic.formatTime("2026-11-04T12:40:00Z", timeZone: TimeZone(identifier: "UTC") ?? .current)
    #expect(text.contains("04/11/2026"))
    #expect(text.contains("12:40"))
  }

  @Test func errorTexts() {
    let conflict = APIError.server(
      status: 409, message: "Task changed; reload before updating", code: "version_conflict", retry: .reconcile)
    #expect(AgentsLogic.changeMessage(conflict) == "O item mudou. Atualize os dados antes de tentar novamente.")
    let parent = APIError.server(status: 409, message: "x", code: "task_has_subtasks", retry: .reconcile)
    #expect(AgentsLogic.changeMessage(parent) == "Exclua as subtarefas antes de excluir a tarefa principal.")
    #expect(AgentsLogic.changeMessage(.offline) == APIError.offline.userMessage)
    let stopped = APIError.server(status: 409, message: "x", code: "session_stopped", retry: .never)
    #expect(AgentsLogic.sendMessage(stopped) == "A sessão do agente está encerrada.")
    #expect(AgentsLogic.sendMessage(.timedOut).hasPrefix("Não deu para confirmar a entrega"))
    #expect(AgentsLogic.pollMessage(.server(status: 404, message: "x", code: nil, retry: nil)).contains("expirou"))
  }
}
