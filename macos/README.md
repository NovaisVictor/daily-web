# Daily Web para macOS

Cliente nativo (SwiftUI) do daily-web. Ele conversa com o mesmo servidor do
painel web, pela mesma API.

> Em desenvolvimento. O plano está em [docs/](docs/plan.md).

## Requisitos

- macOS 26 ou superior, Apple Silicon.
- Um servidor daily-web acessível e uma conta nele.

## Instalação

A distribuição por Homebrew chega na Onda 6 (veja [docs/tasks.md](docs/tasks.md)).

## Desenvolvimento

Requer o Xcode 26.6 ou superior.

```sh
cd macos
make build   # compila o pacote DailyKit
make test    # roda os testes
make lint    # confere a formatação (swift format)
make app     # compila o app pelo Xcode
make check   # lint + testes + app
```

Para abrir no Xcode, use `macos/DailyWeb.xcodeproj`.

Para usar contra um servidor local, rode `npm run dev` na raiz do repositório e
informe `http://localhost:8010` na tela de login do app.

## Estrutura

| Caminho | O que é |
|---|---|
| `App/` | Target do app: cenas e composição |
| `Packages/DailyKit/` | Todo o código: modelos, API, armazenamento, design, núcleo e uma pasta por funcionalidade |
| `Config/` | `xcconfig` e entitlements |
| `docs/` | Spec, plano, pesquisa, contrato da API e tarefas |
