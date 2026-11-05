import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

// MARK: - Tones

extension Theme {
  /// `STATUS_TONES` (`contracts.ts:10-13`): foreground and tint of a status.
  func agentStatusColors(_ status: AgentTaskStatus) -> (foreground: Color, background: Color) {
    switch status {
    case .working: (info, infoTint)
    case .waiting: (brand, brandTint)
    case .blocked: (warning, warningTint)
    case .completed: (success, successTint)
    case .failed: (danger, dangerTint)
    case .cancelled: (inkDim, neutralTint)
    default: (inkMid, neutralTint)
    }
  }

  /// `LIVE_TONES` (`contracts.ts:26-28`).
  func liveColor(_ state: AgentLiveState) -> Color {
    switch state {
    case .working: info
    case .background: brand
    case .prompt: danger
    case .stopped: neutralTint
    default: inkDim
    }
  }

  /// `PROVIDER_ACCENTS` (`TaskCard.tsx:7`): one hue per provider on the card's edge.
  func providerColor(_ provider: AgentProvider) -> Color {
    switch provider {
    case .claude: brand
    case .codex: info
    case .gemini: success
    default: inkDim
    }
  }
}

/// A status in a capsule, coloured by status.
struct AgentStatusBadge: View {
  @Environment(\.theme) private var theme
  let text: String
  let status: AgentTaskStatus

  var body: some View {
    let colors = theme.agentStatusColors(status)
    Text(text)
      .font(.daily(size: 11, weight: .medium))
      .lineLimit(1)
      .foregroundStyle(colors.foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(colors.background, in: .capsule)
  }
}

/// The red "needs you" line with how long it has waited.
struct NeedsYouLine: View {
  @Environment(\.theme) private var theme
  let needsYou: NeedsYou
  let now: Date

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(theme.danger).frame(width: 6, height: 6).accessibilityHidden(true)
      Text(needsYou.label).font(.daily(size: 11, weight: .semibold)).foregroundStyle(theme.danger)
      Text("· \(AgentsLogic.waitedFor(needsYou.since, now: now))").foregroundStyle(theme.inkDim)
    }
    .font(.daily(size: 11))
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Task card

/// `TaskCard.tsx`: a button that opens the task.
struct AgentTaskCard: View {
  @Environment(\.theme) private var theme
  let task: AgentTask
  var progress: AgentSubtaskProgress?
  let now: Date
  let open: (String) -> Void

  var body: some View {
    let waiting = AgentsLogic.needsYou(task)
    Button {
      open(task.id)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        if let waiting { NeedsYouLine(needsYou: waiting, now: now) }
        Text(task.title)
          .font(.daily(size: 13, weight: .semibold))
          .foregroundStyle(theme.ink)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let hold = task.hold {
          HStack(spacing: 6) {
            AgentStatusBadge(text: AgentsLogic.holdLabel(hold.reason, status: task.status), status: task.status)
            if let note = hold.note {
              Text(note).font(.daily(size: 11)).foregroundStyle(theme.inkDim).lineLimit(1)
            }
          }
        }
        if let progress, progress.total > 0 { SubtaskProgressView(progress: progress) }
        if let live = liveState, waiting == nil {
          HStack(spacing: 6) {
            Circle().fill(theme.liveColor(live)).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(AgentsLogic.liveLabel(live))
          }
          .font(.daily(size: 11))
          .foregroundStyle(theme.inkMid)
        }
        footer
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
      .overlay(alignment: .leading) {
        if let provider = task.assignment?.provider {
          UnevenRoundedRectangle(topLeadingRadius: Radius.small, bottomLeadingRadius: Radius.small)
            .fill(theme.providerColor(provider))
            .frame(width: 3)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: Radius.small)
          .strokeBorder(waiting == nil ? theme.line : theme.danger.opacity(0.7), lineWidth: waiting == nil ? 1 : 2)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help(task.description)
  }

  /// Finished tasks show no live state (`TaskCard.tsx:11`).
  private var liveState: AgentLiveState? {
    AgentsLogic.finishedStatuses.contains(task.status) ? nil : task.assignment?.live?.state
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "cpu")
        .foregroundStyle(task.assignment.map { theme.providerColor($0.provider) } ?? theme.inkDim)
        .accessibilityHidden(true)
      Text(task.assignment.map { "\($0.displayName) · \($0.provider.rawValue)" } ?? "Sem agente atribuído")
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let assignment = task.assignment {
        Circle()
          .fill(assignment.freshness == .fresh ? theme.success : theme.warning)
          .frame(width: 6, height: 6)
          .help(AgentsLogic.cardFreshnessLabel(assignment.freshness))
          .accessibilityLabel(AgentsLogic.cardFreshnessLabel(assignment.freshness))
      }
      Text(AgentsLogic.formatTime(task.lastActivityAt)).monospacedDigit()
    }
    .font(.daily(size: 11))
    .foregroundStyle(theme.inkDim)
  }
}

/// `SubtaskTicker.tsx` without the rolling title: the bar, the newest open
/// subtask and the count.
struct SubtaskProgressView: View {
  @Environment(\.theme) private var theme
  let progress: AgentSubtaskProgress

  var body: some View {
    let current = progress.active.first
    VStack(alignment: .leading, spacing: 4) {
      ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
        .progressViewStyle(.linear)
        .tint(current == nil ? theme.success : theme.info)
      HStack(spacing: 6) {
        Text(current?.title ?? "Subtarefas concluídas").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        Text("\(progress.completed)/\(progress.total)").monospacedDigit()
      }
      .font(.daily(size: 11))
      .foregroundStyle(theme.inkDim)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Subtarefas: \(progress.completed) de \(progress.total) concluídas")
  }
}

// MARK: - Kanban

/// `KanbanColumns` (`BoardViews.tsx:34-54`): the active columns, the
/// "Finalizadas" strip and, when opened, the finished columns.
struct AgentKanbanView: View {
  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let tasks: [AgentTask]
  let status: AgentTaskStatus?
  let progress: [String: AgentSubtaskProgress]
  let board: AgentsBoard?
  @Binding var showFinished: Bool
  let now: Date
  var focusedCard: FocusState<String?>.Binding
  let open: (String) -> Void

  /// The board's own width, which picks 1, 2 or 4 columns.
  @State private var width: CGFloat = AgentsLogic.largeBreakpoint
  @State private var hoveringStrip = false

  var body: some View {
    Group {
      if let status {
        column(status)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          grid(AgentsLogic.activeStatuses)
          finishedStrip
          if showFinished && finishedTotal > 0 {
            grid(AgentsLogic.finishedStatuses)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
  }

  private var counts: [(status: AgentTaskStatus, count: Int)] { AgentsLogic.finishedCounts(tasks, board: board) }
  private var finishedTotal: Int { counts.reduce(0) { $0 + $1.count } }

  /// `grid items-start gap-3` with the column count of the width.
  private func grid(_ statuses: [AgentTaskStatus]) -> some View {
    let count = AgentsLogic.columnCount(width: width, columns: statuses.count)
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count),
      alignment: .leading,
      spacing: 12
    ) {
      ForEach(statuses, id: \.self) { column($0) }
    }
  }

  /// `Column` (`BoardViews.tsx:25-32`), on a glass panel instead of `bg-surface-1/80`.
  private func column(_ status: AgentTaskStatus) -> some View {
    let cards = tasks.filter { $0.status == status }
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(AgentsLogic.statusLabel(status)).font(.daily(size: 14, weight: .semibold))
        Spacer()
        Text("\(cards.count)")
          .font(.daily(size: 12))
          .monospacedDigit()
          .foregroundStyle(theme.inkMid)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(theme.surface2, in: .capsule)
      }
      .padding([.horizontal, .top], 4)
      .accessibilityAddTraits(.isHeader)
      if cards.isEmpty {
        Text("Nenhuma tarefa")
          .font(.daily(size: 12))
          .foregroundStyle(theme.inkDim)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
      } else {
        ForEach(cards) { task in
          AgentTaskCard(task: task, progress: progress[task.id], now: now, open: open)
            .focused(focusedCard, equals: task.id)
            .id(task.id)
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .glassSurface(.panel)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(AgentsLogic.statusLabel(status))
  }

  /// "Finalizadas": the counts, red when something failed, and the toggle
  /// (`BoardViews.tsx:43-49`).
  private var finishedStrip: some View {
    let failed = counts.first { $0.status == .failed }?.count ?? 0
    let lit = hoveringStrip && finishedTotal > 0
    return Button {
      showFinished.toggle()
    } label: {
      HStack(spacing: 8) {
        FlowLayout(spacing: 8) {
          Text("Finalizadas").font(.daily(size: 14, weight: .semibold))
          if finishedTotal == 0 {
            Text("nenhuma neste período").font(.daily(size: 12)).foregroundStyle(theme.inkDim)
          } else {
            ForEach(counts.filter { $0.count > 0 }, id: \.status) { item in
              if item.status == .failed {
                Label(
                  AgentsLogic.finishedCountLabel(item.status, count: item.count),
                  systemImage: "exclamationmark.triangle"
                )
                .font(.daily(size: 12, weight: .semibold))
                .foregroundStyle(theme.danger)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(theme.dangerTint, in: .capsule)
              } else {
                Text(AgentsLogic.finishedCountLabel(item.status, count: item.count))
                  .font(.daily(size: 12))
                  .foregroundStyle(theme.inkMid)
              }
            }
          }
        }
        Spacer(minLength: 0)
        if finishedTotal > 0 {
          HStack(spacing: 4) {
            Text(showFinished ? "Ocultar" : "Mostrar")
            Image(systemName: "chevron.down")
              .rotationEffect(.degrees(showFinished ? 180 : 0))
              .accessibilityHidden(true)
          }
          .font(.daily(size: 12, weight: .medium))
          .foregroundStyle(theme.brand)
        }
      }
      .foregroundStyle(theme.ink)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.surface1.opacity(lit ? 1 : 0.6), in: .rect(cornerRadius: Radius.extraLarge))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.extraLarge)
          .strokeBorder(
            failed > 0 ? theme.danger.opacity(0.6) : (lit ? theme.brand.opacity(0.5) : theme.line),
            style: StrokeStyle(lineWidth: 1, dash: [4]))
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(finishedTotal == 0)
    .onHover { hoveringStrip = $0 }
    .animation(Motion.ease(Motion.fast, reduceMotion: reduceMotion), value: showFinished)
    .accessibilityValue(showFinished ? "expandido" : "recolhido")
  }
}

// MARK: - Sessions

/// `SessionGrid` (`BoardViews.tsx:63-75`).
struct AgentSessionGrid: View {
  @Environment(\.theme) private var theme
  let sessions: [AgentSession]
  let now: Date
  let select: (String) -> Void

  var body: some View {
    if sessions.isEmpty {
      EmptyState("Nenhuma sessão reportada", description: "As sessões aparecem quando seus agentes se conectarem.")
    } else {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], spacing: 12) {
        ForEach(sessions) { card($0) }
      }
    }
  }

  private func card(_ session: AgentSession) -> some View {
    let attention = AgentsLogic.needsYou(session)
    return VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "cpu").foregroundStyle(theme.brand).accessibilityHidden(true)
      Text(session.agent.displayName).font(.daily(size: 14, weight: .semibold))
      Text("\(session.agent.provider.rawValue) · \(session.id)")
        .font(.daily(size: 11))
        .foregroundStyle(theme.inkDim)
        .textSelection(.enabled)
      Text("Última atividade: \(AgentsLogic.formatTime(session.lastActivityAt))")
        .font(.daily(size: 11))
        .foregroundStyle(theme.inkMid)
      Text(AgentsLogic.freshnessLabel(session.freshness)).font(.daily(size: 11)).foregroundStyle(theme.inkMid)
      if let live = session.live {
        HStack(spacing: 6) {
          Circle().fill(theme.liveColor(live.state)).frame(width: 6, height: 6).accessibilityHidden(true)
          Text(AgentsLogic.liveLabel(live.state))
        }
        .font(.daily(size: 11))
        .foregroundStyle(theme.inkMid)
      }
      if let attention { NeedsYouLine(needsYou: attention, now: now) }
      Button("Ver tarefas da sessão") { select(session.id) }
        .linkButtonStyle()
        .font(.daily(size: 14, weight: .medium))
        .padding(.top, 4)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassSurface(.panel)
    .overlay {
      // `border-danger ring-2 ring-danger/40` on the session that needs the user.
      if attention != nil {
        RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.danger, lineWidth: 2)
      }
    }
  }
}

// MARK: - Filters

/// `BoardFilterMenu` (`BoardViews.tsx:149-203`): status, period, order and
/// the session filter, with the count of filters away from the default.
struct AgentsFilterMenu: View {
  @Environment(\.theme) private var theme
  let store: AgentsStore

  var body: some View {
    Menu {
      Section("Status") {
        Picker("Status", selection: Binding(get: { store.query.status }, set: { store.setStatus($0) })) {
          Text("Todos").tag(AgentTaskStatus?.none)
          ForEach(AgentTaskStatus.known, id: \.self) { status in
            Text(AgentsLogic.statusLabel(status)).tag(AgentTaskStatus?.some(status))
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      Section("Período") {
        Picker("Período", selection: Binding(get: { store.query.days }, set: { store.setDays($0) })) {
          ForEach(AgentsLogic.activityWindows, id: \.self) { days in
            Text("Últimos \(days) dias").tag(days)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      Section("Ordem") {
        Picker("Ordem", selection: Binding(get: { store.query.sort }, set: { store.setSort($0) })) {
          ForEach(AgentsSort.allCases, id: \.self) { sort in
            Text(sort.label).tag(sort)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      if store.query.sessionID != nil {
        Divider()
        Button("Limpar sessão") { store.setSessionID(nil) }
      }
    } label: {
      Label("Filtros", systemImage: "line.3.horizontal.decrease")
    }
    .menuStyle(.button)
    .iconButtonStyle(variant: .outline)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Filtros")
    .accessibilityLabel("Filtros")
    .accessibilityValue(store.activeFilterCount > 0 ? "\(store.activeFilterCount) ativos" : "")
    .overlay(alignment: .topTrailing) {
      if store.activeFilterCount > 0 {
        Badge("\(store.activeFilterCount)").offset(x: 8, y: -8).allowsHitTesting(false).accessibilityHidden(true)
      }
    }
  }
}

// MARK: - Alerts

/// `PushToggle` (`components/agents/PushToggle.tsx:88-99`) on the app's desktop
/// alerts: "Ativar avisos" asks the system for permission, "Desativar avisos"
/// turns them off. There is no "Testar aviso": the alert engine has no way to
/// post one on demand.
struct AgentsAlertsToggle: View {
  @Environment(\.theme) private var theme
  let store: AgentsStore

  var body: some View {
    let state = store.alertsState
    if state != .unavailable {
      HStack(spacing: 8) {
        switch state {
        case .off:
          Button {
            Task { await store.enableAlerts() }
          } label: {
            Label("Ativar avisos", systemImage: "bell")
          }
          .pillButtonStyle(.outline, size: .small)
          .disabled(store.isChangingAlerts)
        case .on:
          // The web's title says "os seus dispositivos" (push to every subscription);
          // the app's test is local, so it names this one.
          Button {
            Task { await store.testAlert() }
          } label: {
            Label("Testar aviso", systemImage: "bell.badge")
          }
          .pillButtonStyle(.outline, size: .small)
          .disabled(store.isChangingAlerts)
          .help("Envia um aviso de teste para este dispositivo")
          Button {
            store.disableAlerts()
          } label: {
            Label("Desativar avisos", systemImage: "bell.slash")
          }
          .pillButtonStyle(.ghost, size: .small)
          .help("Desativar avisos neste dispositivo")
          .accessibilityLabel("Desativar avisos neste dispositivo")
        case .denied:
          Text("Avisos bloqueados nas permissões do sistema.")
            .font(.daily(size: 12))
            .foregroundStyle(theme.inkDim)
        case .unavailable:
          EmptyView()
        }
        if let notice = store.alertsNotice {
          Text(notice)
            .font(.daily(size: 12))
            .foregroundStyle(theme.inkMid)
        }
      }
    }
  }
}
