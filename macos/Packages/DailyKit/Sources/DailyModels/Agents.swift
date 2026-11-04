/// `lib/agents/model.ts:1-2`.
public struct AgentProvider: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let claude = AgentProvider(rawValue: "claude")
  public static let codex = AgentProvider(rawValue: "codex")
  public static let gemini = AgentProvider(rawValue: "gemini")
  public static let known: [AgentProvider] = [.claude, .codex, .gemini]
}

/// `lib/agents/model.ts:3-4`.
public struct AgentTaskStatus: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let queued = AgentTaskStatus(rawValue: "queued")
  public static let working = AgentTaskStatus(rawValue: "working")
  public static let waiting = AgentTaskStatus(rawValue: "waiting")
  public static let blocked = AgentTaskStatus(rawValue: "blocked")
  public static let completed = AgentTaskStatus(rawValue: "completed")
  public static let failed = AgentTaskStatus(rawValue: "failed")
  public static let cancelled = AgentTaskStatus(rawValue: "cancelled")
  public static let known: [AgentTaskStatus] = [
    .queued, .working, .waiting, .blocked, .completed, .failed, .cancelled,
  ]
}

/// Why a task is waiting or blocked (`lib/agents/model.ts:10-15`). The valid set
/// depends on the status; this lists the union of both.
public struct AgentHoldReason: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let pullRequest = AgentHoldReason(rawValue: "pull_request")
  public static let build = AgentHoldReason(rawValue: "build")
  public static let deploy = AgentHoldReason(rawValue: "deploy")
  public static let external = AgentHoldReason(rawValue: "external")
  public static let decision = AgentHoldReason(rawValue: "decision")
  public static let access = AgentHoldReason(rawValue: "access")
  public static let credential = AgentHoldReason(rawValue: "credential")
  public static let dependency = AgentHoldReason(rawValue: "dependency")
  public static let environment = AgentHoldReason(rawValue: "environment")
  public static let other = AgentHoldReason(rawValue: "other")
  public static let known: [AgentHoldReason] = [
    .pullRequest, .build, .deploy, .external, .decision, .access, .credential, .dependency, .environment, .other,
  ]

  /// The reasons the server accepts for `waiting` (`lib/agents/model.ts:11`).
  public static let waiting: [AgentHoldReason] = [.pullRequest, .build, .deploy, .external, .other]
  /// The reasons the server accepts for `blocked` (`lib/agents/model.ts:12`).
  public static let blocked: [AgentHoldReason] = [
    .decision, .access, .credential, .dependency, .environment, .other,
  ]
}

/// `lib/agents/model.ts:16`.
public struct AgentTaskHold: Codable, Sendable, Equatable, Hashable {
  public var reason: AgentHoldReason
  public var note: String?

  public init(reason: AgentHoldReason, note: String?) {
    self.reason = reason
    self.note = note
  }
}

/// How recently the session reported (`lib/agents/model.ts:18`).
public struct AgentFreshness: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let fresh = AgentFreshness(rawValue: "fresh")
  public static let stale = AgentFreshness(rawValue: "stale")
  public static let disconnected = AgentFreshness(rawValue: "disconnected")
  public static let known: [AgentFreshness] = [.fresh, .stale, .disconnected]
}

/// `lib/agents/model.ts:19`.
public struct AgentAttentionKind: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let permission = AgentAttentionKind(rawValue: "permission")
  public static let input = AgentAttentionKind(rawValue: "input")
  public static let known: [AgentAttentionKind] = [.permission, .input]
}

/// `lib/agents/model.ts:20`.
public struct AgentAttention: Codable, Sendable, Equatable, Hashable {
  public var kind: AgentAttentionKind
  public var since: String

  public init(kind: AgentAttentionKind, since: String) {
    self.kind = kind
    self.since = since
  }
}

/// `lib/agents/model.ts:21-22`.
public struct AgentLiveState: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let working = AgentLiveState(rawValue: "working")
  public static let background = AgentLiveState(rawValue: "background")
  public static let prompt = AgentLiveState(rawValue: "prompt")
  public static let idle = AgentLiveState(rawValue: "idle")
  public static let stopped = AgentLiveState(rawValue: "stopped")
  public static let known: [AgentLiveState] = [.working, .background, .prompt, .idle, .stopped]
}

/// What Agent Deck says the session is doing now (`lib/agents/model.ts:23`).
public struct AgentLive: Codable, Sendable, Equatable, Hashable {
  public var state: AgentLiveState
  public var since: String?

  public init(state: AgentLiveState, since: String?) {
    self.state = state
    self.since = since
  }
}

/// `lib/agents/model.ts:24`.
public struct Agent: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var externalId: String
  public var provider: AgentProvider
  public var displayName: String
  public var createdAt: String
  public var lastActivityAt: String

  public init(
    id: String,
    externalId: String,
    provider: AgentProvider,
    displayName: String,
    createdAt: String,
    lastActivityAt: String
  ) {
    self.id = id
    self.externalId = externalId
    self.provider = provider
    self.displayName = displayName
    self.createdAt = createdAt
    self.lastActivityAt = lastActivityAt
  }
}

/// `lib/agents/model.ts:25`. `live` is filled by `attachLive` (`lib/agents/deck.ts:191-196`).
public struct AgentSession: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var agentId: String
  public var externalId: String
  public var version: Int
  public var startedAt: String
  public var lastActivityAt: String
  public var agent: Agent
  public var freshness: AgentFreshness
  public var attention: AgentAttention?
  public var live: AgentLive?

  public init(
    id: String,
    agentId: String,
    externalId: String,
    version: Int,
    startedAt: String,
    lastActivityAt: String,
    agent: Agent,
    freshness: AgentFreshness,
    attention: AgentAttention?,
    live: AgentLive? = nil
  ) {
    self.id = id
    self.agentId = agentId
    self.externalId = externalId
    self.version = version
    self.startedAt = startedAt
    self.lastActivityAt = lastActivityAt
    self.agent = agent
    self.freshness = freshness
    self.attention = attention
    self.live = live
  }
}

/// `lib/agents/model.ts:26`.
public struct AgentSourceProvider: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let personal = AgentSourceProvider(rawValue: "personal")
  public static let jira = AgentSourceProvider(rawValue: "jira")
  public static let github = AgentSourceProvider(rawValue: "github")
  public static let known: [AgentSourceProvider] = [.personal, .jira, .github]
}

/// Where a task came from (`lib/agents/model.ts:26`). `resource` is a Jira key
/// or `owner/repo#n` (`lib/agents/schemas.ts:32-40`).
public struct AgentSourceLink: Codable, Sendable, Equatable, Hashable {
  public var provider: AgentSourceProvider
  public var connectionId: String?
  public var resource: String

  public init(provider: AgentSourceProvider, connectionId: String? = nil, resource: String) {
    self.provider = provider
    self.connectionId = connectionId
    self.resource = resource
  }
}

/// The session a task is assigned to (`lib/agents/model.ts:27`).
public struct AgentAssignment: Codable, Sendable, Equatable, Hashable {
  public var sessionId: String
  public var agentId: String
  public var provider: AgentProvider
  public var displayName: String
  public var freshness: AgentFreshness
  public var attention: AgentAttention?
  public var live: AgentLive?

  public init(
    sessionId: String,
    agentId: String,
    provider: AgentProvider,
    displayName: String,
    freshness: AgentFreshness,
    attention: AgentAttention?,
    live: AgentLive? = nil
  ) {
    self.sessionId = sessionId
    self.agentId = agentId
    self.provider = provider
    self.displayName = displayName
    self.freshness = freshness
    self.attention = attention
    self.live = live
  }
}

/// `lib/agents/model.ts:28`. Also the answer of `PATCH /api/agents/tasks/{id}`
/// and `POST /api/agents/tasks/{id}/transitions`.
public struct AgentTask: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var parentTaskId: String?
  public var externalId: String
  public var title: String
  public var description: String
  public var status: AgentTaskStatus
  public var hold: AgentTaskHold?
  public var assignment: AgentAssignment?
  public var source: AgentSourceLink?
  public var version: Int
  public var createdAt: String
  public var lastActivityAt: String

  public init(
    id: String,
    parentTaskId: String?,
    externalId: String,
    title: String,
    description: String,
    status: AgentTaskStatus,
    hold: AgentTaskHold?,
    assignment: AgentAssignment?,
    source: AgentSourceLink?,
    version: Int,
    createdAt: String,
    lastActivityAt: String
  ) {
    self.id = id
    self.parentTaskId = parentTaskId
    self.externalId = externalId
    self.title = title
    self.description = description
    self.status = status
    self.hold = hold
    self.assignment = assignment
    self.source = source
    self.version = version
    self.createdAt = createdAt
    self.lastActivityAt = lastActivityAt
  }
}

/// A still-open subtask shown on its parent's card (`lib/agents/model.ts:29`).
public struct AgentActiveSubtask: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var status: AgentTaskStatus

  public init(id: String, title: String, status: AgentTaskStatus) {
    self.id = id
    self.title = title
    self.status = status
  }
}

/// `lib/agents/model.ts:29`. `active` holds at most three
/// (`lib/agents/operations.ts:59`).
public struct AgentSubtaskProgress: Codable, Sendable, Equatable, Hashable {
  public var total: Int
  public var completed: Int
  public var active: [AgentActiveSubtask]

  public init(total: Int, completed: Int, active: [AgentActiveSubtask]) {
    self.total = total
    self.completed = completed
    self.active = active
  }
}

/// `lib/agents/model.ts:30`.
public struct AgentActivityKind: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let progress = AgentActivityKind(rawValue: "progress")
  public static let transition = AgentActivityKind(rawValue: "transition")
  public static let created = AgentActivityKind(rawValue: "created")
  public static let updated = AgentActivityKind(rawValue: "updated")
  public static let known: [AgentActivityKind] = [.progress, .transition, .created, .updated]
}

/// A line of a task's history (`lib/agents/model.ts:30`).
public struct AgentActivity: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var taskId: String
  public var kind: AgentActivityKind
  public var summary: String
  public var receivedAt: String
  public var occurredAt: String?

  public init(
    id: String,
    taskId: String,
    kind: AgentActivityKind,
    summary: String,
    receivedAt: String,
    occurredAt: String?
  ) {
    self.id = id
    self.taskId = taskId
    self.kind = kind
    self.summary = summary
    self.receivedAt = receivedAt
    self.occurredAt = occurredAt
  }
}

/// A cursor page (`lib/agents/model.ts:31`). The cursor is opaque.
public struct AgentPage<Item: Codable & Sendable & Hashable>: Codable, Sendable, Equatable, Hashable {
  public var items: [Item]
  public var nextCursor: String?
  /// Always true today; kept so a partial page is not mistaken for a full one.
  public var complete: Bool

  public init(items: [Item], nextCursor: String?, complete: Bool) {
    self.items = items
    self.nextCursor = nextCursor
    self.complete = complete
  }
}

/// `GET /api/agents` (`app/api/agents/route.ts:4`). `subtaskProgress` is keyed
/// by parent task id and `statusCounts` by `AgentTaskStatus` raw value
/// (`lib/agents/operations.ts:48-60`).
public struct AgentsBoard: Codable, Sendable, Equatable, Hashable {
  public var tasks: AgentPage<AgentTask>
  public var sessions: AgentPage<AgentSession>
  public var subtaskProgress: [String: AgentSubtaskProgress]
  public var statusCounts: [String: Int]

  public init(
    tasks: AgentPage<AgentTask>,
    sessions: AgentPage<AgentSession>,
    subtaskProgress: [String: AgentSubtaskProgress],
    statusCounts: [String: Int]
  ) {
    self.tasks = tasks
    self.sessions = sessions
    self.subtaskProgress = subtaskProgress
    self.statusCounts = statusCounts
  }

  /// Zero for a status the server did not count.
  public func count(of status: AgentTaskStatus) -> Int {
    statusCounts[status.rawValue] ?? 0
  }
}

/// `GET /api/agents/tasks/{id}` (`app/api/agents/tasks/[id]/route.ts:5`).
public struct AgentTaskDetail: Codable, Sendable, Equatable, Hashable {
  public var task: AgentTask
  public var activity: AgentPage<AgentActivity>
  public var subtasks: AgentPage<AgentTask>

  public init(task: AgentTask, activity: AgentPage<AgentActivity>, subtasks: AgentPage<AgentTask>) {
    self.task = task
    self.activity = activity
    self.subtasks = subtasks
  }
}

/// The agent's last answer captured with the pane (`lib/agents/deck.ts:156`).
public struct AgentTerminalResponse: Codable, Sendable, Equatable, Hashable {
  public var content: String
  public var at: String?

  public init(content: String, at: String?) {
    self.content = content
    self.at = at
  }
}

/// A captured terminal (`Terminal`, `lib/agents/deck.ts:156`).
public struct AgentTerminalSnapshot: Codable, Sendable, Equatable, Hashable {
  public var live: AgentLive
  public var pane: String
  public var response: AgentTerminalResponse?
  public var capturedAt: String

  public init(live: AgentLive, pane: String, response: AgentTerminalResponse?, capturedAt: String) {
    self.live = live
    self.pane = pane
    self.response = response
    self.capturedAt = capturedAt
  }
}

/// Why there is no terminal to show (`lib/agents/deck.ts:157`).
public struct AgentTerminalUnavailableReason: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let notEnabled = AgentTerminalUnavailableReason(rawValue: "not_enabled")
  public static let notLocal = AgentTerminalUnavailableReason(rawValue: "not_local")
  public static let unavailable = AgentTerminalUnavailableReason(rawValue: "unavailable")
  public static let known: [AgentTerminalUnavailableReason] = [.notEnabled, .notLocal, .unavailable]
}

/// `GET /api/agents/sessions/{id}/live` (`TerminalView`, `lib/agents/deck.ts:156-171`):
/// a union on `available`.
public enum AgentTerminal: Codable, Sendable, Equatable, Hashable {
  case available(AgentTerminalSnapshot)
  case unavailable(AgentTerminalUnavailableReason)

  private enum CodingKeys: String, CodingKey { case available, reason }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if try container.decode(Bool.self, forKey: .available) {
      self = .available(try AgentTerminalSnapshot(from: decoder))
    } else {
      self = .unavailable(try container.decode(AgentTerminalUnavailableReason.self, forKey: .reason))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .available(let snapshot):
      try container.encode(true, forKey: .available)
      try snapshot.encode(to: encoder)
    case .unavailable(let reason):
      try container.encode(false, forKey: .available)
      try container.encode(reason, forKey: .reason)
    }
  }
}

/// `POST /api/agents/sessions/{id}/messages`, status 202 (`lib/agents/deck.ts:173-188`).
/// `state` is Agent Deck's own word for the delivery and is not enumerated there.
public struct AgentMessageReceipt: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var id: String
  public var state: String

  public init(ok: Bool, id: String, state: String) {
    self.ok = ok
    self.id = id
    self.state = state
  }
}
