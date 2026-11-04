import Foundation

/// The `scheme://host[:port]` of a server, in the form browsers put in `Origin`.
///
/// The server compares `Origin` byte for byte with its own origin
/// (`lib/agents/http.ts:12`), so the scheme and host are lowercased and the
/// default port is dropped, as `new URL(...).origin` does.
public struct ServerOrigin: Sendable, Hashable, CustomStringConvertible {
  public let url: URL

  /// Returns `nil` when the URL is not `http` or `https` or has no host.
  public init?(_ server: URL) {
    guard
      let scheme = server.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = server.host(percentEncoded: false)?.lowercased(),
      !host.isEmpty
    else { return nil }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    let defaultPort = scheme == "https" ? 443 : 80
    if let port = server.port, port != defaultPort {
      components.port = port
    }
    guard let url = components.url else { return nil }
    self.url = url
  }

  /// The origin as text, without a trailing slash.
  public var description: String { url.absoluteString }
}
