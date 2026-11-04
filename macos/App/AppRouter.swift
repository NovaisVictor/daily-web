import DailyCore
import Observation

/// Which sidebar entry the main window shows. Shared with the app delegate so
/// a clicked notification can navigate.
@Observable
final class AppRouter {
  var selection: AppRoute? = .today
  /// Item a notification pointed at; features read and clear it (T3xx/T4xx).
  var pendingItemID: String?

  func open(_ target: AlertTarget) {
    selection = target.route
    pendingItemID = target.itemID
  }
}
