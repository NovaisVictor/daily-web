import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Jira module: the four lists, filters, order, watched issues, followed
/// people, the issue actions and the daily summary (`components/JiraPanel.tsx`).
public struct JiraScreen: View {
  @Environment(\.theme) private var theme
  @State private var store: JiraStore
  @State private var dialog: JiraDialog?
  @State private var standupOpen = false
  @State private var filtersOpen = false
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  private let environment: AppEnvironment

  public init(environment: AppEnvironment) {
    self.environment = environment
    _store = State(initialValue: JiraStore(environment: environment))
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  private func revealPending() {
    guard isPrimaryWindow else { return }
    store.revealPending(from: environment.navigator)
  }

  /// What makes a person's view load again: another person, or a new state.
  private struct PersonLoadKey: Equatable {
    let accountId: String?
    let updatedAt: String?
  }

  public var body: some View {
    let known = store.known
    let now = store.now()
    let actions = JiraRowActions(
      open: { dialog = $0 }, focusEnabled: store.focusEnabled, pulls: store.pullsByKey,
      personName: store.personFirstName, now: now)
    let visible = store.visible(known: known)
    let delivered = store.delivered(known: known)
    let approved = store.approved(known: known)
    let problems = store.problems(known: known)
    let active = store.activeFilters(known: known)

    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          header(active: active, visible: visible)
          if store.peopleSearchOpen {
            PeopleSearchCard(store: store)
          } else if let error = store.peopleError {
            PanelError(error)
          }
          if store.activePerson != nil, let error = store.personError { PanelError(error) }
          tabs(delivered: delivered.count, approved: approved.count, problems: problems.count)
          if store.tab == .delivered || store.tab == .approved {
            FilterBar("Período") {
              ForEach(JiraPeriod.allCases) { period in
                Chip(period.label, isOn: store.period == period) { store.period = period }
              }
            }
          }
          filterBar(active: active, known: known)
          JiraActiveFiltersRow(filters: active, remove: store.clear, clearAll: store.clearFilters)
          content(
            visible: visible, delivered: delivered, approved: approved, problems: problems, known: known,
            actions: actions)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .onChange(of: store.revealed) { _, key in
        guard let key else { return }
        withAnimation { proxy.scrollTo(key, anchor: .center) }
      }
    }
    .task(
      id: PersonLoadKey(accountId: store.activePerson?.accountId, updatedAt: environment.dashboard.state?.updatedAt)
    ) {
      await store.loadPersonView()
    }
    .onAppear { revealPending() }
    .onChange(of: environment.navigator.pending) { revealPending() }
    .onChange(of: environment.dashboard.lastUpdated) { revealPending() }
    .sheet(item: $dialog) { dialog in sheet(dialog) }
    .sheet(isPresented: $standupOpen) { StandupSheet(source: store.standupSource, now: store.now()) }
  }

  // MARK: - Header

  private func header(active: [JiraActiveFilter], visible: [JiraItem]) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      PersonSwitcher(store: store)
      if store.tab == .open, !active.isEmpty {
        Text("\(visible.count) de \(store.all.count)")
          .font(.geist(14).monospacedDigit())
          .foregroundStyle(theme.inkDim)
          .fixedSize()
      }
      Spacer(minLength: 0)
      if store.activePerson == nil {
        IconButton("Resumo para a daily", systemImage: "list.clipboard") { standupOpen = true }
      }
    }
  }

  private func tabs(delivered: Int, approved: Int, problems: Int) -> some View {
    SegmentedPills(
      "listas do Jira",
      items: [
        .init(id: JiraTab.open, label: "Em aberto", count: store.all.count),
        .init(id: .delivered, label: "Entregues", count: delivered),
        .init(id: .approved, label: "Aprovados", count: approved),
        .init(id: .problems, label: "Problemas", count: problems),
      ],
      selection: $store.tab
    )
    .fixedSize()
  }

  private func filterBar(active: [JiraActiveFilter], known: [String: JiraItem]) -> some View {
    // The search stays in plain sight, so the badge counts only what the popover hides.
    let secondary = active.filter { $0.id != .query }.count
    return FilterBar("Filtrar o Jira") {
      SearchField(text: $store.filters.query, label: "buscar issues", placeholder: "chave ou resumo, até do épico")
      Button {
        filtersOpen.toggle()
      } label: {
        // `FilterPopover.tsx:33-56`: the trigger names itself and shows how many hide inside.
        HStack(spacing: 6) {
          Image(systemName: "slider.horizontal.3").accessibilityHidden(true)
          Text("Filtros")
          if secondary > 0 { Text("\(secondary)").monospacedDigit().foregroundStyle(theme.brand) }
        }
      }
      .pillButtonStyle(.outline, size: .small)
      .accessibilityLabel(secondary > 0 ? "filtros do Jira, \(secondary) ativos" : "filtros do Jira")
      .keyboardShortcut("f", modifiers: [.command, .shift])
      .popover(isPresented: $filtersOpen, arrowEdge: .bottom) {
        JiraFilterPopover(store: store, known: known)
      }
      JiraSortMenu(order: $store.order)
    }
  }

  // MARK: - Lists

  @ViewBuilder
  private func content(
    visible: [JiraItem], delivered: [JiraDatedItem], approved: [JiraDatedItem], problems: [JiraProblemItem],
    known: [String: JiraItem], actions: JiraRowActions
  ) -> some View {
    let source = store.source
    let name = store.personFirstName
    let person = store.activePerson != nil
    let filtering = store.filters.isActive
    switch store.tab {
    case .delivered:
      closedList(
        panel: source.delivered, inPeriod: store.deliveredInPeriod, sliced: delivered, known: known, actions: actions,
        empty: emptyClosed(verb: "entregue", person: person, name: name), filtering: filtering)
    case .approved:
      closedList(
        panel: source.approved, inPeriod: store.approvedInPeriod, sliced: approved, known: known, actions: actions,
        empty: emptyClosed(verb: "aprovada", person: person, name: name), filtering: filtering)
    case .problems:
      let all = source.problems.data ?? []
      if let error = source.problems.error { PanelError(error) }
      if store.loading, problems.isEmpty { LoadingState() }
      if filtering, !all.isEmpty, problems.isEmpty { EmptyState("Nenhuma issue com esses filtros.") }
      if !store.loading, all.isEmpty, source.problems.error == nil {
        EmptyState(
          person ? "Nenhuma história ou épico de \(name) com problema." : "Nenhuma história ou épico com problema.")
      }
      BulkStartDateButton(problems: problems, store: store)
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(problems.enumerated()), id: \.element.id) { index, issue in
          ListRow(index: index, isLast: index == problems.count - 1, isActive: store.revealed == issue.key) {
            JiraProblemRowView(issue: issue, store: store, actions: actions)
          }
          .id(issue.key)
        }
      }
    case .open:
      if !person { watchedSection(actions: actions) }
      if let error = source.jira.error { PanelError(error) }
      if store.loading, store.all.isEmpty { LoadingState() }
      if !store.loading, store.all.isEmpty, source.jira.error == nil {
        EmptyState(person ? "Nenhuma issue atribuída a \(name)." : "Nenhuma issue atribuída.")
      }
      if !store.all.isEmpty, visible.isEmpty { EmptyState("Nenhuma issue com esses filtros.") }
      if !visible.isEmpty {
        LazyVStack(alignment: .leading, spacing: 0) {
          if store.grouped {
            ForEach(store.situations(visible)) { group in
              JiraGroupHeading(title: group.label, count: group.issues.count).padding(.top, 16)
              ForEach(Array(group.issues.enumerated()), id: \.element.id) { index, issue in
                ListRow(index: index, isLast: index == group.issues.count - 1, isActive: store.revealed == issue.key) {
                  JiraRowView(issue: issue, store: store, actions: actions, showRole: store.role == .both)
                }
                .id(issue.key)
              }
            }
          } else {
            JiraProjectsView(
              groups: store.tree(visible, known: known), store: store, actions: actions,
              showRole: store.role == .both)
          }
        }
      }
    }
  }

  private func emptyClosed(verb: String, person: Bool, name: String) -> String {
    let by = person ? " por \(name)" : ""
    return store.period == .today
      ? "Nenhuma issue \(verb)\(by) hoje." : "Nenhuma issue \(verb)\(by) nos últimos 7 dias."
  }

  @ViewBuilder
  private func closedList(
    panel: PanelResult<[JiraDatedItem]>, inPeriod: [JiraDatedItem], sliced: [JiraDatedItem],
    known: [String: JiraItem], actions: JiraRowActions, empty: String, filtering: Bool
  ) -> some View {
    if let error = panel.error { PanelError(error) }
    if store.loading, sliced.isEmpty { LoadingState() }
    if filtering, !inPeriod.isEmpty, sliced.isEmpty { EmptyState("Nenhuma issue com esses filtros.") }
    if !store.loading, inPeriod.isEmpty, panel.error == nil { EmptyState(empty) }
    LazyVStack(alignment: .leading, spacing: 0) {
      JiraProjectsView(groups: store.tree(sliced.map(\.item), known: known), store: store, actions: actions)
    }
  }

  /// "Acompanhando": an issue that is not the user's, followed by choice.
  @ViewBuilder
  private func watchedSection(actions: JiraRowActions) -> some View {
    let watched = store.watched
    let items = watched.data ?? []
    VStack(alignment: .leading, spacing: 8) {
      JiraGroupHeading(title: "Acompanhando", count: items.isEmpty ? nil : items.count)
      HStack(spacing: 8) {
        TextField("acompanhar issue do Jira", text: $store.watchKey, prompt: Text("ABC-123"))
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 192)
          .accessibilityLabel("acompanhar issue do Jira")
          .onSubmit { Task { await store.watch() } }
        Button {
          Task { await store.watch() }
        } label: {
          Image(systemName: "plus").symbolEffect(.pulse, isActive: store.watchSaving)
        }
        .iconButtonStyle(variant: .outline)
        .disabled(store.watchSaving || store.watchKey.trimmingCharacters(in: .whitespaces).isEmpty)
        .help(store.watchSaving ? "Buscando…" : "Acompanhar issue")
        .accessibilityLabel(store.watchSaving ? "Buscando…" : "Acompanhar issue")
      }
      if let error = store.watchError { PanelError(error) }
      if let error = watched.error { PanelError(error) }
      if items.isEmpty, store.watchError == nil {
        Text("Nenhuma issue acompanhada.").font(.geist(14)).foregroundStyle(theme.inkDim).padding(.vertical, 8)
      }
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, issue in
          ListRow(index: index, isLast: index == items.count - 1) {
            JiraWatchedRowView(issue: issue, actions: actions) { Task { await store.unwatch(issue.key) } }
          }
        }
      }
    }
    .padding(.bottom, 12)
    Divider()
  }

  // MARK: - Dialogs

  @ViewBuilder
  private func sheet(_ dialog: JiraDialog) -> some View {
    switch dialog {
    case .comment(let issue): CommentSheet(issue: issue, store: store)
    case .flag(let issue): FlagSheet(issue: issue, store: store)
    case .due(let issue): DueSheet(issue: issue, store: store)
    case .priority(let issue): PrioritySheet(issue: issue, store: store)
    case .assign(let issue): AssignSheet(issue: issue, store: store)
    case .createStory(let issue): CreateStorySheet(issue: issue, store: store)
    case .approval(let issue): ApprovalSheet(issue: issue, store: store)
    case .focus(let source):
      FocusScheduleSheet(
        source: source, calendars: store.calendars, serverURL: environment.session.serverURL, store: store)
    }
  }
}

#Preview {
  JiraScreen(environment: .preview(state: JiraPreviewData.state))
    .frame(width: 900, height: 700)
}
