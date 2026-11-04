// FROZEN INTERFACE (T006).

/// What the server's `retry` field says about trying again (`lib/agents/http.ts:9`).
public enum RetryHint: String, Sendable, Equatable {
  case later
  case reconcile
  case never
}

/// Every way a call can fail. `message` cases carry the server's own text,
/// which is Portuguese and meant to be shown as is.
public enum APIError: Error, Sendable, Equatable {
  /// No valid session: the app returns to the login screen.
  case unauthorized
  /// The server answered with an error status. Both error shapes map here:
  /// `{error: string}` and `{error: {code, message, retry}}`.
  case server(status: Int, message: String, code: String?, retry: RetryHint?)
  /// No server configured yet.
  case notConfigured
  case offline
  case timedOut
  case cancelled
  /// The body did not match the expected type; the detail is for logs, not users.
  case decoding(detail: String)
  case invalidResponse

  /// Text for the person using the app, in the web's voice.
  public var userMessage: String {
    switch self {
    case .unauthorized: "Sua sessão expirou. Entre de novo."
    case .server(_, let message, _, _): message
    case .notConfigured: "Informe o endereço do servidor."
    case .offline: "Sem conexão com o servidor."
    case .timedOut: "O servidor demorou para responder."
    case .cancelled: "Operação cancelada."
    case .decoding, .invalidResponse: "Resposta inesperada do servidor."
    }
  }
}
