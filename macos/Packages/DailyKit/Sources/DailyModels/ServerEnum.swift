/// A string union sent by the server, modelled like `ModuleID`: a struct with
/// one static constant per value the app knows. A value added on the server
/// later decodes as itself instead of failing the whole response; `isKnown`
/// tells the two apart.
public protocol ServerEnum: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
  init(rawValue: String)

  /// Every value the server could send when this app was built.
  static var known: [Self] { get }
}

extension ServerEnum {
  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }

  /// False for a value the server added after this app was built.
  public var isKnown: Bool { Self.known.contains(self) }
}
