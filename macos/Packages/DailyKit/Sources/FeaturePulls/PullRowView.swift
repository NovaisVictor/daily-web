import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// What a row asks the screen to do: open a dialog or book a focus block.
struct PullRowActions {
  var open: (PullAction, PullRequestItem) -> Void
  var scheduleFocus: ((PullRequestItem) -> Void)?
}

/// One pull request or issue (`components/pulls/PullRow.tsx`): two lines, the
/// title whole on the first and the situation below it.
struct PullRowView: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let item: PullRequestItem
  /// In the global lists the repository is the first thing to know.
  var withRepo = false
  let store: PullsStore
  let actions: PullRowActions

  private var ref: String { PullActionRules.ref(item) }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        titleLine
        FlowLayout(spacing: 8) {
          ForEach(item.jira ?? [], id: \.key) { jira in
            JiraRefLink(jira: jira)
          }
          ForEach(item.jira ?? [], id: \.key) { jira in
            if let suggestion = JiraSyncSuggestion.of(item, jira) {
              JiraSyncView(item: item, jira: jira, suggestion: suggestion, store: store)
            }
          }
          PullBadges(item: item, now: store.now())
          // The author only matters when it is not you: in your own repo it
          // is what tells your PR from the one dependabot opened.
          if !item.mine, !item.author.isEmpty {
            Text(item.author).typeRole(.caption).foregroundStyle(theme.inkDim)
          }
          if item.draft { Badge("rascunho", style: .secondary) }
          // In the reviews tab every row awaits review: the label would set nothing apart.
          if item.awaitingYou, !withRepo { Badge("revisar", style: .info) }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let schedule = actions.scheduleFocus {
        IconButton("agendar foco para \(ref)", systemImage: "calendar.badge.plus", size: .small) { schedule(item) }
      }
      actionsMenu
    }
    .contentShape(.rect)
    .draggableIfPresent(actions.scheduleFocus == nil ? nil : PullsStore.focusSource(item))
    .contextMenu { menuContent(includeExtras: true) }
  }

  private var titleLine: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      if withRepo {
        if let url = GitHubNames.repoURL(item.repo) {
          Link(item.repo, destination: url)
            .foregroundStyle(theme.inkDim)
            .lineLimit(1)
            .frame(maxWidth: 220, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(item.repo).foregroundStyle(theme.inkDim).lineLimit(1)
        }
      }
      Text("#\(item.number)").monospacedDigit().foregroundStyle(theme.inkDim)
      if let url = URL(string: item.url) {
        Link(item.title.isEmpty ? "—" : item.title, destination: url)
          .foregroundStyle(theme.ink)
          .lineLimit(1)
          .truncationMode(.tail)
      } else {
        Text(item.title.isEmpty ? "—" : item.title).foregroundStyle(theme.ink).lineLimit(1)
      }
    }
    .font(.daily(size: 14))
  }

  private var actionsMenu: some View {
    IconMenu("ações de \(ref)", systemImage: "ellipsis", size: .small) {
      menuContent(includeExtras: false)
    }
  }

  @ViewBuilder
  private func menuContent(includeExtras: Bool) -> some View {
    ForEach(PullAction.entries(for: item)) { action in
      Button(action.label, systemImage: action.systemImage) { actions.open(action, item) }
    }
    if includeExtras {
      Divider()
      if let url = URL(string: item.url) {
        Button("Abrir no GitHub", systemImage: "arrow.up.right.square") { openURL(url) }
      }
      if let schedule = actions.scheduleFocus {
        Button("Agendar foco", systemImage: "calendar.badge.plus") { schedule(item) }
      }
    }
  }
}

/// A Jira card cited in the PR: key and current status (`JiraStatus`).
struct JiraRefLink: View {
  @Environment(\.theme) private var theme
  let jira: PullJiraRef

  var body: some View {
    let content = HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(jira.key).font(.dailyMono(size: 12)).foregroundStyle(theme.brand)
      Text(glyph).foregroundStyle(tone).accessibilityHidden(true)
      Text(PullFormat.status(jira.status)).foregroundStyle(tone)
    }
    .typeRole(.caption)
    if let url = URL(string: jira.url) {
      Link(destination: url) { content }
        .buttonStyle(.plain)
        .help("\(jira.key) no Jira")
    } else {
      content
    }
  }

  private var glyph: String {
    switch jira.statusCategory {
    case .done: StatusGlyph.live.rawValue
    case .indeterminate: StatusGlyph.moving.rawValue
    default: StatusGlyph.idle.rawValue
    }
  }

  private var tone: Color {
    switch jira.statusCategory {
    case .done: theme.success
    case .indeterminate: theme.info
    default: theme.inkDim
    }
  }
}

/// CI, review, conflict, size and age (`components/pulls/PullBadges.tsx`).
struct PullBadges: View {
  @Environment(\.theme) private var theme
  let item: PullRequestItem
  let now: Date

  var body: some View {
    if item.isPullRequest {
      ciBadge
      reviewBadge
      if item.merge == .conflict {
        Badge("\(StatusGlyph.alert.rawValue) conflito", style: .danger).accessibilityLabel("conflito")
      }
      if let size = item.size {
        Text("+\(PullFormat.number(size.additions)) −\(PullFormat.number(size.deletions))")
          .typeRole(.caption)
          .monospacedDigit()
          .foregroundStyle(theme.inkDim)
          .help("\(PullFormat.number(size.files)) arquivo(s) alterado(s)")
      }
    }
    if let age = PullAge.age(createdAt: item.createdAt, updatedAt: item.updatedAt, now: now) {
      HStack(spacing: 0) {
        Text(age.opened)
        if let stalled = age.stalled {
          Text(" · ")
          Text(stalled).foregroundStyle(theme.warning)
        }
      }
      .typeRole(.caption)
      .foregroundStyle(theme.inkDim)
    }
  }

  @ViewBuilder
  private var ciBadge: some View {
    switch item.ci {
    case .running:
      Badge("\(StatusGlyph.moving.rawValue) CI rodando", style: .info).accessibilityLabel("CI rodando")
    case .passing:
      Text("\(StatusGlyph.live.rawValue) CI ok").typeRole(.caption).foregroundStyle(theme.success)
        .accessibilityLabel("CI ok")
    case .failing:
      let names = item.failedChecks.map(\.name).joined(separator: ", ")
      let ref = PullActionRules.ref(item)
      let badge = Badge("\(StatusGlyph.alert.rawValue) CI falhou", style: .danger)
        .help(names.isEmpty ? "" : "Falharam: \(names)")
      if let link = item.failedChecks.first?.url.flatMap(URL.init(string:)) {
        Link(destination: link) { badge }
          .buttonStyle(.plain)
          .accessibilityLabel(names.isEmpty ? "CI falhou em \(ref)" : "CI falhou em \(ref): \(names)")
      } else {
        badge.accessibilityLabel("CI falhou")
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var reviewBadge: some View {
    switch item.review {
    case .changesRequested:
      Badge("\(StatusGlyph.alert.rawValue) pediram mudanças", style: .warning).accessibilityLabel("pediram mudanças")
    case .approved:
      Badge("\(StatusGlyph.live.rawValue) aprovado", style: .success).accessibilityLabel("aprovado")
    case .pending:
      Badge("\(StatusGlyph.idle.rawValue) aguardando revisão", style: .secondary)
        .help(item.pendingReviewers.isEmpty ? "" : "Aguardando: \(item.pendingReviewers.joined(separator: ", "))")
        .accessibilityLabel("aguardando revisão")
    default:
      EmptyView()
    }
  }
}

/// Moves the cited card to match the PR, after confirming (`PullJiraSync.tsx`).
struct JiraSyncView: View {
  @Environment(\.theme) private var theme
  let item: PullRequestItem
  let jira: PullJiraRef
  let suggestion: JiraSyncSuggestion
  let store: PullsStore

  var body: some View {
    switch suggestion {
    case .diverged:
      HStack(spacing: 0) {
        if let url = URL(string: jira.url) {
          Link(jira.key, destination: url)
        } else {
          Text(jira.key)
        }
        Text(": card concluído com ")
        if let url = URL(string: item.url) {
          Link("PR aberto", destination: url)
        } else {
          Text("PR aberto")
        }
      }
      .typeRole(.caption)
      .foregroundStyle(theme.warning)
      .tint(theme.warning)
    case .move(let intent):
      MoveCardButton(jira: jira, intent: intent, store: store)
    }
  }
}

private struct MoveCardButton: View {
  @Environment(\.theme) private var theme
  let jira: PullJiraRef
  let intent: JiraSyncIntent
  let store: PullsStore

  private enum Phase: Equatable {
    case loading
    case failed(String)
    case confirming(JiraTransition, sending: Bool, refusal: String?)
  }

  @State private var open = false
  @State private var phase = Phase.loading
  @State private var request = 0

  var body: some View {
    Button("\(jira.key) → \(intent.label)") { open = true }
      .buttonStyle(.plain)
      .typeRole(.caption)
      .foregroundStyle(theme.brand)
      .accessibilityLabel("mover \(jira.key) para \(intent.label)")
      .popover(isPresented: $open, arrowEdge: .bottom) {
        content
          .padding(12)
          .frame(width: 288, alignment: .leading)
      }
      .onChange(of: open) { _, isOpen in
        if isOpen { load() }
      }
  }

  @ViewBuilder
  private var content: some View {
    switch phase {
    case .loading:
      Text("procurando a transição…").typeRole(.caption).foregroundStyle(theme.inkDim)
    case .failed(let error):
      VStack(alignment: .leading, spacing: 8) {
        Text(error).foregroundStyle(theme.danger)
        openInJira
      }
      .typeRole(.caption)
    case .confirming(let transition, let sending, let refusal):
      if transition.requires == .screen {
        VStack(alignment: .leading, spacing: 8) {
          Text("\(transition.name) → \(transition.to.name)").font(.daily(size: 14))
          if let url = URL(string: jira.url) {
            Link("pede campos — abrir no Jira", destination: url).foregroundStyle(theme.warning)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Mover \(jira.key) de \(jira.status) para \(transition.to.name)?").font(.daily(size: 14))
          if let refusal {
            HStack(spacing: 4) {
              Text("\(refusal) ·").foregroundStyle(theme.danger)
              openInJira
            }
            .typeRole(.caption)
          }
          HStack {
            Spacer()
            Button("Cancelar") { open = false }
              .pillButtonStyle(.outline, size: .small)
              .disabled(sending)
              .keyboardShortcut(.cancelAction)
            Button(sending ? "Movendo…" : "Confirmar") { confirm(transition) }
              .pillButtonStyle(.primary, size: .small)
              .disabled(sending)
              .keyboardShortcut(.defaultAction)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var openInJira: some View {
    if let url = URL(string: jira.url) {
      Link(destination: url) {
        Label("abrir no Jira", systemImage: "arrow.up.right.square").labelStyle(.titleAndIcon)
      }
    }
  }

  /// Answers that arrive after a newer request are dropped.
  private func load() {
    request += 1
    let mine = request
    phase = .loading
    Task {
      let target = await store.jiraTarget(key: jira.key, intent: intent)
      guard mine == request else { return }
      switch target {
      case .failed(let error): phase = .failed(error)
      case .confirm(let transition): phase = .confirming(transition, sending: false, refusal: nil)
      }
    }
  }

  private func confirm(_ transition: JiraTransition) {
    guard case .confirming(_, false, _) = phase else { return }
    phase = .confirming(transition, sending: true, refusal: nil)
    Task {
      if let refusal = await store.moveCard(key: jira.key, transition: transition) {
        phase = .confirming(transition, sending: false, refusal: refusal)
      } else {
        open = false
      }
    }
  }
}

extension View {
  /// `.draggable` only when there is something to drag.
  @ViewBuilder
  func draggableIfPresent<Payload: Transferable>(_ payload: Payload?) -> some View {
    if let payload {
      draggable(payload)
    } else {
      self
    }
  }
}
