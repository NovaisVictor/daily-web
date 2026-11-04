import Foundation
import Testing

@testable import FeatureShell

@Suite struct ServerAddressTests {
  @Test(arguments: ["https://daily.exemplo.com", "  http://localhost:3000 ", "HTTPS://Daily.Exemplo.com/base"])
  func acceptsHTTPAddresses(raw: String) throws {
    let url = try ServerAddress.parse(raw).get()
    #expect(url.host() != nil)
  }

  @Test func rejectsEmpty() {
    #expect(ServerAddress.parse("   ") == .failure(.empty))
    #expect(ServerAddressError.empty.message == "Informe o endereço do servidor.")
  }

  @Test(arguments: ["daily.exemplo.com", "ftp://daily.exemplo.com", "localhost:3000"])
  func rejectsOtherSchemes(raw: String) {
    #expect(ServerAddress.parse(raw) == .failure(.unsupportedScheme))
    #expect(
      ServerAddressError.unsupportedScheme.message == "O endereço do servidor precisa começar com http:// ou https://.")
  }

  @Test func rejectsMissingHost() {
    #expect(ServerAddress.parse("https://") == .failure(.missingHost))
    #expect(ServerAddress.parse("http:/caminho") == .failure(.missingHost))
  }

  @Test func rejectsUnparseableText() {
    #expect(ServerAddress.parse("https://exem plo.com") == .failure(.invalid))
  }
}
