import Foundation

/// Reads the JSON fixtures copied into the test bundle.
enum Fixture {
  struct Missing: Error, CustomStringConvertible {
    let name: String
    var description: String { "fixture \(name) is not in the test bundle" }
  }

  static var directory: URL {
    get throws {
      guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
        throw Missing(name: "Fixtures/")
      }
      return url
    }
  }

  static func data(_ name: String) throws -> Data {
    try Data(contentsOf: try directory.appending(path: name))
  }

  static func allNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: try directory.path(percentEncoded: false))
      .filter { $0.hasSuffix(".json") }
      .sorted()
  }

  /// The API client decodes with a plain decoder: no key or date strategy.
  static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: try data(name))
  }

  static func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  /// The JSON tree with every null removed, so an absent optional and an
  /// explicit null compare equal.
  static func normalized(_ data: Data) throws -> NSObject {
    strippingNulls(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
  }

  private static func strippingNulls(_ value: Any) -> NSObject {
    switch value {
    case let dictionary as [String: Any]:
      var result: [String: NSObject] = [:]
      for (key, element) in dictionary where !(element is NSNull) {
        result[key] = strippingNulls(element)
      }
      return result as NSDictionary
    case let array as [Any]:
      return array.map(strippingNulls) as NSArray
    case let object as NSObject:
      return object
    default:
      return NSNull()
    }
  }
}
