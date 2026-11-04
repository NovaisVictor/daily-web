import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// The connection being added or edited (`Editing` and the form state of
/// `components/IntegrationsPanel.tsx`).
struct ConnectionEditor: Equatable {
  let module: ModuleID
  /// nil for a new connection.
  let connectionId: String?
  var values: [String: String]
  var label: String
  /// Secret fields already saved on the edited connection.
  let savedSecrets: Set<String>
}

/// The integrations tab (`components/IntegrationsPanel.tsx`).
@Observable
final class IntegrationsStore {
  private(set) var payload: IntegrationsPayload?
  private(set) var loadError: String?
  /// The last failed action, shown above the list.
  private(set) var error: String?
  /// The module whose details sheet is open.
  var activeModule: ModuleID?
  private(set) var showsHelp = false
  private(set) var editor: ConnectionEditor?
  private(set) var isSaving = false
  private(set) var testing: String?
  private(set) var testResults: [String: ConnectionTestResult] = [:]
  private(set) var calendars: [String: [CalendarRef]] = [:]
  private(set) var chosenCalendars: [String: [String]] = [:]

  @ObservationIgnored private let client: any APIClient
  /// Runs after any change to the modules, so the dashboard picks it up.
  @ObservationIgnored private let onModulesChanged: () async -> Void

  init(client: any APIClient, onModulesChanged: @escaping () async -> Void = {}) {
    self.client = client
    self.onModulesChanged = onModulesChanged
  }

  func spec(_ module: ModuleID) -> ModuleSpec? { payload?.spec(for: module) }

  var activeState: ModuleState? {
    payload?.modules.first { $0.module == activeModule }
  }

  // MARK: - Loading

  func load() async {
    do {
      payload = try await client.send(IntegrationsEndpoints.list)
      loadError = nil
    } catch {
      Logger.settings.error("Integrations load failed: \(String(describing: error), privacy: .public)")
      // The web's text (`IntegrationsPanel.tsx:163`), unless a reload already has data.
      if payload == nil { loadError = "Falha ao carregar as integrações" }
    }
  }

  // MARK: - Details

  /// `openDetails`: a module with nothing connected and a form to fill opens
  /// straight on it, unless Google can do the job.
  func open(_ module: ModuleState, help: Bool) {
    activeModule = module.module
    showsHelp = help
    error = nil
    guard !help, let spec = spec(module.module), let payload else { return }
    let googleCanConnect = module.module == .agenda && payload.googleConfigured
    if module.connections.isEmpty, IntegrationForm.hasVisibleFields(spec), !googleCanConnect {
      startNew(module.module)
    }
  }

  func close() {
    activeModule = nil
    showsHelp = false
    error = nil
    cancelEdit()
  }

  // MARK: - Form

  func startNew(_ module: ModuleID) {
    guard let spec = spec(module) else { return }
    editor = ConnectionEditor(
      module: module, connectionId: nil, values: IntegrationForm.defaults(for: spec),
      label: spec.multi ? "" : spec.label, savedSecrets: [])
    error = nil
  }

  func startEdit(_ connection: ConnectionSummary) {
    guard let spec = spec(connection.module) else { return }
    editor = ConnectionEditor(
      module: connection.module, connectionId: connection.id,
      values: IntegrationForm.defaults(for: spec).merging(connection.visible) { _, saved in saved },
      label: connection.label, savedSecrets: Set(connection.secretsSet))
    error = nil
  }

  func cancelEdit() {
    editor = nil
  }

  func setValue(_ name: String, _ value: String) {
    guard let current = editor else { return }
    editor?.values = IntegrationForm.setting(name, to: value, in: current.values)
  }

  func setLabel(_ label: String) {
    editor?.label = label
  }

  var visibleFields: [FieldSpec] {
    guard let editor, let spec = spec(editor.module) else { return [] }
    return IntegrationForm.visibleFields(spec, values: editor.values)
  }

  /// `POST` a new connection or `PUT` the edited one. The server's 409 for a
  /// second connection of a single-connection module shows as is.
  func save() async {
    guard let editor, let spec = spec(editor.module) else { return }
    let problems = IntegrationForm.validate(spec, values: editor.values, savedSecrets: editor.savedSecrets)
    guard problems.isEmpty else {
      // Same joined text the server answers with (`connections/route.ts:41`).
      error = problems.joined(separator: "; ")
      return
    }
    isSaving = true
    defer { isSaving = false }
    error = nil
    let body = IntegrationForm.body(spec, values: editor.values, label: editor.label)
    do {
      let response: ModulesResponse
      if let id = editor.connectionId {
        response = try await client.send(IntegrationsEndpoints.update(editor.module, id: id, body))
      } else {
        response = try await client.send(IntegrationsEndpoints.create(editor.module, body))
      }
      payload?.modules = response.modules
      cancelEdit()
      await onModulesChanged()
    } catch {
      Logger.settings.error("Connection save failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  // MARK: - Connection actions

  func remove(_ connection: ConnectionSummary) async {
    error = nil
    do {
      let response = try await client.send(IntegrationsEndpoints.remove(connection.module, id: connection.id))
      payload?.modules = response.modules
      testResults[connection.id] = nil
      calendars[connection.id] = nil
      await onModulesChanged()
    } catch {
      Logger.settings.error("Connection removal failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  /// The answer is always 200 with `{ok, message}`; only a transport or
  /// server failure becomes a failed result with its own message.
  func test(_ connection: ConnectionSummary) async {
    testing = connection.id
    defer { testing = nil }
    do {
      testResults[connection.id] = try await client.send(
        IntegrationsEndpoints.test(connection.module, id: connection.id))
    } catch {
      Logger.settings.error("Connection test failed: \(String(describing: error), privacy: .public)")
      testResults[connection.id] = ConnectionTestResult(ok: false, message: error.userMessage)
    }
  }

  /// After connecting through Google, the person picks which calendars show.
  /// With nothing chosen yet, the primary ones start checked.
  func loadCalendars(_ connectionId: String) async {
    do {
      let response = try await client.send(IntegrationsEndpoints.calendars(connection: connectionId))
      calendars[connectionId] = response.calendars
      chosenCalendars[connectionId] =
        response.selected.isEmpty ? response.calendars.filter(\.primary).map(\.id) : response.selected
    } catch {
      Logger.settings.error("Calendar list failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  func setCalendar(_ calendarId: String, chosen: Bool, connection connectionId: String) {
    var current = chosenCalendars[connectionId] ?? []
    current.removeAll { $0 == calendarId }
    if chosen { current.append(calendarId) }
    chosenCalendars[connectionId] = current
  }

  func saveCalendars(_ connectionId: String) async {
    do {
      let response = try await client.send(
        IntegrationsEndpoints.saveCalendars(connection: connectionId, calendarIds: chosenCalendars[connectionId] ?? []))
      payload?.modules = response.modules
      calendars[connectionId] = nil
      await onModulesChanged()
    } catch {
      Logger.settings.error("Calendar selection failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }
}
