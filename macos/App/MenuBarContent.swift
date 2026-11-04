import AppKit
import DailyCore
import FeatureShell
import SwiftUI

/// The menu bar item's window, wired to the shared stores: it reads what the main
/// window's poller already fetched and never polls on its own.
struct MenuBarContent: View {
  let environment: AppEnvironment
  let opener: WindowOpener
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ThemedRoot(preferences: environment.preferences) {
      MenuBarPanel(
        isSignedIn: isSignedIn,
        state: isSignedIn ? environment.dashboard.state : nil,
        pomodoro: pomodoro,
        actions: actions
      )
    }
  }

  private var isSignedIn: Bool {
    if case .signedIn = environment.session.phase { return true }
    return false
  }

  private var pomodoro: MenuBarPomodoro? {
    let controller = environment.pomodoro
    return controller.display.map {
      MenuBarPomodoro(display: $0, isBusy: controller.isBusy, errorMessage: controller.errorMessage)
    }
  }

  private var actions: MenuBarActions {
    MenuBarActions(
      openApp: { show(nil) },
      openTasks: { show(.module(.tasks)) },
      openTask: { id in show(.module(.tasks), itemID: id) },
      openAgenda: { show(.module(.agenda)) },
      // The bell is a popover of the main window's toolbar: the request waits
      // in the navigator until the bell sees it.
      openNotifications: {
        environment.navigator.requestNotifications()
        show(nil)
      },
      togglePomodoro: { Task { await environment.pomodoro.toggle() } },
      resetPomodoro: { Task { await environment.pomodoro.reset() } },
      quit: { NSApp.terminate(nil) }
    )
  }

  private func show(_ route: AppRoute?, itemID: String? = nil) {
    if let route { environment.navigator.open(route, itemID: itemID) }
    dismiss()
    opener.showMain(.menuBar)
  }
}

/// The menu bar icon; the pomodoro's time shows next to it while it runs.
struct MenuBarLabel: View {
  let environment: AppEnvironment
  let opener: WindowOpener

  var body: some View {
    Group {
      if let display = environment.pomodoro.display, display.enabled, display.running {
        Text(display.formattedRemaining).monospacedDigit()
      } else {
        Image(systemName: "sun.max")
      }
    }
    .accessibilityLabel("Daily Web")
    .modifier(CapturesWindowOpener(opener: opener))
  }
}
