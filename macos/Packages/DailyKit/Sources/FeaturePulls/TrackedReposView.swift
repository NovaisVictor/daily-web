import DailyDesign
import SwiftUI

/// "Repositórios acompanhados" (`PullsPanel.tsx:330-390`): add and remove
/// repositories, and choose whose PRs to follow in each.
struct TrackedReposView: View {
  @Environment(\.theme) private var theme
  @Bindable var store: PullsStore

  var body: some View {
    DisclosureGroup("Repositórios acompanhados", isExpanded: $store.reposExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(store.repos, id: \.self) { repo in
          VStack(alignment: .leading, spacing: 6) {
            RepoPill(repo) { Task { await store.removeRepo(repo) } }
            RepoAuthorsView(repo: repo, store: store)
          }
        }
        if store.repos.isEmpty, store.reposLoaded {
          Text("Nenhum repositório acompanhado ainda.").font(.daily(size: 14)).foregroundStyle(theme.inkDim)
        }
        HStack(spacing: 8) {
          TextField("owner/repo", text: $store.newRepo)
            .singleLine($store.newRepo)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("novo repositório")
            .onSubmit { Task { await store.addRepo() } }
          IconButton("Adicionar repositório", systemImage: "plus", variant: .outline) {
            Task { await store.addRepo() }
          }
        }
        if let error = store.reposError { PanelError(error) }
      }
      .padding(.top, 12)
    }
    .foregroundStyle(theme.inkDim)
  }
}

/// Who is followed in one tracked repo. No authors means everyone: the list
/// only ever narrows (`components/pulls/RepoAuthors.tsx`).
private struct RepoAuthorsView: View {
  @Environment(\.theme) private var theme
  let repo: String
  @Bindable var store: PullsStore

  var body: some View {
    let authors = store.authors[repo] ?? []
    VStack(alignment: .leading, spacing: 6) {
      FlowLayout(spacing: 6) {
        if authors.isEmpty {
          Text("todos os autores").font(.daily(size: 12)).foregroundStyle(theme.inkDim)
        }
        ForEach(authors, id: \.self) { author in
          HStack(spacing: 2) {
            Text(author).font(.daily(size: 12)).foregroundStyle(theme.inkMid)
            Button {
              Task { await store.removeAuthor(author, from: repo) }
            } label: {
              Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkDim)
            .accessibilityLabel("deixar de acompanhar \(author) em \(repo)")
          }
          .padding(.leading, 8)
          .padding(.trailing, 4)
          .padding(.vertical, 1)
          .background(theme.surface1, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.line) }
        }
      }
      HStack(spacing: 6) {
        TextField("acompanhar só este autor", text: draft)
          .singleLine(draft)
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .accessibilityLabel("novo autor em \(repo)")
          .onSubmit { Task { await store.addAuthor(to: repo) } }
        IconButton("Acompanhar autor em \(repo)", systemImage: "plus", size: .small, variant: .outline) {
          Task { await store.addAuthor(to: repo) }
        }
      }
      if let error = store.authorErrors[repo] {
        Text(error).font(.daily(size: 12)).foregroundStyle(theme.danger)
      }
    }
    .padding(.leading, 12)
  }

  private var draft: Binding<String> {
    Binding(get: { store.authorDrafts[repo] ?? "" }, set: { store.authorDrafts[repo] = $0 })
  }
}
