import DailyCore
import DailyModels
import Foundation
import Observation
import os

nonisolated extension Logger {
  static let homeArrangement = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureHome")
}

/// The "Abas" arrangement kept on this Mac, per account (spec 010 FR-010-08,
/// DP-3): read when the tabs show, followed as modules go on and off
/// (`WorkspaceHome.tsx:81-96`), and written a moment after each change so a
/// split being dragged does not write on every step.
@Observable
final class HomeWorkspace {
  /// How long a change waits for the next one before it is written.
  static let saveDelay: Duration = .milliseconds(500)
  /// Shown under "Não deu para guardar a disposição" when the file cannot be written.
  static let saveFailure = "Falha ao guardar as abas neste Mac"

  private(set) var layout = WorkspaceLayout(root: nil, nextID: 1)
  private(set) var saveError: String?
  /// Whether a document was read (or the default chosen) for the current account.
  private(set) var isLoaded = false

  @ObservationIgnored private let store: DashboardLayoutStore
  @ObservationIgnored private let sleep: Sleeper
  @ObservationIgnored private var account: LayoutAccount?
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  init(store: DashboardLayoutStore, sleep: @escaping Sleeper = LiveTime.sleep) {
    self.store = store
    self.sleep = sleep
  }

  /// Reads the arrangement of `account`, or the default when there is none
  /// or it cannot be read, matched to `modules`. Loading the same account
  /// again only follows the modules.
  func load(account: LayoutAccount?, modules: [ModuleID]) {
    if isLoaded, account == self.account {
      reconcile(modules: modules)
      return
    }
    // A change still waiting belongs to the previous account.
    if pendingSave != nil {
      pendingSave?.cancel()
      pendingSave = nil
      persist()
    }
    self.account = account
    isLoaded = true
    saveError = nil
    let saved = readSaved(account: account)
    layout = (saved ?? WorkspaceLayout.makeDefault(modules: modules)).reconciled(with: modules)
  }

  /// Every change from the tabs view goes through here.
  func update(_ next: WorkspaceLayout) {
    guard next != layout else { return }
    layout = next
    scheduleSave()
  }

  /// A module turned on gets a tab; one turned off loses its tab.
  func reconcile(modules: [ModuleID]) {
    guard isLoaded else { return }
    update(layout.reconciled(with: modules))
  }

  /// "Restaurar abas" (`page.tsx:97-100`): the default arrangement, written at once.
  func restore(modules: [ModuleID]) {
    pendingSave?.cancel()
    pendingSave = nil
    layout = WorkspaceLayout.makeDefault(modules: modules)
    persist()
  }

  /// Waits for a scheduled write; tests use it to observe the debounce.
  func waitForPendingSave() async {
    await pendingSave?.value
  }

  private func readSaved(account: LayoutAccount?) -> WorkspaceLayout? {
    guard let account else {
      Logger.homeArrangement.error("No server origin for the tabs arrangement; it stays in memory")
      return nil
    }
    do {
      guard let data = try store.loadWorkspace(account: account) else { return nil }
      guard let decoded = try WorkspaceLayout.decode(data) else {
        Logger.homeArrangement.notice("Saved tabs arrangement has another format version; using the default")
        return nil
      }
      return decoded
    } catch {
      // The next change overwrites the unreadable file with a valid one.
      Logger.homeArrangement.error("Saved tabs arrangement unreadable: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    let sleep = self.sleep
    pendingSave = Task { [weak self] in
      do {
        try await sleep(Self.saveDelay)
      } catch {
        // Cancelled: a newer change rescheduled the write, or the account changed.
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.pendingSave = nil
      self.persist()
    }
  }

  private func persist() {
    guard let account else { return }
    do {
      try store.saveWorkspace(layout.encoded(), account: account)
      saveError = nil
    } catch {
      Logger.homeArrangement.error("Tabs arrangement save failed: \(String(describing: error), privacy: .public)")
      saveError = Self.saveFailure
    }
  }
}
