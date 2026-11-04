import DailyDesign
import DailyModels
import SwiftUI

/// The status on the row, as a picker of the transitions Jira allows from it
/// (`components/jira/actions/TransitionAction.tsx`).
struct TransitionPicker: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let store: JiraStore

  @State private var open = false
  @State private var phase: Phase = .loading
  @State private var request = 0

  enum Phase {
    case loading
    case failed(String)
    case choosing([JiraTransition])
    case confirming([JiraTransition], chosen: JiraTransition, sending: Bool, refusal: String?)
  }

  var body: some View {
    Button {
      open = true
      load()
    } label: {
      JiraStatusLabel(issue: issue)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("mudar status de \(issue.key) (\(issue.status))")
    .popover(isPresented: $open, arrowEdge: .bottom) {
      content
        .font(.system(size: 12))
        .padding(10)
        .frame(width: 288, alignment: .leading)
    }
  }

  private func load() {
    request += 1
    let mine = request
    phase = .loading
    Task {
      let result = await store.transitions(issue.key)
      guard mine == request else { return }
      switch result {
      case .success(let transitions): phase = .choosing(transitions)
      case .failure(let error): phase = .failed(error.userMessage)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch phase {
    case .loading:
      Text("carregando transições…").foregroundStyle(theme.inkDim)
    case .failed(let message):
      VStack(alignment: .leading, spacing: 8) {
        Text(message).foregroundStyle(theme.danger)
        Button("Tentar de novo", action: load).controlSize(.small)
      }
    case .choosing(let transitions):
      if transitions.isEmpty {
        Text("nenhuma transição disponível").foregroundStyle(theme.inkDim)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(transitions) { transition in option(transition, all: transitions) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("transições de \(issue.key)")
      }
    case .confirming(let transitions, let chosen, let sending, let refusal):
      VStack(alignment: .leading, spacing: 8) {
        Text("Mover \(issue.key) de \(issue.status) para \(chosen.to.name)?")
          .font(.system(size: 13))
          .foregroundStyle(theme.ink)
          .fixedSize(horizontal: false, vertical: true)
        JiraRefusal(message: refusal, issue: issue)
        HStack {
          Spacer()
          Button("Cancelar") { phase = .choosing(transitions) }
            .disabled(sending)
            .keyboardShortcut(.cancelAction)
          Button(sending ? "Movendo…" : "Confirmar") { confirm(transitions, chosen) }
            .buttonStyle(.borderedProminent)
            .disabled(sending)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private func option(_ transition: JiraTransition, all: [JiraTransition]) -> some View {
    Button {
      if transition.requires == .screen {
        // Fields only Jira can fill in: the web links straight to the issue.
        if let url = URL(string: issue.url) { openURL(url) }
      } else {
        phase = .confirming(all, chosen: transition, sending: false, refusal: nil)
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(transition.name).foregroundStyle(theme.ink)
        if transition.to.name != transition.name {
          Text("→ \(transition.to.name)").foregroundStyle(theme.inkDim)
        }
        if transition.requires == .screen {
          Text("pede campos — abrir no Jira").foregroundStyle(theme.warning)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }

  private func confirm(_ transitions: [JiraTransition], _ chosen: JiraTransition) {
    if case .confirming(_, _, true, _) = phase { return }
    phase = .confirming(transitions, chosen: chosen, sending: true, refusal: nil)
    Task {
      if let error = await store.transition(issue.key, to: chosen) {
        phase = .confirming(transitions, chosen: chosen, sending: false, refusal: error.userMessage)
      } else {
        open = false
      }
    }
  }
}
