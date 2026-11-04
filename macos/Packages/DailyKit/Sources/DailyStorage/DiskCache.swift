import Foundation

public enum DiskCacheError: Error, Sendable, Equatable {
  /// No directory was injected and the process has no bundle identifier to name one.
  case missingBundleIdentifier
}

/// One JSON file holding the last good value, so the app can open with data before the network answers.
public struct DiskCache<Value: Codable & Sendable>: Sendable {
  public let fileURL: URL

  /// Stores `fileName` inside `directory`.
  public init(fileName: String, directory: URL) {
    fileURL = directory.appending(path: fileName, directoryHint: .notDirectory)
  }

  /// Stores `fileName` under `Application Support/<bundleIdentifier>/`.
  public init(fileName: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
      throw DiskCacheError.missingBundleIdentifier
    }
    let directory = URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    self.init(fileName: fileName, directory: directory)
  }

  /// Returns `nil` only when nothing was saved yet; unreadable or corrupt data throws.
  public func load() throws -> Value? {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
    return try JSONDecoder().decode(Value.self, from: data)
  }

  /// Writes atomically, so a crash never leaves half a file behind.
  public func save(_ value: Value) throws {
    let data = try JSONEncoder().encode(value)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }

  /// Deletes the file; a missing file is already the desired state.
  public func remove() throws {
    do {
      try FileManager.default.removeItem(at: fileURL)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    }
  }
}
