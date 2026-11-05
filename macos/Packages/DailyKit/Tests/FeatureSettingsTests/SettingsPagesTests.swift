import DailyCore
import DailyModels
import Testing

@testable import FeatureSettings

@Suite struct SettingsPagesTests {
  @Test func everyOldTabLandsOnItsPage() {
    #expect(SettingsPage(.integrations) == .ferramentas)
    #expect(SettingsPage(.profile) == .perfil)
    #expect(SettingsPage(.appearance) == .configuracao)
    #expect(SettingsPage(.users) == .configuracao)
    #expect(SettingsPage(.general) == .configuracao)
  }

  @Test func titlesAndDescriptionsAreTheWebs() {
    #expect(SettingsPage.ferramentas.title == "Ferramentas")
    #expect(SettingsPage.ferramentas.description == nil)
    #expect(SettingsPage.configuracao.title == "Configuração")
    #expect(
      SettingsPage.configuracao.description == "Ajuste a aparência, a disposição dos painéis e quem tem acesso.")
    #expect(SettingsPage.perfil.title == "Perfil")
    #expect(SettingsPage.perfil.description == "Sua foto, seus dados e sua senha.")
  }

  @Test func theProfileIsAsNarrowAsMaxWLg() {
    #expect(PerfilScreen.maxContentWidth == 512)
  }

  @Test func configurationUsesTwoColumnsOnlyWhenWide() {
    #expect(ConfiguracaoLayout.columns(forWidth: 600) == 1)
    #expect(ConfiguracaoLayout.columns(forWidth: ConfiguracaoLayout.twoColumnMinWidth - 1) == 1)
    #expect(ConfiguracaoLayout.columns(forWidth: ConfiguracaoLayout.twoColumnMinWidth) == 2)
  }

  @Test func theColumnsSplitOnePointFourToOne() {
    let widths = ConfiguracaoLayout.columnWidths(forWidth: 1016)
    #expect(widths.leading + widths.trailing + ConfiguracaoLayout.spacing == 1016)
    #expect(widths.leading == 583)
    #expect(widths.trailing == 417)
  }

  @Test func onlyAnAdminSeesTheUsers() {
    let admin = CurrentUser(username: "ana", isAdmin: true, avatarUrl: nil, fullName: nil, email: nil)
    let member = CurrentUser(username: "bruno", isAdmin: false, avatarUrl: nil, fullName: nil, email: nil)
    #expect(UsersAccess.canManage(admin))
    #expect(!UsersAccess.canManage(member))
    #expect(!UsersAccess.canManage(nil))
    #expect(UsersAccess.showsList(isAdmin: true, forbidden: false))
    // A 403 wins over the session's flag: the server is the authority.
    #expect(!UsersAccess.showsList(isAdmin: true, forbidden: true))
    #expect(!UsersAccess.showsList(isAdmin: false, forbidden: false))
  }

  @Test func theLayoutTextDoesNotSendYouToButtonsThatDoNotExist() {
    #expect(!LayoutSettingsView.explanation.contains("Concluir"))
    #expect(LayoutSettingsView.explanation.contains("segure um painel por meio segundo"))
  }
}
