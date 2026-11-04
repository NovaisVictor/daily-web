import Foundation
import Testing

@testable import DailyStorage

private struct Snapshot: Codable, Sendable, Equatable {
  var updatedAt: String
  var names: [String]
}

private func temporaryDirectory() -> URL {
  FileManager.default.temporaryDirectory.appending(
    path: "DailyStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Test func diskCacheRoundTrip() throws {
  let directory = temporaryDirectory()
  defer { removeDirectory(directory) }
  let cache = DiskCache<Snapshot>(fileName: "state.json", directory: directory.appending(path: "nested"))
  let value = Snapshot(updatedAt: "2026-11-04T12:00:00.000Z", names: ["a", "b"])

  try cache.save(value)
  #expect(try cache.load() == value)

  try cache.remove()
  #expect(try cache.load() == nil)
  try cache.remove()
}

@Test func diskCacheMissingFileIsNil() throws {
  let cache = DiskCache<Snapshot>(fileName: "missing.json", directory: temporaryDirectory())
  #expect(try cache.load() == nil)
}

@Test func diskCacheCorruptFileThrows() throws {
  let directory = temporaryDirectory()
  defer { removeDirectory(directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let cache = DiskCache<Snapshot>(fileName: "state.json", directory: directory)
  try Data("{not json".utf8).write(to: cache.fileURL)

  #expect(throws: DecodingError.self) { try cache.load() }
}

@Test func diskCacheDefaultDirectoryUsesBundleIdentifier() throws {
  let cache = try DiskCache<Snapshot>(fileName: "state.json", bundleIdentifier: "io.example.app")
  #expect(cache.fileURL.deletingLastPathComponent().lastPathComponent == "io.example.app")
  #expect(cache.fileURL.deletingLastPathComponent().deletingLastPathComponent() == URL.applicationSupportDirectory)
  #expect(throws: DiskCacheError.missingBundleIdentifier) {
    try DiskCache<Snapshot>(fileName: "state.json", bundleIdentifier: nil)
  }
}

@Test func serverSettingsRoundTrip() throws {
  let suite = "io.github.novaisvictor.dailyweb.tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = UserDefaultsServerSettings(defaults: defaults)
  let server = try #require(URL(string: "https://daily.example.com"))

  #expect(settings.serverURL == nil)
  settings.setServerURL(server)
  #expect(settings.serverURL == server)
  #expect(defaults.string(forKey: UserDefaultsServerSettings.key) == "https://daily.example.com")
  #expect(UserDefaultsServerSettings(defaults: defaults).serverURL == server)

  settings.setServerURL(nil)
  #expect(settings.serverURL == nil)
}

@Test func serverSettingsIgnoreInvalidStoredValue() throws {
  let suite = "io.github.novaisvictor.dailyweb.tests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set("not a server", forKey: UserDefaultsServerSettings.key)

  #expect(UserDefaultsServerSettings(defaults: defaults).serverURL == nil)
}

private func removeDirectory(_ url: URL) {
  do {
    try FileManager.default.removeItem(at: url)
  } catch {
    Issue.record("Could not remove \(url.path()): \(error)")
  }
}
