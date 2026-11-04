import DailyDesign
import Observation
import ServiceManagement
import SwiftUI
import os

/// The login item calls, so tests can stand in for `SMAppService`.
public protocol LoginItemService {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

extension SMAppService: LoginItemService {}

/// "Abrir ao iniciar": registers the app itself as a login item.
@Observable
public final class LaunchAtLogin {
  public private(set) var status: SMAppService.Status
  /// The system's message for the last failed change.
  public private(set) var errorMessage: String?

  @ObservationIgnored private let service: any LoginItemService
  private static let logger = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureShell")

  public init(service: any LoginItemService = SMAppService.mainApp) {
    self.service = service
    status = service.status
  }

  /// On, or waiting for the user's approval in System Settings: either way the
  /// app asked to open at login.
  public var isOn: Bool { status == .enabled || status == .requiresApproval }

  public var needsApproval: Bool { status == .requiresApproval }

  /// What the toggle's caption says about the current state.
  public var statusText: String {
    switch status {
    case .enabled: "O Daily Web abre quando você inicia a sessão."
    case .requiresApproval: "Falta aprovar em Ajustes do Sistema › Geral › Itens de Início."
    case .notFound: "O macOS não encontrou o app para abrir ao iniciar."
    case .notRegistered: "Desligado."
    @unknown default: "Estado desconhecido."
    }
  }

  public func setOn(_ on: Bool) {
    errorMessage = nil
    do {
      if on { try service.register() } else { try service.unregister() }
    } catch {
      Self.logger.error("Login item change failed: \(String(describing: error), privacy: .public)")
      errorMessage = error.localizedDescription
    }
    status = service.status
  }

  /// The user may have changed it in System Settings meanwhile.
  public func reload() {
    status = service.status
  }
}

/// The toggle, its state and the system's error, for Settings → Geral.
public struct LaunchAtLoginToggle: View {
  @State private var model: LaunchAtLogin
  @Environment(\.theme) private var theme

  public init(model: LaunchAtLogin = LaunchAtLogin()) {
    _model = State(initialValue: model)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle("Abrir ao iniciar a sessão", isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))
      Text(model.statusText).font(.caption).foregroundStyle(theme.inkDim)
      if model.needsApproval {
        Button("Abrir Itens de Início") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = model.errorMessage {
        Text(error).font(.caption).foregroundStyle(theme.danger)
      }
    }
    .onAppear { model.reload() }
  }
}
