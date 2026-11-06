import DailyDesign
import DailyModels
import SwiftUI

/// A module's details: connect action, help, connections and the form
/// (`renderDetails` in `components/IntegrationsPanel.tsx`).
struct ModuleDetailsSheet: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let store: IntegrationsStore
  let server: URL?
  @State private var confirm: ConfirmRequest?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let module = store.activeState, let spec = store.spec(module.module), let payload = store.payload {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            header(module, spec: spec, payload: payload)
            if store.showsHelp {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(spec.instructions, id: \.self) { line in
                  Text(line)
                }
              }
              .typeRole(.caption)
              .foregroundStyle(theme.inkMid)
              .padding(.leading, 12)
              .overlay(alignment: .leading) { Rectangle().fill(theme.lineSoft).frame(width: 1) }
            }
            setupNotes(module, payload: payload)
            if let error = store.error {
              PanelError(error)
            }
            ForEach(module.connections) { connection in
              ConnectionRow(store: store, connection: connection, spec: spec) {
                confirm = ConfirmRequest(
                  title: "Remover a conexão?",
                  message: "A credencial de \"\(connection.label)\" é apagada junto e precisa ser cadastrada de novo.",
                  confirmLabel: "Remover",
                  destructive: true,
                  onConfirm: { Task { await store.remove(connection) } }
                )
              }
            }
            if let editor = store.editor, editor.module == module.module {
              ConnectionFormView(store: store, spec: spec, mstodoAvailable: payload.mstodoAvailable)
            } else if module.module == .agenda, payload.googleConfigured {
              Button("Usar link iCal") { store.startNew(module.module) }
                .pillButtonStyle(.outline, size: .small)
            }
          }
          .padding(24)
        }
      }
      Rectangle().fill(theme.lineSoft).frame(height: 1).accessibilityHidden(true)
      HStack {
        Spacer()
        Button("Fechar") { store.close() }
          .pillButtonStyle(.outline)
          .keyboardShortcut(.cancelAction)
      }
      .padding(16)
    }
    .frame(width: 600, height: 540)
    .confirmDialog($confirm)
  }

  private func header(_ module: ModuleState, spec: ModuleSpec, payload: IntegrationsPayload) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: moduleSymbol(module.module))
        .font(.system(size: 22))
        .foregroundStyle(theme.inkMid)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(module.label)
          .typeRole(.subhead)
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        Text(module.summary)
          .typeRole(.data)
          .foregroundStyle(theme.inkMid)
      }
      Spacer()
      if store.editor == nil, let action = IntegrationForm.connectAction(for: module, spec: spec, payload: payload) {
        switch action {
        case .browser(let title, let path, let query):
          Button(title) {
            if let url = IntegrationForm.serverURL(server, path: path, query: query) { openURL(url) }
          }
          .pillButtonStyle(.primary)
          .disabled(server == nil)
        case .form(let title):
          Button(title) { store.startNew(module.module) }
            .pillButtonStyle(.primary)
        }
      }
    }
  }

  /// What the server's admin has to set up first (`IntegrationsPanel.tsx:422-446`).
  @ViewBuilder private func setupNotes(_ module: ModuleState, payload: IntegrationsPayload) -> some View {
    if module.module == .agenda, !payload.googleConfigured {
      setupNote(
        "Para conectar contas Google, quem administra este servidor precisa definir GOOGLE_CLIENT_ID e "
          + "GOOGLE_CLIENT_SECRET. Criar o client é gratuito; registre esta URI de redirecionamento:",
        uri: payload.googleRedirectUri)
    }
    if module.module == .slack, !payload.slackConfigured {
      setupNote(
        "Para conectar o Slack, quem administra este servidor precisa definir SLACK_CLIENT_ID e "
          + "SLACK_CLIENT_SECRET. Registre esta URI de redirecionamento:",
        uri: payload.slackRedirectUri)
    }
  }

  private func setupNote(_ text: String, uri: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(text)
      Text(uri)
        .font(.dailyMono(size: 12))
        .foregroundStyle(theme.ink)
        .textSelection(.enabled)
    }
    .typeRole(.caption)
    .foregroundStyle(theme.inkMid)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.small)
        .strokeBorder(theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
  }
}

private struct ConnectionRow: View {
  @Environment(\.theme) private var theme
  let store: IntegrationsStore
  let connection: ConnectionSummary
  let spec: ModuleSpec
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(connection.label)
            .typeRole(.data)
            .foregroundStyle(theme.ink)
          Text(IntegrationForm.subtitle(connection, spec: spec))
            .typeRole(.caption)
            .foregroundStyle(connection.unreadable ? theme.warning : theme.inkDim)
            .lineLimit(1)
        }
        Spacer()
        Button(store.testing == connection.id ? "Testando…" : "Testar") {
          Task { await store.test(connection) }
        }
        .pillButtonStyle(.outline, size: .small)
        .disabled(store.testing == connection.id)
        if IntegrationForm.isGoogle(connection) {
          if connection.module == .agenda {
            Button("Escolher agendas") { Task { await store.loadCalendars(connection.id) } }
              .pillButtonStyle(.outline, size: .small)
          }
        } else {
          IconButton("Editar", systemImage: "pencil", size: .small) { store.startEdit(connection) }
        }
        IconButton("Remover", systemImage: "trash", size: .small, action: onRemove)
      }
      if let calendars = store.calendars[connection.id] {
        CalendarChooser(store: store, connectionId: connection.id, calendars: calendars)
      }
      if let result = store.testResults[connection.id] {
        Label(result.message, systemImage: result.ok ? "checkmark.circle" : "exclamationmark.circle")
          .typeRole(.caption)
          .foregroundStyle(result.ok ? theme.success : theme.danger)
          .onAppear { AccessibilityNotification.Announcement(result.message).post() }
      }
    }
    .padding(12)
    .background(theme.surface1.opacity(0.6), in: .rect(cornerRadius: Radius.small))
    .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineSoft) }
  }
}

/// "Quais agendas mostrar" (`IntegrationsPanel.tsx:513-547`).
private struct CalendarChooser: View {
  let store: IntegrationsStore
  let connectionId: String
  let calendars: [CalendarRef]

  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Quais agendas mostrar")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityAddTraits(.isHeader)
      ForEach(calendars) { calendar in
        Toggle(calendar.label, isOn: chosen(calendar.id))
          .toggleStyle(.checkbox)
          .typeRole(.data)
      }
      Button("Salvar seleção") { Task { await store.saveCalendars(connectionId) } }
        .pillButtonStyle(.primary, size: .small)
        .padding(.top, 6)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineSoft) }
  }

  private func chosen(_ id: String) -> Binding<Bool> {
    Binding(
      get: { store.chosenCalendars[connectionId]?.contains(id) == true },
      set: { store.setCalendar(id, chosen: $0, connection: connectionId) }
    )
  }
}

/// The form generated from the catalog's fields (`Field` in `IntegrationsPanel.tsx`).
private struct ConnectionFormView: View {
  @Environment(\.theme) private var theme
  let store: IntegrationsStore
  let spec: ModuleSpec
  let mstodoAvailable: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if spec.multi {
        field(label: "Nome desta conexão", required: false, help: nil) {
          TextField("Nome desta conexão", text: labelBinding, prompt: Text("Trabalho, Pessoal…"))
            .singleLine(labelBinding)
        }
      }
      ForEach(store.visibleFields) { spec in
        field(label: spec.label, required: spec.required == true, help: spec.help) {
          input(for: spec)
        }
      }
      HStack {
        Button(store.isSaving ? "Salvando…" : "Salvar") { Task { await store.save() } }
          .pillButtonStyle(.primary, size: .small)
          .keyboardShortcut(.defaultAction)
          .disabled(store.isSaving)
        Button("Cancelar") { store.cancelEdit() }
          .pillButtonStyle(.ghost, size: .small)
      }
      .padding(.top, 4)
    }
    .textFieldStyle(.roundedBorder)
    .padding(16)
    .background(theme.surface1.opacity(0.6), in: .rect(cornerRadius: Radius.small))
    .overlay { RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.lineSoft) }
  }

  private func field<Input: View>(
    label: String,
    required: Bool,
    help: String?,
    @ViewBuilder input: () -> Input
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(required ? "\(label) *" : label)
        .typeRole(.caption)
        .foregroundStyle(theme.inkMid)
        .accessibilityHidden(true)
      input()
        .labelsHidden()
        .accessibilityLabel(label)
      if let help {
        Text(help)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
      }
    }
  }

  @ViewBuilder private func input(for field: FieldSpec) -> some View {
    let alreadySet = store.editor?.savedSecrets.contains(field.name) == true
    let placeholder = IntegrationForm.placeholder(for: field, alreadySet: alreadySet).map { Text($0) }
    switch field.type {
    case .select:
      Picker(field.label, selection: value(field.name)) {
        ForEach(IntegrationForm.options(for: field, mstodoAvailable: mstodoAvailable), id: \.value) { option in
          Text(option.label).tag(option.value)
        }
      }
    case .password:
      SecureField(field.label, text: value(field.name), prompt: placeholder)
        .singleLine(value(field.name))
    default:
      TextField(field.label, text: value(field.name), prompt: placeholder)
        .singleLine(value(field.name))
    }
  }

  private var labelBinding: Binding<String> {
    Binding(get: { store.editor?.label ?? "" }, set: { store.setLabel($0) })
  }

  /// An absent value reads as empty, like `values[field.name] ?? ''` on the web.
  private func value(_ name: String) -> Binding<String> {
    Binding(get: { store.editor?.values[name] ?? "" }, set: { store.setValue(name, $0) })
  }
}
