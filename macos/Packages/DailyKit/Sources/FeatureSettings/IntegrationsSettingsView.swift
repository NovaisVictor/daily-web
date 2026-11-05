import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The integrations (`components/IntegrationsPanel.tsx`): one card per
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

  /// `grid-cols-12`, three columns each: four cards to a row on a wide page,
  /// fewer as it narrows.
  static let cardMinWidth: CGFloat = 200

  @ViewBuilder private var content: some View {
    if let payload = store.payload {
      VStack(alignment: .leading, spacing: 16) {
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
        GlassGroup(spacing: 16) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardMinWidth), spacing: 16)], spacing: 16) {
            ForEach(payload.modules) { module in
              ModuleCard(store: store, module: module)
            }
          }
        }
      }
    } else if let error = store.loadError {
      PanelError(error)
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

/// One tool (`IntegrationsPanel.tsx:670-703`): logo and "Conectado", the
/// name, and the two actions at the bottom.
private struct ModuleCard: View {
  @Environment(\.theme) private var theme
  let store: IntegrationsStore
  let module: ModuleState

  var body: some View {
    let connected = !module.connections.isEmpty
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        Image(systemName: moduleSymbol(module.module))
          .font(.system(size: 20))
          .foregroundStyle(theme.inkMid)
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)
        Spacer()
        if connected {
          Text("Conectado")
            .typeRole(.caption)
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(theme.brandTint, in: .capsule)
        }
      }
      Text(module.label)
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      FlowLayout(spacing: 8) {
        Button(connected ? "Gerenciar" : "Conectar") { store.open(module, help: false) }
          .pillButtonStyle(.primary, size: .small)
        Button("Como conectar") { store.open(module, help: true) }
          .pillButtonStyle(.ghost, size: .small)
          .disabled(connected)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    .glassSurface(.panel)
    .help(module.summary)
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
    server: URL(string: "https://daily.example.com")
  )
  .padding(24)
}
