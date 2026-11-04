import Foundation

/// The error bodies the server sends. Three shapes exist:
/// - `{error: string}` (most routes, e.g. `middleware.ts:39`);
/// - `{error: {code, message, retry}}` (`lib/agents/http.ts:9`);
/// - `{error: string, code, retry?}` (pulls, `app/api/pulls/shared.ts:57`).
struct ServerErrorBody: Decodable {
  let message: String
  let code: String?
  let retry: String?

  private enum CodingKeys: String, CodingKey {
    case error
    case code
    case retry
    case message
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let text = try? container.decode(String.self, forKey: .error) {
      // `try?` only probes which shape this is; the nested decode below throws
      // when the body matches neither.
      message = text
      code = try container.decodeIfPresent(String.self, forKey: .code)
      retry = try container.decodeIfPresent(String.self, forKey: .retry)
    } else {
      let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .error)
      message = try nested.decode(String.self, forKey: .message)
      code = try nested.decodeIfPresent(String.self, forKey: .code)
      retry = try nested.decodeIfPresent(String.self, forKey: .retry)
    }
  }
}
