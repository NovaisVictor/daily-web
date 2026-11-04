import DailyCore
import DailyDesign
import FeatureShell
import SwiftUI

/// Picks the screen for the session phase. Launch and foreground tracking live
/// in `AppDelegate`: they are per app, not per window.
struct RootView: View {
  let environment: AppEnvironment
  let router: AppRouter

  var body: some View {
    ThemedRoot(preferences: environment.preferences) {
      content
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .bottomTrailing) { toasts }
    }
  }

  @ViewBuilder private var content: some View {
    switch environment.session.phase {
    case .restoring:
      if let error = environment.session.restoreError {
        ErrorState("Não foi possível conectar ao servidor", description: error.userMessage) {
          Task { await environment.launch() }
        }
      } else {
        LoadingState()
      }
    case .signedOut(let message):
      VStack(spacing: 12) {
        if let message {
          PanelError(message)
            .frame(maxWidth: 360)
        }
        LoginView(initialServer: environment.session.serverURL) { server, username, password in
          await environment.session.signIn(server: server, username: username, password: password)
        }
      }
    case .signedIn(let user):
      MainWindow(environment: environment, router: router, user: user)
    }
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
