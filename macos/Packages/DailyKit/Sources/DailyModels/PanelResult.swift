/// One module's slice of the dashboard, as the server sends it: data, an error,
/// or neither when the module is switched off (`lib/types.ts:393-396`).
public struct PanelResult<Value: Sendable>: Sendable {
  public var data: Value?
  public var error: String?

  public init(data: Value?, error: String?) {
    self.data = data
    self.error = error
  }

  /// Both fields null is how the server says the module is off, which is not
  /// the same as an empty list.
  public var isOff: Bool { data == nil && error == nil }
}

extension PanelResult: Equatable where Value: Equatable {}
extension PanelResult: Hashable where Value: Hashable {}

extension PanelResult: Codable where Value: Codable {
  private enum CodingKeys: String, CodingKey { case data, error }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    data = try container.decodeIfPresent(Value.self, forKey: .data)
    error = try container.decodeIfPresent(String.self, forKey: .error)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(data, forKey: .data)
    try container.encode(error, forKey: .error)
  }
}
