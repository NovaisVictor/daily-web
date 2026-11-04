import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// How a focus block request ended.
public enum FocusScheduleResult: Equatable, Sendable {
  case created(AgendaItem)
  /// Refused before the call, with the server's own text for the same field.
  case invalid(String)
  /// 409: the Google connection lacks write permission; the UI offers to reconnect.
  case reconnect(String)
  case failed(APIError)
}

/// Creates focus blocks on a writable Google calendar (`POST /api/agenda/focus-blocks`).
@Observable
public final class FocusScheduler {
  /// `DURATIONS`, `lib/focusBlock.ts:10`.
  public static let durations = [25, 50, 90, 120]
  /// Shown on a 409 that carries no message of its own.
  public static let reconnectMessage = "reconecte o Google para criar blocos de foco"

  public private(set) var isSaving = false

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let toasts: ToastCenter
  @ObservationIgnored private let now: Now

  public init(client: any APIClient, dashboard: DashboardStore, toasts: ToastCenter, now: @escaping Now = LiveTime.now)
  {
    self.client = client
    self.dashboard = dashboard
    self.toasts = toasts
    self.now = now
  }

  public func schedule(
    _ source: FocusSource,
    connectionId: String,
    start: Date,
    minutes: Int
  ) async -> FocusScheduleResult {
    let request: FocusBlockRequest
    switch Self.validate(source, connectionId: connectionId, start: start, minutes: minutes, now: now()) {
    case .success(let valid): request = valid
    case .failure(let refusal): return .invalid(refusal.message)
    }
    isSaving = true
    defer { isSaving = false }
    do {
      let response = try await client.send(AgendaEndpoints.focusBlock(request))
      dashboard.patch { state in
        // Mirrors the server's own cache patch (`route.ts:22-26`, `:91-97`).
        guard let items = state.agenda.data else { return }
        state.agenda.data = Self.sortedInsert(items, response.item)
      }
      toasts.success("Bloco de foco criado")
      return .created(response.item)
    } catch {
      Logger.core.error("Focus block failed: \(String(describing: error), privacy: .public)")
      if case .server(409, let message, _, _) = error {
        return .reconnect(message.isEmpty ? Self.reconnectMessage : message)
      }
      return .failed(error)
    }
  }

  struct Refusal: Error, Equatable {
    let message: String
  }

  /// The server's checks, in its order (`app/api/agenda/focus-blocks/route.ts:37-79`).
  static func validate(
    _ source: FocusSource,
    connectionId: String,
    start: Date,
    minutes: Int,
    now: Date
  ) -> Result<FocusBlockRequest, Refusal> {
    guard !connectionId.isEmpty else { return .failure(Refusal(message: "conexão não informada")) }
    let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
    // JavaScript measures length in UTF-16 units.
    guard !title.isEmpty, title.utf16.count <= 200 else { return .failure(Refusal(message: "título inválido")) }
    let ref = source.ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard ref.utf16.count <= 64 else { return .failure(Refusal(message: "referência inválida")) }
    if let url = source.url {
      guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host() != nil else {
        return .failure(Refusal(message: "URL inválida"))
      }
    }
    let earliest = now.addingTimeInterval(-5 * 60)
    let latest = now.addingTimeInterval(60 * 24 * 60 * 60)
    guard start >= earliest, start <= latest else { return .failure(Refusal(message: "início inválido")) }
    guard durations.contains(minutes) else { return .failure(Refusal(message: "duração inválida")) }
    let item = FocusSource(kind: source.kind, ref: ref, title: title, url: source.url)
    return .success(
      FocusBlockRequest(connectionId: connectionId, item: item, start: JSISODate.string(from: start), minutes: minutes))
  }

  static func sortedInsert(_ items: [AgendaItem], _ item: AgendaItem) -> [AgendaItem] {
    // Stable, like `Array.prototype.sort`, with the same keys.
    (items + [item]).enumerated()
      .sorted { lhs, rhs in
        if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
        if lhs.element.time != rhs.element.time { return lhs.element.time < rhs.element.time }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }
}
