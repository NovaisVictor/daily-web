import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeatureSettings

@MainActor
final class ChangeCounter {
  var count = 0
}

@Suite struct IntegrationsStoreTests {
  let client = RecordingAPIClient()
  let changes = ChangeCounter()
  let store: IntegrationsStore

  init() {
    let changes = self.changes
    store = IntegrationsStore(client: client) { changes.count += 1 }
    client.respond { _ in integrationsFixture }
  }

  func loaded() async throws -> IntegrationsPayload {
    await store.load()
    return try #require(store.payload)
  }

  func modulesAnswer(_ payload: IntegrationsPayload, change: (inout [ModuleState]) -> Void = { _ in }) -> Data {
    var modules = payload.modules
    change(&modules)
    return RecordingAPIClient.json(ModulesResponse(modules: modules))
  }

  @Test func loadsTheIntegrations() async throws {
    let payload = try await loaded()
    #expect(client.calls.map { "\($0.method) \($0.path)" } == ["GET /api/integrations"])
    #expect(payload.modules.map(\.module).contains(.jira))
  }

  @Test func aFailedLoadShowsTheWebText() async {
    client.respond { _ throws(APIError) in throw .offline }
    await store.load()
    #expect(store.loadError == "Falha ao carregar as integrações")
  }

  // MARK: - Connections

  @Test func opensTheFormForAModuleWithNothingConnected() async throws {
    let payload = try await loaded()
    let tasks = try #require(payload.modules.first { $0.module == .tasks })
    store.open(tasks, help: false)
    #expect(store.editor?.module == .tasks)
    #expect(store.editor?.values == ["provider": "local"])
    // A single-connection module is named after itself.
    #expect(store.editor?.label == "Tarefas")

    store.close()
    store.open(tasks, help: true)
    #expect(store.editor == nil)
    #expect(store.showsHelp)
  }

  @Test func createsAConnectionWithTheVisibleFields() async throws {
    let payload = try await loaded()
    store.startNew(.email)
    store.setLabel("Pessoal")
    store.setValue("user", "voce@example.com")
    store.setValue("password", "app-password")
    let answer = modulesAnswer(payload)
    client.respond { _ in answer }

    await store.save()

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "POST /api/integrations/email/connections")
    #expect(
      call.body
        == #"{"label":"Pessoal","values":{"password":"app-password","preset":"gmail","user":"voce@example.com"}}"#)
    #expect(store.editor == nil)
    #expect(changes.count == 1)
  }

  @Test func refusesMissingRequiredFieldsBeforeTheCall() async throws {
    _ = try await loaded()
    store.startNew(.jira)
    await store.save()
    #expect(
      store.error
        == "Domínio Jira Cloud é obrigatório; E-mail da conta Atlassian é obrigatório; API token é obrigatório")
    #expect(client.calls.count == 1)
  }

  @Test func showsTheSingleConnectionConflict() async throws {
    _ = try await loaded()
    store.startNew(.jira)
    store.setValue("cloud", "acme")
    store.setValue("email", "voce@example.com")
    store.setValue("token", "t")
    client.respond { _ throws(APIError) in
      throw .server(status: 409, message: "Jira aceita só uma conexão — edite a que já existe", code: nil, retry: nil)
    }

    await store.save()

    #expect(store.error == "Jira aceita só uma conexão — edite a que já existe")
    #expect(store.editor != nil)
  }

  @Test func editingKeepsASavedSecretWhenLeftBlank() async throws {
    let payload = try await loaded()
    let jira = try #require(payload.modules.first { $0.module == .jira }?.connections.first)
    store.startEdit(jira)
    #expect(store.editor?.values == ["cloud": "acme", "email": "voce@example.com"])
    let answer = modulesAnswer(payload)
    client.respond { _ in answer }

    await store.save()

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "PUT /api/integrations/jira/connections/conn-jira-1")
    #expect(call.body == #"{"label":"Jira","values":{"cloud":"acme","email":"voce@example.com"}}"#)
  }

  @Test func removesAConnection() async throws {
    let payload = try await loaded()
    let jira = try #require(payload.modules.first { $0.module == .jira }?.connections.first)
    let answer = RecordingAPIClient.json(ConnectionRemovedResponse(modules: payload.modules, label: "Jira"))
    client.respond { _ in answer }

    await store.remove(jira)

    #expect(
      client.calls.last.map { "\($0.method) \($0.path)" } == "DELETE /api/integrations/jira/connections/conn-jira-1")
    #expect(changes.count == 1)
  }

  @Test func showsTheTestResultEvenWhenItFailed() async throws {
    let payload = try await loaded()
    let jira = try #require(payload.modules.first { $0.module == .jira }?.connections.first)
    client.respond { _ in Data(#"{"ok":false,"message":"token recusado pelo Jira"}"#.utf8) }

    await store.test(jira)

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "POST /api/integrations/jira/test")
    #expect(call.body == #"{"id":"conn-jira-1"}"#)
    #expect(store.testResults["conn-jira-1"] == ConnectionTestResult(ok: false, message: "token recusado pelo Jira"))
    #expect(store.error == nil)

    client.respond { _ throws(APIError) in throw .offline }
    await store.test(jira)
    #expect(store.testResults["conn-jira-1"] == ConnectionTestResult(ok: false, message: "Sem conexão com o servidor."))
  }

  @Test func choosesGoogleCalendars() async throws {
    let payload = try await loaded()
    client.respond { _ in
      Data(
        #"{"calendars":[{"id":"primary","label":"Pessoal","primary":true},"#
          .appending(#"{"id":"team","label":"Time","primary":false}],"selected":[]}"#).utf8)
    }

    await store.loadCalendars("conn-cal-1")

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "GET /api/integrations/agenda/google/calendars")
    #expect(call.query == [URLQueryItem(name: "id", value: "conn-cal-1")])
    // Nothing chosen yet: the primary calendar starts checked.
    #expect(store.chosenCalendars["conn-cal-1"] == ["primary"])

    store.setCalendar("team", chosen: true, connection: "conn-cal-1")
    store.setCalendar("primary", chosen: false, connection: "conn-cal-1")
    let answer = modulesAnswer(payload)
    client.respond { _ in answer }
    await store.saveCalendars("conn-cal-1")

    let save = try #require(client.calls.last)
    #expect("\(save.method) \(save.path)" == "PATCH /api/integrations/agenda/google/calendars")
    #expect(save.body == #"{"calendarIds":["team"],"id":"conn-cal-1"}"#)
    #expect(store.calendars["conn-cal-1"] == nil)
  }
}
