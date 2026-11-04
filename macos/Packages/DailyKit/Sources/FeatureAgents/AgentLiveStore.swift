import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// The live terminal of a session and the reply box (`components/agents/LivePanel.tsx`).
@Observable
final class AgentLiveStore {
  enum Content: String, CaseIterable {
    case pane
    case response
  }

  struct Notice: Equatable {
    var isError: Bool
    var text: String
  }

  let sessionID: String
  private(set) var terminal: AgentTerminal?
  private(set) var error: String?
  var content: Content = .pane
  /// The reply being written.
  var text = ""
  private(set) var isSending = false
  private(set) var notice: Notice?

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let poller: Poller
  @ObservationIgnored private(set) var isPolling = false

  init(sessionID: String, client: any APIClient, poller: Poller) {
    self.sessionID = sessionID
    self.client = client
    self.poller = poller
  }

  /// Polls every 2 s while the panel is on screen, like the web's own `useAgentPolling`.
  func start() {
    guard !isPolling else { return }
    isPolling = true
    poller.register(AgentsStore.liveScope, foreground: Poller.Cadence.agents, background: nil) { [weak self] in
      await self?.load()
    }
  }

  func stop() {
    guard isPolling else { return }
    isPolling = false
    poller.unregister(AgentsStore.liveScope)
  }

  func load() async {
    do {
      terminal = try await client.send(AgentsEndpoints.live(sessionID: sessionID))
      error = nil
    } catch {
      Logger.agents.error("Live terminal load failed: \(String(describing: error), privacy: .public)")
      if AgentsLogic.dropsData(error) { terminal = nil }
      self.error = AgentsLogic.pollMessage(error)
    }
  }

  var snapshot: AgentTerminalSnapshot? {
    if case .available(let snapshot) = terminal { return snapshot }
    return nil
  }

  var isStopped: Bool { snapshot?.live.state == .stopped }

  var canSend: Bool {
    !isSending && !isStopped && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The hint under the box while nothing was sent (`LivePanel.tsx:98`).
  var hint: String {
    switch snapshot?.live.state {
    case .working?: "O agente está trabalhando; a mensagem espera o fim do turno."
    case .prompt?: "Há um menu aberto no terminal; a mensagem é entregue quando ele fechar."
    default: ""
    }
  }

  /// One key per reply: a retry after an unconfirmed delivery reuses it, an
  /// edit or a confirmed delivery starts a new one.
  private var replyKey: String?

  func setText(_ value: String) {
    let next = String(value.prefix(AgentsLogic.messageMax))
    if next != text { replyKey = nil }
    text = next
  }

  /// Sends the reply; the draft stays when the delivery is not confirmed.
  func send() async {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, !isSending, !isStopped else { return }
    isSending = true
    notice = nil
    defer { isSending = false }
    let key = replyKey ?? UUID().uuidString
    replyKey = key
    do {
      _ = try await client.send(AgentsEndpoints.message(sessionID: sessionID, text: message, key: key))
      replyKey = nil
      text = ""
      notice = Notice(isError: false, text: "Mensagem na fila: o agente recebe assim que o terminal estiver pronto.")
    } catch {
      Logger.agents.error("Agent message failed: \(String(describing: error), privacy: .public)")
      notice = Notice(isError: true, text: AgentsLogic.sendMessage(error))
    }
  }
}
