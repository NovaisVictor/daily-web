import DailyAPI
import Foundation
import Security

/// Why a Keychain operation failed.
public enum KeychainError: Error, Sendable, Equatable {
  /// `SecItem*` returned this status during `operation`.
  case unexpectedStatus(OSStatus, operation: String)
  /// The stored item is not UTF-8 text.
  case invalidData
  /// The URL has no `http(s)` origin to key the item by.
  case invalidServer
}

/// Keeps the session token as a generic password, one item per server origin.
public struct KeychainSessionTokenStore: SessionTokenStore {
  public static let defaultService = "io.github.novaisvictor.dailyweb.session"

  public let service: String
  public let useDataProtectionKeychain: Bool

  /// - Parameters:
  ///   - service: `kSecAttrService`; tests pass a unique value per test.
  ///   - useDataProtectionKeychain: Off by default because the data protection
  ///     keychain needs a team-signed app with a keychain access group; the app
  ///     is ad hoc signed (`Config/Base.xcconfig`), which answers
  ///     `errSecMissingEntitlement`. The login keychain works with ad hoc signing.
  public init(service: String = Self.defaultService, useDataProtectionKeychain: Bool = false) {
    self.service = service
    self.useDataProtectionKeychain = useDataProtectionKeychain
  }

  public func token(for server: URL) throws -> String? {
    var query = try baseQuery(for: server)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
        throw KeychainError.invalidData
      }
      return token
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.unexpectedStatus(status, operation: "read")
    }
  }

  public func save(_ token: String, for server: URL) throws {
    let query = try baseQuery(for: server)
    let data = Data(token.utf8)
    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus, operation: "add")
      }
    default:
      throw KeychainError.unexpectedStatus(updateStatus, operation: "update")
    }
  }

  public func deleteToken(for server: URL) throws {
    let status = SecItemDelete(try baseQuery(for: server) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status, operation: "delete")
    }
  }

  private func baseQuery(for server: URL) throws -> [String: Any] {
    guard let origin = ServerOrigin(server) else { throw KeychainError.invalidServer }
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: origin.description,
      kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
    ]
  }
}
