import DailyDesign
import DailyModels
import SwiftUI

/// One dialog of the row menu, holding the item as it was when opened: a write
/// can change the item (approved, merged) so that the menu no longer offers the
/// action, and the open dialog still shows its answer.
struct PullActionRequest: Identifiable {
  let id = UUID()
  let action: PullAction
  let item: PullRequestItem
}

/// The dialogs of `components/pulls/PullActions.tsx`, with the web's texts.
struct PullActionSheet: View {
  @Environment(\.theme) private var theme
  @Environment(\.dismiss) private var dismiss
  let request: PullActionRequest
  let store: PullsStore

  @State private var text = ""
  @State private var chosen: [String] = []
  @State private var typed = ""
  @State private var method = MergeMethod.squash
  @State private var sending = false
  @State private var refusal: String?
  @State private var outcome: String?

  private var item: PullRequestItem { request.item }
  private var ref: String { PullActionRules.ref(item) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).typeRole(.subhead).foregroundStyle(theme.ink)
        Text(item.title).font(.geist(13)).foregroundStyle(theme.inkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let outcome {
        done(outcome)
      } else {
        form
      }
    }
    .padding(20)
    .frame(width: 460)
    // Escape while the write is in flight would hide the answer to a request
    // that still lands on GitHub.
    .interactiveDismissDisabled(sending)
  }

  private var title: String {
    switch request.action {
    case .approve: "Aprovar \(ref)"
    case .requestChanges: "Pedir mudanças em \(ref)"
    case .comment: "Comentar em \(ref)"
    case .rerequest: "Pedir revisão de novo em \(ref)"
    case .merge: "Fazer merge de \(ref)"
    case .rerun: "Rodar CI de novo em \(ref)"
    }
  }

  private func done(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 4) {
        Text("\(message) ·")
        if let url = URL(string: item.url) {
          Link("abrir \(ref) no GitHub", destination: url).underline()
        }
      }
      .font(.geist(14))
      .foregroundStyle(theme.ink)
      .accessibilityElement(children: .combine)
      HStack {
        Spacer()
        Button("Fechar") { dismiss() }
          .pillButtonStyle()
          .keyboardShortcut(.defaultAction)
      }
    }
    .onAppear { AccessibilityNotification.Announcement(message).post() }
  }

  @ViewBuilder
  private var form: some View {
    switch request.action {
    case .approve, .requestChanges, .comment: textForm
    case .rerequest: rerequestForm
    case .merge: mergeForm
    case .rerun: rerunForm
    }
  }

  // MARK: - Text dialogs (approve, request changes, comment)

  private var hint: String {
    switch request.action {
    case .approve: "comentário opcional, publicado junto com a aprovação"
    case .requestChanges: "diga o que precisa mudar — o comentário é obrigatório"
    default: "vai aparecer como seu comentário no GitHub"
    }
  }

  private var trimmedLength: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
  private var tooLong: Bool { trimmedLength > GitHubNames.textMax }
  private var textReady: Bool { !tooLong && (request.action == .approve || trimmedLength > 0) }

  private var textForm: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: $text)
        .font(.geist(14))
        .frame(minHeight: 96)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(theme.surface2, in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.lineStrong) }
        .disabled(sending)
        .accessibilityLabel("comentário em \(ref)")
        .accessibilityHint(hint)
      problem(refusal ?? (tooLong ? "passou de \(GitHubNames.textMax) caracteres (\(trimmedLength))" : nil))
      Text(hint).typeRole(.caption).foregroundStyle(theme.inkDim)
      footer(ready: textReady, label: textLabel.label, pending: textLabel.pending) {
        switch request.action {
        case .approve: await store.approve(item, comment: text)
        case .requestChanges: await store.requestChanges(item, comment: text)
        default: await store.comment(item, text: text)
        }
      }
    }
  }

  private var textLabel: (label: String, pending: String) {
    switch request.action {
    case .approve: ("Aprovar", "Aprovando…")
    case .requestChanges: ("Pedir mudanças", "Enviando…")
    default: ("Comentar", "Comentando…")
    }
  }

  // MARK: - Re-request review

  private var rerequestProblem: String? { PullActionRules.rerequestProblem(chosen: chosen, typed: typed) }

  private var rerequestForm: some View {
    let listed = PullActionRules.rerequestCandidates(item)
    let reviewers = PullActionRules.reviewers(chosen: chosen, typed: typed)
    return VStack(alignment: .leading, spacing: 12) {
      if !listed.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("revisores").typeRole(.caption).foregroundStyle(theme.inkDim)
          ForEach(listed, id: \.self) { reviewer in
            Toggle(
              reviewer,
              isOn: Binding(
                get: { chosen.contains(reviewer) },
                set: { on in
                  if on { chosen.append(reviewer) } else { chosen.removeAll { $0 == reviewer } }
                })
            )
            .toggleStyle(.checkbox)
          }
        }
        .disabled(sending)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("outros logins (separados por vírgula)").font(.geist(13))
        TextField("outros logins (separados por vírgula)", text: $typed)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .disabled(sending)
      }
      problem(refusal ?? rerequestProblem)
      footer(ready: !reviewers.isEmpty && rerequestProblem == nil, label: "Pedir revisão", pending: "Pedindo…") {
        await store.requestReviewers(item, chosen: chosen, typed: typed)
      }
    }
  }

  // MARK: - Merge

  private var mergeForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(item.headRef ?? "") → \(item.baseRef ?? "")")
        .font(.dailyMono(size: 14))
        .foregroundStyle(theme.ink)
      Picker("método", selection: $method) {
        ForEach(MergeMethod.allCases, id: \.self) { method in
          Text(method.label).tag(method)
        }
      }
      .pickerStyle(.radioGroup)
      .disabled(sending)
      Text(
        "só entra o commit \(String((item.headSha ?? "").prefix(7))) que você está vendo; se o PR mudou, o merge é recusado"
      )
      .typeRole(.caption)
      .foregroundStyle(theme.inkDim)
      .fixedSize(horizontal: false, vertical: true)
      problem(refusal)
      footer(ready: true, label: "Fazer merge", pending: "Fazendo merge…", destructive: true) {
        await store.merge(item, method: method)
      }
    }
  }

  // MARK: - Re-run CI

  private var rerunForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("roda de novo só os jobs que falharam no GitHub Actions deste commit").font(.geist(14))
      if !item.failedChecks.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(item.failedChecks, id: \.name) { check in
            Text("• \(check.name)")
          }
        }
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("checks com falha: \(item.failedChecks.map(\.name).joined(separator: ", "))")
      }
      problem(refusal)
      footer(ready: true, label: "Rodar de novo", pending: "Pedindo…") {
        await store.rerun(item)
      }
    }
  }

  // MARK: - Shared pieces

  @ViewBuilder
  private func problem(_ text: String?) -> some View {
    if let text {
      Text(text)
        .typeRole(.caption)
        .foregroundStyle(theme.danger)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isStaticText)
    }
  }

  private func footer(
    ready: Bool,
    label: String,
    pending: String,
    destructive: Bool = false,
    send: @escaping () async -> PullWriteOutcome
  ) -> some View {
    HStack(spacing: 8) {
      Spacer()
      Button("Cancelar") { dismiss() }
        .pillButtonStyle(.outline)
        .disabled(sending)
        .keyboardShortcut(.cancelAction)
      Button(sending ? pending : label, role: destructive ? .destructive : nil) {
        submit(send)
      }
      .pillButtonStyle(destructive ? .destructive : .primary)
      .disabled(!ready || sending)
      .keyboardShortcut(.defaultAction)
    }
  }

  private func submit(_ send: @escaping () async -> PullWriteOutcome) {
    guard !sending else { return }
    sending = true
    refusal = nil
    Task {
      let result = await send()
      sending = false
      switch result {
      case .done(let message): outcome = message
      case .refused(let message):
        refusal = message
        AccessibilityNotification.Announcement(message).post()
      }
    }
  }
}
