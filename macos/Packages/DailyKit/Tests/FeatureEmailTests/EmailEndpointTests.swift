import DailyAPI
import DailyModels
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import FeatureEmail

@Suite struct EmailEndpointTests {
  let message = envelope("41/82", account: "conn 1", from: "Ana <ana@example.com>", subject: "Oi", folder: "Clientes")

  func query<T>(_ endpoint: Endpoint<T>) -> String {
    endpoint.query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test func reads() {
    let stored = EmailEndpoints.mailboxes(account: "c1", sync: false)
    #expect(stored.method == .get && stored.path == "/api/email/mailboxes" && query(stored) == "account=c1")
    #expect(query(EmailEndpoints.mailboxes(account: "c1", sync: true)) == "account=c1&sync=1")
    let folders = EmailEndpoints.folders(account: "c1")
    #expect(folders.path == "/api/email/folders" && query(folders) == "account=c1")
    let messages = EmailEndpoints.messages(account: "c1", folder: "Clientes/Acme")
    #expect(messages.path == "/api/email/messages" && query(messages) == "account=c1&folder=Clientes/Acme")
    let body = EmailEndpoints.body(account: message.account, id: message.id, box: .sent)
    #expect(body.method == .get && body.path == "/api/email/conn%201/41%2F82/body" && query(body) == "box=sent")
    #expect(EmailEndpoints.noteFolders.path == "/api/notes/folders")
  }

  @Test func batchOmitsTheFolderWhenThereIsNone() {
    let targets = [EmailTarget(account: "c1", id: "1"), EmailTarget(account: "c1", id: "2")]
    let read = EmailEndpoints.batch(targets, action: .read, folder: nil, folderPath: "INBOX")
    #expect(read.method == .post && read.path == "/api/email/batch")
    #expect(
      FakeAPIClient.encode(read.body)
        == #"{"action":"read","folderPath":"INBOX","targets":[{"account":"c1","id":"1"},{"account":"c1","id":"2"}]}"#)
    let move = EmailEndpoints.batch(targets, action: .move, folder: "Arquivo", folderPath: "Clientes")
    #expect(
      FakeAPIClient.encode(move.body)
        == #"{"action":"move","folder":"Arquivo","folderPath":"Clientes","targets":[{"account":"c1","id":"1"},{"account":"c1","id":"2"}]}"#
    )
  }

  @Test func writes() {
    let mark = EmailEndpoints.mark(message, seen: true)
    #expect(mark.path == "/api/email/mark")
    #expect(FakeAPIClient.encode(mark.body) == #"{"account":"conn 1","folder":"Clientes","id":"41/82","seen":true}"#)
    let folderRead = EmailEndpoints.folderRead(account: "c1", folder: "Clientes")
    #expect(folderRead.path == "/api/email/folder/read")
    #expect(FakeAPIClient.encode(folderRead.body) == #"{"account":"c1","folder":"Clientes"}"#)
    let draft = EmailEndpoints.replyDraft(message, instruction: "confirmo terça")
    #expect(draft.path == "/api/email/reply/draft")
    #expect(
      FakeAPIClient.encode(draft.body)
        == #"{"account":"conn 1","from":"Ana <ana@example.com>","id":"41/82","instruction":"confirmo terça","subject":"Oi"}"#
    )
    let reply = EmailEndpoints.reply(message, body: "Combinado")
    #expect(reply.path == "/api/email/reply")
    #expect(FakeAPIClient.encode(reply.body) == #"{"account":"conn 1","body":"Combinado","id":"41/82"}"#)
    let note = EmailEndpoints.toNote(message, noteFolderId: "f1")
    #expect(note.path == "/api/email/to-note")
    #expect(
      FakeAPIClient.encode(note.body) == #"{"account":"conn 1","folder":"Clientes","folderId":"f1","id":"41/82"}"#)
    #expect(
      FakeAPIClient.encode(EmailEndpoints.toNote(message, noteFolderId: nil).body)
        == #"{"account":"conn 1","folder":"Clientes","id":"41/82"}"#)
    let task = EmailEndpoints.toTask(message)
    #expect(task.path == "/api/email/to-task")
    #expect(FakeAPIClient.encode(task.body) == #"{"account":"conn 1","folder":"Clientes","id":"41/82"}"#)
  }

  @Test func dragTokenRoundTripsThroughItsOwnContentType() throws {
    let token = EmailDragToken(threadID: "c1:9")
    let data = try JSONEncoder().encode(token)
    #expect(try JSONDecoder().decode(EmailDragToken.self, from: data) == token)
    #expect(UTType.dailyEmailDrag.identifier == "io.github.novaisvictor.dailyweb.email-drag")
  }
}
