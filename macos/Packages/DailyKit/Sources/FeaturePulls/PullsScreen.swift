import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The pull requests module: tracked repositories, review requests and your
/// own PRs, with filters, the row actions and "agendar foco"
/// (`components/PullsPanel.tsx`).
public struct PullsScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: PullsStore
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let environment: AppEnvironment

  @State private var actionRequest: PullActionRequest?
  @State private var focusRequest: FocusRequest?

  public init(environment: AppEnvironment) {
    self.environment = environment
    _store = State(initialValue: PullsStore(environment: environment))
  }

  private struct FocusRequest: Identifiable {
    let id = UUID()
    let source: FocusSource
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      let count = store.count(store.tab)
      SectionHeader("GitHub", count: count > 0 ? String(count) : nil)
      SegmentedPills(
        "listas do GitHub",
        items: PullsTab.allCases.map { .init(id: $0, label: $0.label, count: store.count($0)) },
        selection: $store.tab
      )
      .fixedSize()
      if store.showsFilters { PullFiltersView(store: store) }
      content
      if store.tab == .tracked { TrackedReposView(store: store) }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .sheet(item: $actionRequest) { request in
      PullActionSheet(request: request, store: store)
    }
    .sheet(item: $focusRequest) { request in
      PullFocusSheet(
        source: request.source, calendars: store.calendars, serverURL: environment.session.serverURL, store: store)
    }
    .task {
      revealPending()
      await store.loadRepos()
    }
    .onChange(of: environment.navigator.pending) { revealPending() }
    .onChange(of: environment.dashboard.lastUpdated) { revealPending() }
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  private func revealPending() {
    guard isPrimaryWindow else { return }
    store.revealPending(from: environment.navigator)
  }

  // MARK: - Lists

  @ViewBuilder
  private var content: some View {
    if store.isLoading {
      LoadingState()
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            switch store.tab {
            case .tracked: tracked
            case .reviews: reviews
            case .mine: mine
            }
          }
          .padding(.trailing, 8)
        }
        .onChange(of: store.highlighted, initial: true) { _, id in
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }
  }

  private var rowActions: PullRowActions {
    PullRowActions(
      open: { action, item in actionRequest = PullActionRequest(action: action, item: item) },
      scheduleFocus: store.focusEnabled
        ? { item in focusRequest = FocusRequest(source: PullsStore.focusSource(item)) } : nil
    )
  }

  /// `blockers` is the "needs you" line the web prints above the row (`PullsPanel.tsx`).
  private func row(
    _ item: PullRequestItem, withRepo: Bool, index: Int, count: Int, blockers: String? = nil
  ) -> some View {
    let ref = PullActionRules.ref(item)
    return ListRow(index: index, isLast: index == count - 1, isActive: store.highlighted == ref) {
      VStack(alignment: .leading, spacing: 4) {
        if let blockers {
          Text(blockers).typeRole(.caption).foregroundStyle(theme.danger)
        }
        PullRowView(item: item, withRepo: withRepo, store: store, actions: rowActions)
      }
    }
    .id(ref)
  }

  @ViewBuilder
  private var tracked: some View {
    let panel = store.pulls
    if let error = panel.error { PanelError(error) }
    // A renamed repository fails on its own; showing that beside the ones that
    // loaded is more useful than replacing the whole panel with an error.
    if let errors = panel.data?.errors, !errors.isEmpty { PanelError(errors.joined(separator: "; ")) }
    DefaultBranchAlert(branches: panel.data?.defaultBranches ?? [])
    if store.tracked.isEmpty, panel.error == nil {
      EmptyState(store.trackedEmptyText)
    }
    let truncated = panel.data?.truncated ?? []
    ForEach(store.trackedGroups) { group in
      VStack(alignment: .leading, spacing: 8) {
        Group {
          if let url = GitHubNames.repoURL(group.repo) {
            Link(group.repo, destination: url).foregroundStyle(theme.ink)
          } else {
            Text(group.repo)
          }
        }
        .typeRole(.subhead)
        .accessibilityAddTraits(.isHeader)
        Divider()
        subsection("Issues", group.issues, truncation: truncated.first { $0.repo == group.repo && $0.kind == .issues })
        subsection(
          "Pull requests", group.pulls, truncation: truncated.first { $0.repo == group.repo && $0.kind == .pulls })
      }
      .padding(.bottom, 24)
    }
  }

  @ViewBuilder
  private func subsection(_ title: String, _ items: [PullRequestItem], truncation: PullsTruncation?) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title)
          Text("\(items.count)").monospacedDigit().fontWeight(.regular)
        }
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          row(item, withRepo: false, index: index, count: items.count)
        }
        if let truncation {
          let noun = truncation.kind == .issues ? "issues" : "pull requests"
          Text("Mostrando \(truncation.shown) de \(truncation.total) \(noun)")
            .typeRole(.caption).monospacedDigit().foregroundStyle(theme.inkDim)
        }
      }
      .padding(.leading, 16)
      .padding(.vertical, 6)
    }
  }

  @ViewBuilder
  private var reviews: some View {
    let panel = store.reviewRequests
    let digest = panel.data
    if let error = panel.error { PanelError(error) }
    if let errors = digest?.errors, !errors.isEmpty { PanelError(errors.joined(separator: "; ")) }
    // An empty list and a list the token cannot reach are different things,
    // and the second has a fix: the note says which one it is.
    if panel.error == nil {
      if store.reviews.isEmpty, store.filters.isActive, !store.allReviews.isEmpty {
        EmptyState(PullsStore.noFilterMatch)
      }
      if store.allReviews.isEmpty {
        EmptyState("Nenhuma revisão pedida a você.", description: digest?.scopeNote)
      }
    }
    let reviews = store.reviews
    ForEach(Array(reviews.enumerated()), id: \.element.id) { index, item in
      row(item, withRepo: true, index: index, count: reviews.count)
    }
    if let digest, digest.truncated {
      Text("Mostrando \(store.reviews.count) de \(digest.total): a busca traz uma página por ciclo.")
        .typeRole(.caption).foregroundStyle(theme.inkDim).padding(.top, 12)
    }
  }

  @ViewBuilder
  private var mine: some View {
    let panel = store.myPulls
    let digest = panel.data
    if let error = panel.error { PanelError(error) }
    if let errors = digest?.errors, !errors.isEmpty { PanelError(errors.joined(separator: "; ")) }
    if store.mine.isEmpty, panel.error == nil {
      EmptyState(
        store.filters.isActive && !store.allMine.isEmpty ? PullsStore.noFilterMatch : "Nenhum PR seu aberto.")
    }
    ForEach(store.mineGroups, id: \.group) { entry in
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(entry.group.label)
          Text("\(entry.items.count)").monospacedDigit().fontWeight(.regular)
        }
        .typeRole(.subhead)
        .accessibilityAddTraits(.isHeader)
        Divider()
        ForEach(Array(entry.items.enumerated()), id: \.element.id) { index, item in
          row(
            item, withRepo: true, index: index, count: entry.items.count,
            blockers: entry.group == .needsYou ? PullGrouping.blockers(item).map(\.label).joined(separator: ", ") : nil)
        }
      }
      .padding(.bottom, 24)
    }
    if let digest, digest.truncated {
      Text("Mostrando \(store.mine.count) de \(digest.total): a busca traz uma página por ciclo.")
        .typeRole(.caption).foregroundStyle(theme.inkDim).padding(.top, 12)
    }
  }
}

/// "CI vermelho na branch principal" (`components/pulls/DefaultBranchAlert.tsx`).
struct DefaultBranchAlert: View {
  @Environment(\.theme) private var theme
  let branches: [DefaultBranchStatus]

  var body: some View {
    let failing = branches.filter { $0.ci == .failing }
    if !failing.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("CI vermelho na branch principal").fontWeight(.medium).foregroundStyle(theme.ink)
        ForEach(failing, id: \.self) { branch in
          let label = "\(branch.repo) · \(branch.branch)"
          if let url = GitHubNames.actionsURL(repo: branch.repo, branch: branch.branch) {
            Link(label, destination: url).underline()
          } else {
            Text(label)
          }
        }
      }
      .font(.daily(size: 14))
      .foregroundStyle(theme.inkMid)
      .tint(theme.inkMid)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.warningTint, in: .rect(cornerRadius: 4))
      .overlay(alignment: .leading) { Rectangle().fill(theme.warning).frame(width: 2) }
      .padding(.bottom, 12)
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isStaticText)
    }
  }
}

#Preview("Pull requests") {
  PullsScreen(environment: .preview(state: PullsPreviewData.state))
    .frame(width: 1000, height: 760)
}
