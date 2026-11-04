import Foundation
import Observation

/// A short message at the edge of the window, like the web's `sonner` toasts.
/// The app maps it to `DailyDesign`'s toast stack; Core stays free of views.
public struct AppToast: Identifiable {
  public enum Kind: Sendable, Equatable {
    case success
    case error
    case info
  }

  public let id: UUID
  public let kind: Kind
  public let text: String
  public let actionTitle: String?
  public let action: (@MainActor () -> Void)?

  public init(
    id: UUID = UUID(),
    kind: Kind,
    text: String,
    actionTitle: String? = nil,
    action: (@MainActor () -> Void)? = nil
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.actionTitle = actionTitle
    self.action = action
  }
}

/// The toasts on screen, newest last. Each one leaves after `dismissDelay`.
@Observable
public final class ToastCenter {
  public private(set) var toasts: [AppToast] = []

  @ObservationIgnored private let dismissDelay: Duration
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]

  /// - Parameter dismissDelay: How long a toast stays; `sonner`'s default is 4 s.
  public init(dismissDelay: Duration = .seconds(4), sleep: @escaping Sleeper = LiveTime.sleep) {
    self.dismissDelay = dismissDelay
    self.sleep = sleep
  }

  @discardableResult
  public func show(
    _ kind: AppToast.Kind,
    _ text: String,
    actionTitle: String? = nil,
    action: (@MainActor () -> Void)? = nil
  ) -> UUID {
    let toast = AppToast(kind: kind, text: text, actionTitle: actionTitle, action: action)
    toasts.append(toast)
    let id = toast.id
    let delay = dismissDelay
    let sleep = self.sleep
    timers[id] = Task { [weak self] in
      do {
        try await sleep(delay)
      } catch {
        // Cancelled by `dismiss`: the toast is already gone.
        return
      }
      self?.dismiss(id)
    }
    return id
  }

  @discardableResult
  public func error(_ text: String) -> UUID { show(.error, text) }

  @discardableResult
  public func success(_ text: String) -> UUID { show(.success, text) }

  @discardableResult
  public func info(_ text: String) -> UUID { show(.info, text) }

  public func dismiss(_ id: UUID) {
    timers.removeValue(forKey: id)?.cancel()
    toasts.removeAll { $0.id == id }
  }

  /// Runs the toast's action and removes it.
  public func perform(_ id: UUID) {
    guard let toast = toasts.first(where: { $0.id == id }) else { return }
    dismiss(id)
    toast.action?()
  }

  public func removeAll() {
    for timer in timers.values { timer.cancel() }
    timers.removeAll()
    toasts.removeAll()
  }
}
