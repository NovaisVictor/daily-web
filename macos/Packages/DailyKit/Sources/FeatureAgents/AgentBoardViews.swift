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
      .font(.system(size: 11, weight: .medium))
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
      Text(needsYou.label).fontWeight(.semibold).foregroundStyle(theme.danger)
      Text("· \(AgentsLogic.waitedFor(needsYou.since, now: now))").foregroundStyle(theme.inkDim)
    }
    .font(.system(size: 11))
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
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.ink)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let hold = task.hold {
          HStack(spacing: 6) {
            AgentStatusBadge(text: AgentsLogic.holdLabel(hold.reason, status: task.status), status: task.status)
            if let note = hold.note {
              Text(note).font(.system(size: 11)).foregroundStyle(theme.inkDim).lineLimit(1)
            }
          }
        }
        if let progress, progress.total > 0 { SubtaskProgressView(progress: progress) }
        if let live = liveState, waiting == nil {
          HStack(spacing: 6) {
            Circle().fill(theme.liveColor(live)).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(AgentsLogic.liveLabel(live))
          }
          .font(.system(size: 11))
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
    .font(.system(size: 11))
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
      .font(.system(size: 11))
      .foregroundStyle(theme.inkDim)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Subtarefas: \(progress.completed) de \(progress.total) concluídas")
  }
}

// MARK: - Kanban

/// `KanbanColumns` (`BoardViews.tsx:34-54`).
struct AgentKanbanView: View {
  @Environment(\.theme) private var theme
  let tasks: [AgentTask]
  let status: AgentTaskStatus?
  let progress: [String: AgentSubtaskProgress]
  let board: AgentsBoard?
  @Binding var showFinished: Bool
  let now: Date
  var focusedCard: FocusState<String?>.Binding
  let open: (String) -> Void

  var body: some View {
    if let status {
      column(status)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(AgentsLogic.activeStatuses, id: \.self) { column($0) }
        }
        finishedStrip
        if showFinished && finishedTotal > 0 {
          HStack(alignment: .top, spacing: 12) {
            ForEach(AgentsLogic.finishedStatuses, id: \.self) { column($0) }
          }
        }
      }
    }
  }

  private var counts: [(status: AgentTaskStatus, count: Int)] { AgentsLogic.finishedCounts(tasks, board: board) }
  private var finishedTotal: Int { counts.reduce(0) { $0 + $1.count } }

  private func column(_ status: AgentTaskStatus) -> some View {
    let cards = tasks.filter { $0.status == status }
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(AgentsLogic.statusLabel(status)).font(.system(size: 13, weight: .semibold))
        Spacer()
        Text("\(cards.count)")
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(theme.inkMid)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(theme.surface2, in: .capsule)
      }
      .accessibilityAddTraits(.isHeader)
      if cards.isEmpty {
        Text("Nenhuma tarefa")
          .font(.system(size: 11))
          .foregroundStyle(theme.inkDim)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
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
    .background(theme.surface1.opacity(0.8), in: .rect(cornerRadius: Radius.medium))
    .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.line) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(AgentsLogic.statusLabel(status))
  }

  /// "Finalizadas": the counts, red when something failed, and the toggle.
  private var finishedStrip: some View {
    let failed = counts.first { $0.status == .failed }?.count ?? 0
    return Button {
      showFinished.toggle()
    } label: {
      HStack(spacing: 8) {
        Text("Finalizadas").fontWeight(.semibold)
        if finishedTotal == 0 {
          Text("nenhuma neste período").font(.system(size: 11)).foregroundStyle(theme.inkDim)
        } else {
          ForEach(counts.filter { $0.count > 0 }, id: \.status) { item in
            if item.status == .failed {
              Label(
                AgentsLogic.finishedCountLabel(item.status, count: item.count), systemImage: "exclamationmark.triangle"
              )
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(theme.danger)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(theme.dangerTint, in: .capsule)
            } else {
              Text(AgentsLogic.finishedCountLabel(item.status, count: item.count))
                .font(.system(size: 11))
                .foregroundStyle(theme.inkMid)
            }
          }
        }
        Spacer()
        if finishedTotal > 0 {
          Label(showFinished ? "Ocultar" : "Mostrar", systemImage: showFinished ? "chevron.up" : "chevron.down")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.brand)
        }
      }
      .font(.system(size: 13))
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.surface1.opacity(0.6), in: .rect(cornerRadius: Radius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.medium)
          .strokeBorder(
            failed > 0 ? theme.danger.opacity(0.6) : theme.line, style: StrokeStyle(lineWidth: 1, dash: [4]))
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(finishedTotal == 0)
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
      Text(session.agent.displayName).font(.system(size: 14, weight: .semibold))
      Text("\(session.agent.provider.rawValue) · \(session.id)")
        .font(.system(size: 11))
        .foregroundStyle(theme.inkDim)
        .textSelection(.enabled)
      Text("Última atividade: \(AgentsLogic.formatTime(session.lastActivityAt))")
        .font(.system(size: 11))
        .foregroundStyle(theme.inkMid)
      Text(AgentsLogic.freshnessLabel(session.freshness)).font(.system(size: 11)).foregroundStyle(theme.inkMid)
      if let live = session.live {
        HStack(spacing: 6) {
          Circle().fill(theme.liveColor(live.state)).frame(width: 6, height: 6).accessibilityHidden(true)
          Text(AgentsLogic.liveLabel(live.state))
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.inkMid)
      }
      if let attention { NeedsYouLine(needsYou: attention, now: now) }
      Button("Ver tarefas da sessão") { select(session.id) }
        .buttonStyle(.link)
        .padding(.top, 4)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.surface1, in: .rect(cornerRadius: Radius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.medium)
        .strokeBorder(attention == nil ? theme.line : theme.danger, lineWidth: attention == nil ? 1 : 2)
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
        .labelStyle(.iconOnly)
    }
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
