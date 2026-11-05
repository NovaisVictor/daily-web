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
    IconMenu("ações de \(issue.key)", systemImage: "ellipsis", size: .small) {
      JiraIssueMenuItems(issue: issue, actions: actions)
    }
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
    HStack(alignment: .top, spacing: 12) {
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
          if let stale { Text(stale).font(.daily(size: 12)).foregroundStyle(theme.warning) }
          if let due {
            Text(due).font(.daily(size: 12)).foregroundStyle(overdue ? theme.danger : theme.inkDim)
          }
        }
        JiraPullLinks(key: issue.key, pulls: actions.pulls[issue.key] ?? [])
      }
      if let source = actions.focusSource(issue) {
        IconButton("agendar foco para \(issue.key)", systemImage: "calendar.badge.plus", size: .small) {
          actions.open(.focus(source))
        }
      }
      if origin != .ancestor { JiraIssueMenu(issue: issue, actions: actions) }
    }
    .padding(.leading, CGFloat(depth) * 24)
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
      }
      .buttonStyle(JiraCaretStyle(isOpen: isOpen))
      .focusEffectDisabled()
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

/// One block per project with its tree (`JiraProjects`, `JiraBranch`). The open
/// branches are laid out as one flat list so every row knows its place in the zebra.
struct JiraProjectsView: View {
  let groups: [JiraProjectGroup]
  let store: JiraStore
  let actions: JiraRowActions
  var showRole = false

  var body: some View {
    ForEach(groups) { group in
      let rows = JiraTree.visibleRows(group.roots, isOpen: store.isOpen)
      VStack(alignment: .leading, spacing: 0) {
        JiraGroupHeading(title: group.project, count: group.count)
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          let node = row.node
          ListRow(index: index, isLast: index == rows.count - 1, isActive: store.revealed == node.issue.key) {
            JiraRowView(
              issue: node.issue, store: store, actions: actions, depth: row.depth, children: node.children.count,
              isOpen: store.isOpen(node), origin: node.origin, showRole: showRole, toggle: { store.toggle(node) })
          }
          .id(node.issue.key)
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
    HStack(alignment: .top, spacing: 12) {
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
    HStack(alignment: .top, spacing: 12) {
      Text(JiraText.issueMarker(issue)).typeRole(.caption).foregroundStyle(theme.inkDim).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          JiraKeyLink(issue: issue)
          Text(issue.summary).foregroundStyle(theme.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        FlowLayout(spacing: 10) {
          JiraStatusLabel(issue: issue)
          if let stale { Text(stale).font(.daily(size: 12)).foregroundStyle(theme.warning) }
          if let due {
            Text(due).font(.daily(size: 12))
              .foregroundStyle(JiraText.isOverdue(issue.dueDate, now: actions.now) ? theme.danger : theme.inkDim)
          }
        }
      }
      IconButton("parar de acompanhar \(issue.key)", systemImage: "xmark", size: .small, action: unwatch)
    }
    .contentShape(.rect)
    .contextMenu { JiraRowContextItems(issue: issue, actions: actions) }
  }
}

/// The tree caret (`caret`, `JiraPanel.tsx:105-106` and :1365-1374): a 14pt arrow in an
/// 18pt box, `rounded-md hover:bg-muted hover:text-ink`, turned 90° while open.
private struct JiraCaretStyle: ButtonStyle {
  let isOpen: Bool

  func makeBody(configuration: Configuration) -> some View {
    JiraCaretBody(configuration: configuration, isOpen: isOpen)
  }
}

private struct JiraCaretBody: View {
  @Environment(\.theme) private var theme
  @Environment(\.isFocused) private var isFocused
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  let configuration: ButtonStyleConfiguration
  let isOpen: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.medium)
    configuration.label
      .font(.system(size: 14))
      .foregroundStyle(hovering ? theme.ink : theme.inkDim)
      .rotationEffect(.degrees(isOpen ? 90 : 0))
      .frame(width: 18, height: 18)
      .background(hovering || configuration.isPressed ? theme.lineSoft : .clear, in: shape)
      .dailyFocusRing(isFocused, in: shape)
      .contentShape(shape)
      .onHover { hovering = $0 }
      // `transition-transform duration-100 ease-brand motion-reduce:transition-none`.
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: isOpen)
      .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: hovering)
  }
}
