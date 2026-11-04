import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The integrations tab (`components/IntegrationsPanel.tsx`): one row per
/// module, and a sheet with its connections, form and help.
struct IntegrationsSettingsView: View {
  @Environment(\.theme) private var theme
  @State private var store: IntegrationsStore
  private let server: URL?

  init(environment: AppEnvironment) {
    let dashboard = environment.dashboard
    server = environment.session.serverURL
    _store = State(
      initialValue: IntegrationsStore(client: environment.client) { await dashboard.reload() })
  }

  init(store: IntegrationsStore, server: URL?) {
    _store = State(initialValue: store)
    self.server = server
  }

  var body: some View {
    content
      .task { await store.load() }
      // The Google and Slack flows finish in the browser; coming back to the
      // app is the cue to read the connections again.
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        Task { await store.load() }
      }
      .sheet(isPresented: detailsPresented) {
        ModuleDetailsSheet(store: store, server: server)
      }
  }

  @ViewBuilder private var content: some View {
    if let payload = store.payload {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if !payload.vaultReady {
            PanelError(
              "DAILY_WEB_SECRET_KEY não está configurada no servidor. Sem ela nenhuma credencial pode ser "
                + "guardada. Gere com openssl rand -base64 32.")
          }
          if let error = store.error, store.activeModule == nil {
            PanelError(error)
          }
          // No on/off switch per module: connecting turns it on, and the web
          // asserts there is none (`tests/components/IntegrationsPanel.test.tsx:299`,
          // "não mostra o liga/desliga no popup: conectar já liga o módulo").
          ForEach(payload.modules) { module in
            ModuleRow(store: store, module: module)
          }
        }
        .padding(20)
      }
    } else if let error = store.loadError {
      VStack {
        PanelError(error)
        Spacer()
      }
      .padding(20)
    } else {
      LoadingState()
    }
  }

  private var detailsPresented: Binding<Bool> {
    Binding(
      get: { store.activeModule != nil },
      set: { if !$0 { store.close() } }
    )
  }
}

/// An SF Symbol per module, standing in for the web's `ToolLogo`.
func moduleSymbol(_ module: ModuleID) -> String {
  switch module {
  case .email: "envelope"
  case .agenda: "calendar"
  case .jira: "square.stack.3d.up"
  case .pulls: "arrow.triangle.pull"
  case .tasks: "checklist"
  case .notes: "note.text"
  case .slack: "number"
  default: "puzzlepiece.extension"
  }
}

private struct ModuleRow: View {
  @Environment(\.theme) private var theme
  let store: IntegrationsStore
  let module: ModuleState

  var body: some View {
    let connected = !module.connections.isEmpty
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: moduleSymbol(module.module))
        .font(.system(size: 18))
        .foregroundStyle(theme.inkMid)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(module.label)
            .typeRole(.body)
            .foregroundStyle(theme.ink)
          if connected {
            Text("Conectado")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(theme.brand)
              .padding(.horizontal, 10)
              .padding(.vertical, 2)
              .background(theme.brandTint, in: .capsule)
          }
        }
        Text(module.summary)
          .font(.system(size: 13))
          .foregroundStyle(theme.inkDim)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Button(connected ? "Gerenciar" : "Conectar") { store.open(module, help: false) }
      Button("Como conectar") { store.open(module, help: true) }
        .buttonStyle(.borderless)
        .disabled(connected)
    }
    .padding(12)
    .background(theme.surface1.opacity(0.6), in: .rect(cornerRadius: Radius.medium))
    .overlay { RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(theme.lineSoft) }
  }
}

private let previewIntegrations = """
  {"vaultReady":true,"mstodoAvailable":false,"googleConfigured":true,"googleRedirectUri":"",
  "slackConfigured":false,"slackRedirectUri":"https://daily.example.com/api/integrations/slack/callback",
  "catalog":{},"modules":[{"module":"email","label":"E-mail","summary":"Caixa de entrada.","multi":true,
  "enabled":true,"configured":true,"connections":[{"id":"c1","module":"email","label":"Trabalho",
  "visible":{"user":"voce@example.com"},"secretsSet":["password"],"updatedAt":"","unreadable":false}]},
  {"module":"slack","label":"Slack","summary":"menções e mensagens diretas","multi":false,
  "enabled":false,"configured":false,"connections":[]}]}
  """

#Preview {
  IntegrationsSettingsView(
    store: IntegrationsStore(
      client: PreviewAPIClient(responses: ["GET /api/integrations": Data(previewIntegrations.utf8)])),
    server: URL(string: "https://daily.example.com"))
}
