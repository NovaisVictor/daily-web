import DailyCore
import DailyDesign
import FeatureShell
import SwiftUI

/// Picks the screen for the session phase. Launch and foreground tracking live
/// in `AppDelegate`: they are per app, not per window.
struct RootView: View {
  let environment: AppEnvironment
  let opener: WindowOpener
  /// The main window follows the shared navigator, which notifications and other
  /// screens move; a window opened with ⌘N keeps a sidebar selection of its own.
  let followsNavigator: Bool
  @State private var ownSelection: AppRoute? = .today
  @State private var isLeavingServer = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var screen: SessionScreen {
    SessionScreen(phase: environment.session.phase, hasRestoreError: environment.session.restoreError != nil)
  }

  var body: some View {
    ThemedRoot(preferences: environment.preferences) {
      ZStack { content }
        .animation(reduceMotion ? nil : Motion.easeInOut(Motion.slow), value: screen)
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .bottomTrailing) { toasts }
    }
    // Navigator requests target the window that follows the navigator; module
    // windows keep the default (false).
    .environment(\.isPrimaryWindow, followsNavigator)
    .generalSettingsControls()
    .modifier(CapturesWindowOpener(opener: opener))
  }

  private var selection: Binding<AppRoute?> {
    if followsNavigator {
      let navigator = environment.navigator
      return Binding(get: { navigator.route }, set: { navigator.route = $0 })
    }
    return $ownSelection
  }

  @ViewBuilder private var content: some View {
    Group {
      switch environment.session.phase {
      case .restoring:
        if let error = environment.session.restoreError {
          restoreFailed(error.userMessage)
        } else {
          LoadingState()
        }
      case .signedOut(let message):
        VStack(spacing: 12) {
          if let message {
            PanelError(message)
              .frame(maxWidth: 360)
              .transition(.opacity)
          }
          LoginView(initialServer: environment.session.serverURL) { server, username, password in
            await environment.session.signIn(server: server, username: username, password: password)
          }
        }
      case .signedIn(let user):
        MainWindow(environment: environment, selection: selection, user: user, opener: opener)
      }
    }
    .transition(.opacity.combined(with: .scale(0.98)))
  }

  /// A stored server that no longer answers (a stopped localhost, a moved host)
  /// would otherwise leave the app retrying forever: signing out forgets its
  /// token and opens the login screen with the server field to change.
  private func restoreFailed(_ message: String) -> some View {
    VStack(spacing: 12) {
      ErrorState("Não foi possível conectar ao servidor", description: message) {
        Task { await environment.launch() }
      }
      Button(isLeavingServer ? "Saindo…" : "Entrar em outro servidor") {
        isLeavingServer = true
        Task {
          await environment.session.signOut()
          isLeavingServer = false
        }
      }
      .pillButtonStyle(.ghost, size: .small)
    }
    // Retrying while the sign-out runs would race it back into `.restoring`.
    .disabled(isLeavingServer)
    .frame(maxWidth: 480)
    .padding(24)
  }

  private var toasts: some View {
    ToastStack(environment.toasts.toasts.map(ToastMessage.init)) { id in
      environment.toasts.dismiss(id)
    }
    .padding(16)
  }
}

extension ToastMessage {
  /// Core keeps its own toast value so it never imports the design system.
  init(_ toast: AppToast) {
    let kind: Kind =
      switch toast.kind {
      case .success: .success
      case .error: .error
      case .info: .info
      }
    let action = zip(toast.actionTitle, toast.action).map { Action(title: $0, perform: $1) }
    self.init(id: toast.id, kind: kind, text: toast.text, action: action)
  }
}

/// `zip` for optionals: both present or nothing.
private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
  guard let a, let b else { return nil }
  return (a, b)
}
