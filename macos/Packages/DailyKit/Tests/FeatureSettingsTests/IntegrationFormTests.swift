import DailyModels
import Foundation
import Testing

@testable import FeatureSettings

func decodedPayload() throws -> IntegrationsPayload {
  try JSONDecoder().decode(IntegrationsPayload.self, from: integrationsFixture)
}

func spec(_ module: ModuleID) throws -> ModuleSpec {
  try #require(try decodedPayload().spec(for: module))
}

/// The web's cases from `tests/lib/modules.test.ts`, run against the catalog
/// the server sends.
@Suite struct IntegrationFormTests {
  @Test func fillsHostAndPortFromTheProvider() {
    let values = IntegrationForm.applyMailPreset(["preset": "gmail", "user": "a@b.com"])
    #expect(values["imapHost"] == "imap.gmail.com")
    #expect(values["smtpPort"] == "465")
  }

  @Test func keepsWhatWasTypedByHand() {
    #expect(
      IntegrationForm.applyMailPreset(["preset": "gmail", "imapHost": "imap.meu.com"])["imapHost"] == "imap.meu.com")
  }

  @Test func leavesManualValuesAlone() {
    let values = ["preset": "custom", "imapHost": "imap.meu.com"]
    #expect(IntegrationForm.applyMailPreset(values) == values)
  }

  @Test func appliesThePresetOnlyWhenTheProviderChanges() {
    #expect(IntegrationForm.setting("preset", to: "outlook", in: [:])["imapHost"] == "outlook.office365.com")
    #expect(IntegrationForm.setting("user", to: "a@b.com", in: ["preset": "outlook"])["imapHost"] == nil)
  }

  @Test func hidesHostAndPortForAKnownProvider() throws {
    let names = IntegrationForm.visibleFields(try spec(.email), values: ["preset": "gmail"]).map(\.name)
    #expect(names == ["preset", "user", "password"])
  }

  @Test func showsHostAndPortForAManualProvider() throws {
    let names = IntegrationForm.visibleFields(try spec(.email), values: ["preset": "custom"]).map(\.name)
    #expect(names.contains("imapHost"))
    #expect(names.contains("smtpPort"))
  }

  @Test func usesTheFieldDefaultWhenNothingWasChosen() throws {
    #expect(IntegrationForm.visibleFields(try spec(.tasks), values: [:]).map(\.name) == ["provider"])
    #expect(IntegrationForm.visibleFields(try spec(.tasks), values: ["provider": "local"]).map(\.name) == ["provider"])
  }

  @Test func neverShowsHiddenFields() throws {
    let agenda = IntegrationForm.visibleFields(
      try spec(.agenda), values: IntegrationForm.defaults(for: try spec(.agenda)))
    #expect(agenda.map(\.name) == ["icsUrl"])
    #expect(IntegrationForm.visibleFields(try spec(.slack), values: [:]).isEmpty)
    #expect(!IntegrationForm.hasVisibleFields(try spec(.notes)))
  }

  @Test func startsFromTheCatalogDefaults() throws {
    #expect(IntegrationForm.defaults(for: try spec(.tasks)) == ["provider": "local"])
  }

  @Test func asksForTheVisibleRequiredFields() throws {
    #expect(
      IntegrationForm.validate(try spec(.jira), values: [:]) == [
        "Domínio Jira Cloud é obrigatório",
        "E-mail da conta Atlassian é obrigatório",
        "API token é obrigatório",
      ])
  }

  @Test func ignoresFieldsHiddenByThePreset() throws {
    let values = ["preset": "gmail", "user": "a@b.com", "password": "x"]
    #expect(IntegrationForm.validate(try spec(.email), values: values).isEmpty)
    let manual = ["preset": "custom", "user": "a@b.com", "password": "x"]
    #expect(IntegrationForm.validate(try spec(.email), values: manual) == ["Servidor IMAP é obrigatório"])
  }

  @Test func treatsWhitespaceAsEmpty() throws {
    #expect(
      IntegrationForm.validate(try spec(.agenda), values: ["icsUrl": "   "]) == ["URL do iCal (.ics) é obrigatório"])
  }

  @Test func aSavedSecretLeftBlankStillCounts() throws {
    let values = ["cloud": "acme", "email": "voce@example.com", "token": ""]
    #expect(IntegrationForm.validate(try spec(.jira), values: values, savedSecrets: ["token"]).isEmpty)
    #expect(IntegrationForm.validate(try spec(.jira), values: values) == ["API token é obrigatório"])
  }

  @Test func offersMicrosoftToDoOnlyWhenInstalled() throws {
    let provider = try #require(try spec(.tasks).fields.first { $0.name == "provider" })
    #expect(IntegrationForm.options(for: provider, mstodoAvailable: false).map(\.value) == ["local"])
    #expect(IntegrationForm.options(for: provider, mstodoAvailable: true).map(\.value) == ["local", "mstodo"])
  }

  @Test func neverShowsASavedSecret() throws {
    let token = try #require(try spec(.jira).fields.first { $0.name == "token" })
    let cloud = try #require(try spec(.jira).fields.first { $0.name == "cloud" })
    #expect(IntegrationForm.placeholder(for: token, alreadySet: true) == IntegrationForm.savedSecretPlaceholder)
    #expect(IntegrationForm.placeholder(for: token, alreadySet: false) == nil)
    #expect(IntegrationForm.placeholder(for: cloud, alreadySet: true) == "acme")
  }

  @Test func sendsOnlyTheVisibleFields() throws {
    let values = IntegrationForm.applyMailPreset(["preset": "gmail", "user": "a@b.com", "password": "x"])
    let body = IntegrationForm.body(try spec(.email), values: values, label: "Trabalho")
    #expect(body.label == "Trabalho")
    #expect(body.values == ["preset": "gmail", "user": "a@b.com", "password": "x"])
  }

  @Test func trimsOnlyTheSecretsEnds() throws {
    let values = ["cloud": "acme", "email": " voce@example.com ", "token": "\n abc def \r\n"]
    let body = IntegrationForm.body(try spec(.jira), values: values, label: "Jira")
    // The secret loses the pasted line break but keeps its inner space; plain
    // fields go as typed.
    #expect(body.values == ["cloud": "acme", "email": " voce@example.com ", "token": "abc def"])
  }

  @Test func picksTheConnectActionLikeTheWeb() throws {
    var payload = try decodedPayload()
    let state = { (module: ModuleID) in
      ModuleState(
        module: module, label: "", summary: "", multi: false, enabled: true, configured: false, connections: [])
    }
    let connection = ConnectionSummary(
      id: "c", module: .jira, label: "Jira", visible: [:], secretsSet: [], updatedAt: "", unreadable: false)
    var connectedJira = state(.jira)
    connectedJira.connections = [connection]

    #expect(
      IntegrationForm.connectAction(for: state(.jira), spec: try spec(.jira), payload: payload)
        == .form(title: "Conectar"))
    // A single-connection module that is connected has nothing to add.
    #expect(IntegrationForm.connectAction(for: connectedJira, spec: try spec(.jira), payload: payload) == nil)
    #expect(IntegrationForm.connectAction(for: state(.slack), spec: try spec(.slack), payload: payload) == nil)
    #expect(IntegrationForm.connectAction(for: state(.notes), spec: try spec(.notes), payload: payload) == nil)

    payload.googleConfigured = true
    payload.slackConfigured = true
    #expect(
      IntegrationForm.connectAction(for: state(.slack), spec: try spec(.slack), payload: payload)
        == .browser(title: "Conectar", path: "/api/integrations/slack/start", query: []))
    #expect(
      IntegrationForm.connectAction(for: state(.agenda), spec: try spec(.agenda), payload: payload)
        == .browser(title: "Conectar", path: "/api/integrations/agenda/google/start", query: []))
    #expect(
      IntegrationForm.connectAction(for: state(.notes), spec: try spec(.notes), payload: payload)
        == .browser(
          title: "Conectar", path: "/api/integrations/agenda/google/start",
          query: [URLQueryItem(name: "purpose", value: "notes")]))
  }

  @Test func buildsTheBrowserURLOnTheServer() throws {
    let server = try #require(URL(string: "http://localhost:8010"))
    #expect(
      IntegrationForm.serverURL(
        server, path: "/api/integrations/agenda/google/start", query: [URLQueryItem(name: "purpose", value: "notes")])?
        .absoluteString == "http://localhost:8010/api/integrations/agenda/google/start?purpose=notes")
    #expect(IntegrationForm.serverURL(nil, path: "/x", query: []) == nil)
  }

  @Test func describesTheConnection() throws {
    let payload = try decodedPayload()
    let email = try #require(payload.modules.first { $0.module == .email })
    #expect(IntegrationForm.subtitle(email.connections[0], spec: try spec(.email)) == "gmail")
    #expect(
      IntegrationForm.subtitle(email.connections[1], spec: try spec(.email))
        == "ilegível com a chave atual — grave de novo")
    let bare = ConnectionSummary(
      id: "c", module: .jira, label: "Jira", visible: [:], secretsSet: [], updatedAt: "", unreadable: false)
    #expect(IntegrationForm.subtitle(bare, spec: try spec(.jira)) == "configurado")
  }
}
