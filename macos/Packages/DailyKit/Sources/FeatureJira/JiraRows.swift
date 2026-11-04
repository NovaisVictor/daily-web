import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// What a row can ask of the screen.
struct JiraRowActions {
  let open: (JiraDialog) -> Void
  let focusEnabled: Bool
  let pulls: [String: [PullRequestItem]]
  /// First name of the followed person on screen, empty for the user.
  let personName: String
  let now: Date

  func focusSource(_ issue: JiraItem) -> FocusSource? {
    focusEnabled ? FocusSource(kind: .jira, ref: issue.key, title: issue.summary, url: issue.url) : nil
  }
}

/// The row's "⋯" menu (`IssueActions`): every write that is not the status or the approval.
struct JiraIssueMenu: View {
  let issue: JiraItem
  let actions: JiraRowActions

  var body: some View {
    Menu {
      JiraIssueMenuItems(issue: issue, actions: actions)
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel("ações de \(issue.key)")
  }
}

/// The items shared by the "⋯" menu and the row's context menu
/// (`CommentMenuItem`, `FlagMenuItem`, `EditMenuItems`).
struct JiraIssueMenuItems: View {
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let actions: JiraRowActions

  var body: some View {
    Button("Comentar", systemImage: "text.bubble") { actions.open(.comment(issue)) }
    Button(issue.flag == .impediment ? "Remover impedimento" : "Marcar impedimento", systemImage: "flag") {
      actions.open(.flag(issue))
    }
    Divider()
    Button("Alterar prazo") { actions.open(.due(issue)) }
    Button("Alterar prioridade") { actions.open(.priority(issue)) }
    // Always offered: `role` does not say who the assignee is.
    Button("Atribuir a mim") { actions.open(.assign(issue)) }
    if JiraText.isEpic(issue) {
      Button("Criar história neste épico") { actions.open(.createStory(issue)) }
    }
  }
}

/// The "abrir no Jira" and "agendar foco" items of a row's context menu.
struct JiraRowContextItems: View {
  @Environment(\.openURL) private var openURL
  let issue: JiraItem
  let actions: JiraRowActions

  var body: some View {
    Button("Abrir no Jira", systemImage: "arrow.up.right.square") {
      if let url = URL(string: issue.url) { openURL(url) }
    }
    if let source = actions.focusSource(issue) {
      Button("Agendar foco", systemImage: "calendar.badge.plus") { actions.open(.focus(source)) }
    }
  }
}

/// One issue of the lists (`JiraRow`, `components/JiraPanel.tsx:1265-1453`).
struct JiraRowView: View {
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let store: JiraStore
  let actions: JiraRowActions
  var depth = 0
  var children = 0
  var isOpen = false
  var origin: JiraNodeOrigin = .match
  var showRole = false
  var toggle: (() -> Void)?

  var body: some View {
    let stale = JiraText.stalenessLabel(issue, now: actions.now)
    let due = issue.dueDate.isEmpty ? nil : JiraText.dueLabel(issue.dueDate, now: actions.now)
    let overdue = !issue.dueDate.isEmpty && JiraText.isOverdue(issue.dueDate, now: actions.now)
    HStack(alignment: .top, spacing: 10) {
      if depth > 0 {
        // A branch tick reads as hierarchy without drawing a full tree of guides.
        UnevenRoundedRectangle(bottomLeadingRadius: 3)
          .stroke(theme.lineStrong, lineWidth: 1)
          .frame(width: 8, height: 8)
          .padding(.top, 4)
          .accessibilityHidden(true)
      }
      caret
      Text(JiraText.issueMarker(issue))
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          JiraKeyLink(issue: issue)
          if issue.flag == .impediment {
            if origin == .ancestor {
              JiraFlagMark()
            } else {
              FlagIndicator(issue: issue, actions: actions)
            }
          }
          Text(issue.summary)
            .foregroundStyle(origin == .ancestor ? theme.inkDim : theme.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
          if showRole, issue.role == .reporter { JiraRoleBadge(text: "REL") }
          if issue.awaitingApproval { approvalBadge }
        }
        FlowLayout(spacing: 10) {
          if origin == .ancestor {
            JiraStatusLabel(issue: issue)
          } else {
            TransitionPicker(issue: issue, store: store)
          }
          JiraPriorityLabel(issue: issue)
          if let stale { Text(stale).font(.system(size: 12)).foregroundStyle(theme.warning) }
          if let due {
            Text(due).font(.system(size: 12)).foregroundStyle(overdue ? theme.danger : theme.inkDim)
          }
        }
        JiraPullLinks(key: issue.key, pulls: actions.pulls[issue.key] ?? [])
      }
      if let source = actions.focusSource(issue) {
        Button {
          actions.open(.focus(source))
        } label: {
          Image(systemName: "calendar.badge.plus")
        }
        .buttonStyle(.borderless)
        .help("agendar foco para \(issue.key)")
        .accessibilityLabel("agendar foco para \(issue.key)")
      }
      if origin != .ancestor { JiraIssueMenu(issue: issue, actions: actions) }
    }
    .padding(.leading, CGFloat(depth) * 24)
    .padding(.vertical, 10)
    .contentShape(.rect)
    .draggableIfPresent(actions.focusSource(issue))
    .contextMenu {
      JiraRowContextItems(issue: issue, actions: actions)
      if origin != .ancestor {
        Divider()
        JiraIssueMenuItems(issue: issue, actions: actions)
      }
    }
  }

  @ViewBuilder
  private var caret: some View {
    // The arrow exists only where there is something to reveal; the spacer
    // keeps the column aligned.
    if children > 0, let toggle {
      let what = children == 1 ? "a issue" : "as \(children) issues"
      Button(action: toggle) {
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .rotationEffect(.degrees(isOpen ? 90 : 0))
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .foregroundStyle(theme.inkDim)
      .accessibilityLabel("\(isOpen ? "recolher" : "expandir") \(what) sob \(issue.key)")
      .accessibilityValue(isOpen ? "expandido" : "recolhido")
    } else {
      Color.clear.frame(width: 18, height: 18).accessibilityHidden(true)
    }
  }

  /// `ApprovalBadge`: on someone else's queue it stays a mark, since only the
  /// logged-in user answers their own approvals.
  @ViewBuilder
  private var approvalBadge: some View {
    let title =
      actions.personName.isEmpty ? "aguardando a sua aprovação" : "aguardando a aprovação de \(actions.personName)"
    if store.activePerson != nil {
      JiraRoleBadge(text: "APROV", tone: .warning, bold: true).help(title)
    } else {
      Button {
        actions.open(.approval(issue))
      } label: {
        JiraRoleBadge(text: "APROV", tone: .warning, bold: true)
      }
      .buttonStyle(.plain)
      .help(title)
      .accessibilityLabel("aprovar ou recusar \(issue.key)")
    }
  }
}

/// The impediment mark, made clickable: it offers to remove the impediment
/// (`FlagIndicator`).
struct FlagIndicator: View {
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let actions: JiraRowActions

  var body: some View {
    Button {
      actions.open(.flag(issue))
    } label: {
      Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(theme.danger)
    }
    .buttonStyle(.plain)
    .help("impedimento")
    .accessibilityLabel("impedimento")
  }
}

/// A node and, when open, its children (`JiraBranch`).
struct JiraBranchView: View {
  let node: JiraNode
  let store: JiraStore
  let actions: JiraRowActions
  let depth: Int
  let showRole: Bool

  var body: some View {
    let open = store.isOpen(node)
    JiraRowView(
      issue: node.issue, store: store, actions: actions, depth: depth, children: node.children.count, isOpen: open,
      origin: node.origin, showRole: showRole, toggle: { store.toggle(node) }
    )
    .id(node.issue.key)
    .jiraRowBackground(highlighted: store.revealed == node.issue.key)
    Divider()
    if open {
      ForEach(node.children) { child in
        JiraBranchView(node: child, store: store, actions: actions, depth: depth + 1, showRole: showRole)
      }
    }
  }
}

/// One block per project with its tree (`JiraProjects`).
struct JiraProjectsView: View {
  let groups: [JiraProjectGroup]
  let store: JiraStore
  let actions: JiraRowActions
  var showRole = false

  var body: some View {
    ForEach(groups) { group in
      VStack(alignment: .leading, spacing: 0) {
        JiraGroupHeading(title: group.project, count: group.count)
        ForEach(group.roots) { node in
          JiraBranchView(node: node, store: store, actions: actions, depth: 0, showRole: showRole)
        }
      }
      .padding(.top, 16)
    }
  }
}

/// A problem row: what the issue is and everything missing in it (`JiraProblemRow`).
struct JiraProblemRowView: View {
  @Environment(\.theme) private var theme
  let issue: JiraProblemItem
  let store: JiraStore
  let actions: JiraRowActions

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(JiraText.issueMarker(issue.item)).typeRole(.caption).foregroundStyle(theme.inkDim)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          JiraKeyLink(issue: issue.item)
          if issue.flag == .impediment { FlagIndicator(issue: issue.item, actions: actions) }
          Text(issue.summary).foregroundStyle(theme.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        FlowLayout(spacing: 10) {
          TransitionPicker(issue: issue.item, store: store)
          JiraPriorityLabel(issue: issue.item)
          ForEach(issue.problems, id: \.self) { problem in
            JiraRoleBadge(text: JiraText.problemLabel(problem), tone: .warning)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("problemas de \(issue.key)")
        JiraPullLinks(key: issue.key, pulls: actions.pulls[issue.key] ?? [])
        ProblemFixView(issue: issue, store: store)
      }
      JiraIssueMenu(issue: issue.item, actions: actions)
    }
    .padding(.vertical, 10)
    .contentShape(.rect)
    .contextMenu {
      JiraRowContextItems(issue: issue.item, actions: actions)
      Divider()
      JiraIssueMenuItems(issue: issue.item, actions: actions)
    }
  }
}

/// A watched issue, with "parar de acompanhar".
struct JiraWatchedRowView: View {
  @Environment(\.theme) private var theme
  let issue: JiraItem
  let actions: JiraRowActions
  let unwatch: () -> Void

  var body: some View {
    let stale = JiraText.stalenessLabel(issue, now: actions.now)
    let due = issue.dueDate.isEmpty ? nil : JiraText.dueLabel(issue.dueDate, now: actions.now)
    HStack(alignment: .top, spacing: 10) {
      Text(JiraText.issueMarker(issue)).typeRole(.caption).foregroundStyle(theme.inkDim).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          JiraKeyLink(issue: issue)
          Text(issue.summary).foregroundStyle(theme.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        FlowLayout(spacing: 10) {
          JiraStatusLabel(issue: issue)
          if let stale { Text(stale).font(.system(size: 12)).foregroundStyle(theme.warning) }
          if let due {
            Text(due).font(.system(size: 12))
              .foregroundStyle(JiraText.isOverdue(issue.dueDate, now: actions.now) ? theme.danger : theme.inkDim)
          }
        }
      }
      Button(action: unwatch) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(theme.inkDim)
      .help("parar de acompanhar \(issue.key)")
      .accessibilityLabel("parar de acompanhar \(issue.key)")
    }
    .padding(.vertical, 10)
    .contextMenu { JiraRowContextItems(issue: issue, actions: actions) }
  }
}

extension View {
  /// The revealed row of a notification gets the brand tint.
  func jiraRowBackground(highlighted: Bool) -> some View {
    modifier(JiraRowHighlight(highlighted: highlighted))
  }
}

private struct JiraRowHighlight: ViewModifier {
  @Environment(\.theme) private var theme
  let highlighted: Bool

  func body(content: Content) -> some View {
    content.background(highlighted ? theme.brandTint : .clear, in: .rect(cornerRadius: 6))
  }
}
