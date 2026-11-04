import DailyDesign
import SwiftUI

/// Why a typed server address cannot be used.
public enum ServerAddressError: Error, Equatable {
  case empty
  case invalid
  case unsupportedScheme
  case missingHost

  public var message: String {
    switch self {
    case .empty: "Informe o endereço do servidor."
    case .invalid: "Endereço do servidor inválido."
    case .unsupportedScheme: "O endereço do servidor precisa começar com http:// ou https://."
    case .missingHost: "Informe o nome do servidor depois de http:// ou https://."
    }
  }
}

/// Checks the server field before any request goes out.
public enum ServerAddress {
  public static func parse(_ raw: String) -> Result<URL, ServerAddressError> {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .failure(.empty) }
    guard let components = URLComponents(string: text) else { return .failure(.invalid) }
    guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      return .failure(.unsupportedScheme)
    }
    guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }
    guard let url = components.url else { return .failure(.invalid) }
    return .success(url)
  }
}

/// The sign-in screen (`app/login/page.tsx`), plus the server field the web does not
/// need because it is served from that server.
public struct LoginView: View {
  private enum Field: Hashable { case server, username, password }

  /// Signs in and returns the message to show, or nil on success.
  private let onSubmit: (URL, String, String) async -> String?

  @State private var server: String
  @State private var username = ""
  @State private var password = ""
  @State private var error: String?
  @State private var isSubmitting = false
  @FocusState private var focus: Field?
  @Environment(\.theme) private var theme

  public init(initialServer: URL?, onSubmit: @escaping (URL, String, String) async -> String?) {
    self.onSubmit = onSubmit
    _server = State(initialValue: initialServer?.absoluteString ?? "")
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Circle()
          .fill(theme.surface2)
          .overlay(Circle().fill(theme.brand).frame(width: 8, height: 8))
          .overlay(Circle().stroke(theme.line))
          .frame(width: 40, height: 40)
          .accessibilityHidden(true)
        Text("daily-web")
          .font(.title2.weight(.semibold))
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
      }
      Text("Seu dia, num relance.")
        .font(.callout)
        .foregroundStyle(theme.inkMid)

      labeled("Servidor") {
        TextField("Servidor", text: $server, prompt: Text("https://daily.exemplo.com"))
          .focused($focus, equals: .server)
          .autocorrectionDisabled()
      }
      labeled("Usuário") {
        TextField("Usuário", text: $username)
          .textContentType(.username)
          .focused($focus, equals: .username)
          .autocorrectionDisabled()
      }
      labeled("Senha") {
        SecureField("Senha", text: $password)
          .textContentType(.password)
          .focused($focus, equals: .password)
      }

      if let error {
        Text(error)
          .font(.callout)
          .foregroundStyle(theme.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(action: submit) {
        Text(isSubmitting ? "Entrando" : "Entrar").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(theme.brand)
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
      .disabled(isSubmitting)
    }
    .textFieldStyle(.roundedBorder)
    .disabled(isSubmitting)
    .onSubmit(submit)
    .padding(32)
    .frame(width: 380)
    .background(theme.surface1, in: RoundedRectangle(cornerRadius: theme.radius))
    .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.line))
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.surface0)
    .onAppear { focus = server.isEmpty ? .server : .username }
    .onChange(of: error) { _, message in
      guard let message else { return }
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private func labeled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.callout.weight(.medium)).foregroundStyle(theme.ink)
      field()
    }
  }

  private func submit() {
    guard !isSubmitting else { return }
    error = nil
    switch ServerAddress.parse(server) {
    case .failure(let failure):
      error = failure.message
      focus = .server
    case .success(let url):
      isSubmitting = true
      Task {
        error = await onSubmit(url, username, password)
        isSubmitting = false
      }
    }
  }
}

#Preview("Login vazio") {
  LoginView(initialServer: nil) { _, _, _ in nil }
}

#Preview("Login com erro") {
  LoginView(initialServer: URL(string: "https://daily.exemplo.com")) { _, _, _ in
    "Usuário ou senha inválidos"
  }
}
