import ServiceManagement
import Testing

@testable import FeatureShell

private struct LoginItemFailure: LocalizedError {
  var errorDescription: String? { "Operação não permitida." }
}

private final class FakeLoginItem: LoginItemService {
  var status: SMAppService.Status = .notRegistered
  var failure: (any Error)?
  var calls: [String] = []

  func register() throws {
    calls.append("register")
    if let failure { throw failure }
    status = .enabled
  }

  func unregister() throws {
    calls.append("unregister")
    if let failure { throw failure }
    status = .notRegistered
  }
}

@Suite struct LaunchAtLoginTests {
  @Test func turningOnRegistersAndShowsTheNewStatus() {
    let service = FakeLoginItem()
    let model = LaunchAtLogin(service: service)
    #expect(!model.isOn)
    model.setOn(true)
    #expect(service.calls == ["register"])
    #expect(model.isOn)
    #expect(model.errorMessage == nil)
    model.setOn(false)
    #expect(service.calls == ["register", "unregister"])
    #expect(!model.isOn)
  }

  @Test func aFailureShowsTheSystemMessageAndKeepsTheRealStatus() {
    let service = FakeLoginItem()
    service.failure = LoginItemFailure()
    let model = LaunchAtLogin(service: service)
    model.setOn(true)
    #expect(model.errorMessage == "Operação não permitida.")
    #expect(!model.isOn)
  }

  @Test func pendingApprovalCountsAsOnAndAsksForIt() {
    let service = FakeLoginItem()
    service.status = .requiresApproval
    let model = LaunchAtLogin(service: service)
    #expect(model.isOn)
    #expect(model.needsApproval)
    service.status = .enabled
    model.reload()
    #expect(!model.needsApproval)
  }
}
