import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// "Acesso dos agentes" (`components/agents/AccessPanel.tsx`): reporting
/// tokens, the instructions to paste into the agent, the MCP address and the
/// authorized MCP clients.
public struct AccessScreen: View {
  @State private var store: AccessStore
  @State private var confirmation: ConfirmRequest?
  @Environment(\.theme) private var theme
  @Environment(\.openSettings) private var openSettings
  /// Nil in tests and previews built from a bare store.
  private let navigator: AppNavigator?

  public init(environment: AppEnvironment) {
    self.init(store: AccessStore(client: environment.client), navigator: environment.navigator)
  }

  init(store: AccessStore, navigator: AppNavigator? = nil) {
    _store = State(initialValue: store)
    self.navigator = navigator
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        if let error = store.error {
          ErrorState("Não foi possível concluir", description: error) {
            Task { await store.loadTokens() }
          }
        }
        HStack(alignment: .top, spacing: 20) {
          tokenForm
          instructions
        }
        tokenList
        mcp
      }
      .padding(20)
      .frame(maxWidth: 1100, alignment: .topLeading)
    }
    .task { await store.loadAll() }
    .confirmDialog($confirmation)
    .sheet(isPresented: Binding(get: { store.secret != nil }, set: { if !$0 { store.dismissSecret() } })) {
      SecretSheet(secret: store.secret ?? "") { store.dismissSecret() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("CONECTE SEU WORKSPACE")
        .font(.geist(11, weight: .medium))
        .tracking(1.5)
        .foregroundStyle(theme.inkDim)
      Text("Acesso dos agentes")
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
        .accessibilityAddTraits(.isHeader)
      Text(
        "Envie o trabalho do Claude, Codex ou Gemini ao seu kanban. Cada acesso pertence à sua conta e pode ser revogado a qualquer momento."
      )
      .font(.geist(13))
      .foregroundStyle(theme.inkMid)
      .frame(maxWidth: 640, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Step 1

  private var tokenForm: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionTitle("1. Gere um acesso para a API", systemImage: "key")
      Text("O token é exibido uma única vez. Guarde-o no gerenciador de segredos do seu ambiente.")
        .font(.geist(13))
        .foregroundStyle(theme.inkMid)
        .fixedSize(horizontal: false, vertical: true)
      Form {
        TextField(
          "Nome do acesso",
          text: Binding(get: { store.label }, set: { store.setLabel($0) }),
          prompt: Text("Ex.: Claude no notebook")
        )
        .onSubmit { Task { await store.create() } }
        Picker("Permissão", selection: $store.permission) {
          ForEach(AccessPermission.allCases, id: \.self) { permission in
            Text(permission.label).tag(permission)
          }
        }
      }
      .formStyle(.columns)
      Button(store.isSaving ? "Aguarde…" : "Gerar token") {
        Task { await store.create() }
      }
      .pillButtonStyle()
      .disabled(!store.canCreate)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .accessCard()
  }

  // MARK: - Step 2

  private var instructions: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("2. Copie as instruções para o agente", systemImage: "doc.on.doc")
      Text(
        "As instruções usam placeholders e não incluem seu token. Informe o segredo separadamente pelo ambiente seguro do agente."
      )
      .font(.geist(13))
      .foregroundStyle(theme.inkMid)
      .fixedSize(horizontal: false, vertical: true)
      if let error = store.promptError {
        Text(error).font(.geist(13)).foregroundStyle(theme.danger)
      }
      if let prompt = store.prompt {
        ScrollView {
          Text(prompt)
            .font(.dailyMono(size: 11))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: 224)
        .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
        .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.line) }
        .accessibilityLabel("Instruções para o agente")
        CopyButton(value: prompt, label: "Copiar instruções")
      } else if store.promptError == nil {
        Text("Preparando instruções…").font(.geist(13)).foregroundStyle(theme.inkMid)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .accessCard()
  }

  // MARK: - Tokens

  private var tokenList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Tokens da API").font(.geist(14, weight: .semibold)).accessibilityAddTraits(.isHeader)
      if let tokens = store.tokens {
        if tokens.isEmpty {
          Text("Você ainda não gerou nenhum token.").font(.geist(13)).foregroundStyle(theme.inkMid)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
              ListRow(index: index, isLast: index == tokens.count - 1) { tokenRow(token) }
            }
          }
        }
      } else if store.error == nil {
        Text("Carregando acessos…").font(.geist(13)).foregroundStyle(theme.inkMid)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessCard()
  }

  private func tokenRow(_ token: APICredential) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(token.label).font(.geist(13, weight: .medium))
          Text(token.state == .active ? "Ativo" : "Revogado").font(.geist(11)).foregroundStyle(theme.inkDim)
        }
        Text("\(token.prefix)… · \(AccessLogic.scopeSummary(token.scopes))")
          .font(.geist(11))
          .foregroundStyle(theme.inkMid)
        Text(
          "Criado em \(AccessLogic.formatTime(token.createdAt)) · "
            + (token.lastUsedAt.map { "Usado em \(AccessLogic.formatTime($0))" } ?? "Ainda não utilizado")
        )
        .font(.geist(11))
        .foregroundStyle(theme.inkDim)
      }
      .accessibilityElement(children: .combine)
      Spacer()
      if token.state == .active {
        Button("Revogar \(token.label)") { confirmRevoke(token) }
          .pillButtonStyle(.outline, size: .small)
          .disabled(store.isSaving)
      }
    }
  }

  private func confirmRevoke(_ token: APICredential) {
    confirmation = ConfirmRequest(
      title: "Revogar \(token.label)?",
      message:
        "O agente perde acesso na próxima chamada. As tarefas já enviadas continuam seguindo a retenção de 30 dias.",
      confirmLabel: "Revogar acesso",
      destructive: true
    ) { [store] in
      Task { await store.revoke(token) }
    }
  }

  // MARK: - MCP

  private var mcp: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("MCP com autorização OAuth", systemImage: "powerplug")
      Text(
        "O MCP usa sua autorização de login para operar tarefas, Jira e GitHub. Tokens e senhas das integrações são cadastrados apenas no navegador."
      )
      .font(.geist(13))
      .foregroundStyle(theme.inkMid)
      .frame(maxWidth: 720, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      mcpEndpoint
      Button("Gerenciar conexões") {
        navigator?.requestSettings(.integrations)
        openSettings()
      }
      .pillButtonStyle(.outline)
      Divider()
      grants
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessCard()
  }

  @ViewBuilder private var mcpEndpoint: some View {
    if let error = store.mcpError {
      Text(error).font(.geist(13)).foregroundStyle(theme.danger)
    } else if let endpoint = store.mcpEndpoint {
      HStack(alignment: .bottom, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Endereço do servidor MCP").font(.geist(13))
          Text(endpoint)
            .font(.dailyMono(size: 11))
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
            .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.line) }
            .accessibilityLabel("Endereço do servidor MCP")
            .accessibilityValue(endpoint)
        }
        CopyButton(value: endpoint, label: "Copiar endereço MCP")
      }
    } else {
      Text("Carregando endereço MCP…").font(.geist(13)).foregroundStyle(theme.inkMid)
    }
  }

  private var grants: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Clientes autorizados", systemImage: "checkmark.shield")
        .font(.geist(13, weight: .medium))
        .accessibilityAddTraits(.isHeader)
      if let error = store.grantsError {
        HStack(spacing: 8) {
          Text(error).foregroundStyle(theme.danger)
          Button("Tentar novamente") { Task { await store.loadGrants() } }
            .buttonStyle(.link)
        }
        .font(.geist(13))
      }
      if let grants = store.grants {
        if grants.isEmpty {
          Text("Nenhum cliente MCP autorizado. A autorização é solicitada pelo seu cliente ao conectar.")
            .font(.geist(13))
            .foregroundStyle(theme.inkMid)
        }
        VStack(spacing: 0) {
          ForEach(Array(grants.enumerated()), id: \.element.id) { index, grant in
            ListRow(index: index, isLast: index == grants.count - 1) { grantRow(grant) }
          }
        }
      } else if store.grantsError == nil {
        Text("Carregando autorizações…").font(.geist(11)).foregroundStyle(theme.inkDim)
      }
    }
  }

  private func grantRow(_ grant: OAuthGrant) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(grant.clientName).font(.geist(13, weight: .medium))
        Text(grant.scopes.joined(separator: " · ")).font(.geist(11)).foregroundStyle(theme.inkMid)
        if let expires = grant.expiresAt {
          Text("Expira em \(AccessLogic.formatTime(expires))").font(.geist(11)).foregroundStyle(theme.inkDim)
        }
      }
      .accessibilityElement(children: .combine)
      Spacer()
      Button("Revogar \(grant.clientName)") { confirmRevoke(grant) }
        .pillButtonStyle(.outline, size: .small)
        .disabled(store.isRevokingGrant)
    }
  }

  private func confirmRevoke(_ grant: OAuthGrant) {
    confirmation = ConfirmRequest(
      title: "Revogar \(grant.clientName)?",
      message: "O cliente MCP perde sua autorização na próxima operação.",
      confirmLabel: "Revogar autorização",
      destructive: true
    ) { [store] in
      Task { await store.revoke(grant) }
    }
  }

  private func sectionTitle(_ title: String, systemImage: String) -> some View {
    Label {
      Text(title)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(theme.brand)
    }
    .font(.geist(14, weight: .semibold))
    .accessibilityAddTraits(.isHeader)
  }
}

/// "Guarde seu token agora": the secret, shown once.
struct SecretSheet: View {
  @Environment(\.theme) private var theme
  let secret: String
  let done: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Guarde seu token agora")
        .typeRole(.subhead)
        .accessibilityAddTraits(.isHeader)
      Text("Este segredo não será mostrado novamente. Não o cole nas instruções nem compartilhe em conversas.")
        .font(.geist(13))
        .foregroundStyle(theme.inkMid)
        .fixedSize(horizontal: false, vertical: true)
      Text(secret)
        .font(.dailyMono(size: 13))
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
        .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.line) }
        .accessibilityLabel("Token gerado, exibido uma única vez")
        .accessibilityValue(secret)
      HStack {
        CopyButton(value: secret, label: "Copiar token")
        Spacer()
        Button("Já guardei o token", action: done)
          .pillButtonStyle()
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 480)
    .interactiveDismissDisabled()
  }
}

/// `CopyButton` (`AccessPanel.tsx:20-27`): "Copiado" after a copy, and a hint
/// to copy by hand when the pasteboard refuses.
struct CopyButton: View {
  @Environment(\.theme) private var theme
  let value: String
  let label: String
  @State private var state: CopyState = .ready

  enum CopyState { case ready, copied, failed }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        state = pasteboard.setString(value, forType: .string) ? .copied : .failed
      } label: {
        Label(state == .copied ? "Copiado" : label, systemImage: state == .copied ? "checkmark" : "doc.on.doc")
      }
      .pillButtonStyle(.outline, size: .small)
      if state == .failed {
        Text("Selecione o texto e copie manualmente.").font(.geist(11)).foregroundStyle(theme.danger)
      }
    }
  }
}

extension View {
  fileprivate func accessCard() -> some View {
    modifier(AccessCard())
  }
}

/// `rounded-2xl border bg-surface-1` on the web; Liquid Glass here, as on the
/// Home panels (spec 013 FR-013-02).
private struct AccessCard: ViewModifier {
  func body(content: Content) -> some View {
    content.glassSurface(.panel)
  }
}

#Preview("Acesso") {
  AccessScreen(store: AccessStore(client: AccessPreview.client))
    .frame(width: 1000, height: 800)
}
