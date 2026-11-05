import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Sessão ao vivo" (`components/agents/LivePanel.tsx`): the captured terminal
/// or the reason it is missing, and the reply box.
struct AgentLivePanel: View {
  @Environment(\.theme) private var theme
  @Bindable var store: AgentLiveStore
  let now: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Sessão ao vivo", systemImage: "terminal")
          .font(.daily(size: 14, weight: .semibold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if let snapshot = store.snapshot { liveState(snapshot.live) }
      }
      if store.terminal == nil && store.error == nil {
        Text("Conectando ao terminal…").font(.daily(size: 13)).foregroundStyle(theme.inkMid)
      }
      if let error = store.error {
        Text(error).font(.daily(size: 13)).foregroundStyle(theme.danger)
      }
      switch store.terminal {
      case .unavailable(let reason)?:
        Text(AgentsLogic.unavailableText(reason))
          .font(.daily(size: 13))
          .foregroundStyle(theme.inkMid)
          .fixedSize(horizontal: false, vertical: true)
      case .available(let snapshot)?:
        available(snapshot)
      case nil:
        EmptyView()
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .agentsCard()
  }

  private func liveState(_ live: AgentLive) -> some View {
    HStack(spacing: 6) {
      Circle().fill(theme.liveColor(live.state)).frame(width: 8, height: 8).accessibilityHidden(true)
      Text(AgentsLogic.liveLabel(live.state))
      if let since = live.since {
        Text("· última atividade \(AgentsLogic.waitedFor(since, now: now))").foregroundStyle(theme.inkDim)
      }
    }
    .font(.daily(size: 11))
    .foregroundStyle(theme.inkMid)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func available(_ snapshot: AgentTerminalSnapshot) -> some View {
    SegmentedPills(
      "Conteúdo da sessão",
      items: [
        .init(id: AgentLiveStore.Content.pane, label: "Terminal"),
        .init(id: AgentLiveStore.Content.response, label: "Última resposta"),
      ],
      selection: $store.content,
      style: .toggle)

    ScrollViewReader { proxy in
      ScrollView {
        Text(screenText(snapshot))
          .font(.dailyMono(size: 11))
          .foregroundStyle(theme.ink)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        Color.clear.frame(height: 1).id(Self.bottomID)
      }
      .frame(minHeight: 160, maxHeight: 512)
      .background(theme.surface2, in: .rect(cornerRadius: Radius.medium))
      .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.line) }
      // Follows the end of the pane as the web does while pinned to the bottom.
      .onChange(of: snapshot.pane, initial: true) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
      .onChange(of: store.content) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    }

    Text(caption(snapshot)).font(.daily(size: 11)).foregroundStyle(theme.inkDim)

    reply(snapshot)
  }

  private static let bottomID = "live-bottom"

  private func screenText(_ snapshot: AgentTerminalSnapshot) -> String {
    switch store.content {
    case .pane: snapshot.pane.isEmpty ? "Terminal vazio." : snapshot.pane
    case .response:
      (snapshot.response?.content).flatMap { $0.isEmpty ? nil : $0 } ?? "Nenhuma resposta registrada ainda."
    }
  }

  private func caption(_ snapshot: AgentTerminalSnapshot) -> String {
    var prefix = ""
    if store.content == .response, let at = snapshot.response?.at {
      prefix = "Resposta de \(AgentsLogic.formatTime(at)) · "
    }
    return prefix + "Atualizado \(AgentsLogic.formatTime(snapshot.capturedAt)). Nada disso fica salvo no servidor."
  }

  private func reply(_ snapshot: AgentTerminalSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Responder ao agente").font(.daily(size: 13, weight: .medium))
      TextEditor(text: Binding(get: { store.text }, set: { store.setText($0) }))
        .font(.daily(size: 13))
        .frame(minHeight: 64, maxHeight: 140)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
        .overlay(alignment: .topLeading) {
          if store.text.isEmpty {
            Text("Escreva como se estivesse no terminal. ⌘↩ envia.")
              .font(.daily(size: 13))
              .foregroundStyle(theme.inkDim)
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineStrong) }
        .disabled(store.isStopped)
        .accessibilityLabel("Responder ao agente")
      HStack(spacing: 8) {
        Text(store.notice?.text ?? store.hint)
          .font(.daily(size: 11))
          .foregroundStyle(store.notice?.isError == true ? theme.danger : theme.inkMid)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          Task { await store.send() }
        } label: {
          Label(store.isSending ? "Enviando…" : "Enviar", systemImage: "paperplane")
        }
        .pillButtonStyle(size: .small)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!store.canSend)
      }
    }
  }
}
