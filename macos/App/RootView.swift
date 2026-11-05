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

  var body: some View {
    ThemedRoot(preferences: environment.preferences) {
      content
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .bottomTrailing) { toasts }
    }
    // Navigator requests target the window that follows the navigator; module
    // windows keep the default (false).
    .environment(\.isPrimaryWindow, followsNavigator)
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
      MainWindow(environment: environment, selection: selection, user: user, opener: opener)
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
