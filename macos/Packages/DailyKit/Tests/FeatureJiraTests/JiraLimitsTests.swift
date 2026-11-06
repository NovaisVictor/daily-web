import Testing

@testable import FeatureJira

/// The cut hint the dialogs show where the web's `maxLength` cuts silently.
@Suite struct JiraLimitsTests {
  @Test func cutsAPastePastTheLimitAndSaysSo() {
    let capped = JiraLimits.capped("abcdef", limit: 4, wasCut: false)
    #expect(capped.text == "abcd")
    #expect(capped.cut)
  }

  @Test func keepsTheHintWhileTheTextStaysAtTheLimit() {
    // The field reports the cut text back; the hint must survive that echo.
    #expect(JiraLimits.capped("abcd", limit: 4, wasCut: true).text == "abcd")
    #expect(JiraLimits.capped("abcd", limit: 4, wasCut: true).cut)
  }

  @Test func dropsTheHintOnceTheTextIsShortened() {
    #expect(JiraLimits.capped("abc", limit: 4, wasCut: true).text == "abc")
    #expect(!JiraLimits.capped("abc", limit: 4, wasCut: true).cut)
  }

  @Test func neverShowsTheHintForTypingUpToTheLimit() {
    #expect(JiraLimits.capped("abcd", limit: 4, wasCut: false).text == "abcd")
    #expect(!JiraLimits.capped("abcd", limit: 4, wasCut: false).cut)
  }

  @Test func namesTheLimit() {
    #expect(JiraLimits.cutHint(255) == "Limite de 255 caracteres: o excedente foi cortado.")
  }
}
