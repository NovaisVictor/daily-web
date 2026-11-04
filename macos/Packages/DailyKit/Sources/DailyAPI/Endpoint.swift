import Foundation

// FROZEN INTERFACE (T006). Features describe their calls as `Endpoint` values in
// their own target; only the client in this target turns them into requests.

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"

  /// Every non-GET call is a write: it carries `Origin`, which the server's
  /// `browser(request, 'write')` guard requires (`lib/agents/http.ts:11-12`).
  public var isWrite: Bool { self != .get }
}

/// A typed description of one API call.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
  public var method: HTTPMethod
  /// Path below the server origin, starting with `/api/`. Path segments taken
  /// from data must already be percent-encoded with `Endpoint.segment(_:)`.
  public var path: String
  public var query: [URLQueryItem]
  public var body: (any Encodable & Sendable)?
  /// Adds `Idempotency-Key` and `X-Request-Timestamp`, read by the pulls writes
  /// and agent messages (`app/api/pulls/shared.ts`, `lib/access/receipts.ts`).
  public var idempotent: Bool

  public init(
    _ method: HTTPMethod,
    _ path: String,
    query: [URLQueryItem] = [],
    body: (any Encodable & Sendable)? = nil,
    idempotent: Bool = false
  ) {
    self.method = method
    self.path = path
    self.query = query
    self.body = body
    self.idempotent = idempotent
  }

  /// Percent-encodes a single path segment (ids may contain `/`, `+`, `=`).
  public static func segment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/+=?#")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

/// For calls whose success has no useful body (204, or `{ok:true}` we ignore).
public struct EmptyResponse: Decodable, Sendable, Equatable {
  public init() {}
  public init(from decoder: any Decoder) throws {}
}
