import DailyCore
import DailyModels
import Testing

@testable import FeatureShell

@Suite struct SessionScreenTests {
  private let ana = CurrentUser(username: "ana", isAdmin: false, avatarUrl: nil, fullName: nil, email: nil)

  @Test func restoringIsLoadingUntilTheRestoreFails() {
    #expect(SessionScreen(phase: .restoring, hasRestoreError: false) == .loading)
    #expect(SessionScreen(phase: .restoring, hasRestoreError: true) == .restoreFailed)
  }

  @Test func signedOutIsTheLoginWhateverTheMessage() {
    #expect(SessionScreen(phase: .signedOut(message: nil), hasRestoreError: false) == .login)
    #expect(SessionScreen(phase: .signedOut(message: SessionStore.expiredMessage), hasRestoreError: false) == .login)
  }

  @Test func aProfileEditIsNotAChangeOfScreen() {
    var edited = ana
    edited.fullName = "Ana S."
    #expect(SessionScreen(phase: .signedIn(ana), hasRestoreError: false) == .main)
    #expect(
      SessionScreen(phase: .signedIn(ana), hasRestoreError: false)
        == SessionScreen(phase: .signedIn(edited), hasRestoreError: false))
  }
}
