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
  ///
  /// Encodes the UTF-8 bytes by hand instead of `addingPercentEncoding`, whose
  /// optional result would need a fallback; this way every input has an answer.
  public static func segment(_ value: String) -> String {
    var encoded = ""
    encoded.reserveCapacity(value.utf8.count)
    for byte in value.utf8 {
      if segmentAllowed.contains(byte) {
        encoded.unicodeScalars.append(Unicode.Scalar(byte))
      } else {
        encoded += "%" + hexDigits[Int(byte >> 4)] + hexDigits[Int(byte & 0x0F)]
      }
    }
    return encoded
  }
}

/// RFC 3986 `pchar` without the characters a server or router may read as
/// structure (`/`, `+`, `=`); `?` and `#` are not `pchar` at all.
private let segmentAllowed: Set<UInt8> = Set(
  Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*,;:@".utf8))

private let hexDigits = Array("0123456789ABCDEF").map(String.init)

/// For calls whose success has no useful body (204, or `{ok:true}` we ignore).
public struct EmptyResponse: Decodable, Sendable, Equatable {
  public init() {}
  public init(from decoder: any Decoder) throws {}
}
