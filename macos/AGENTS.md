# macos/: regras para quem mexe aqui

Vale para pessoas e agentes. O plano completo está em [docs/plan.md](docs/plan.md),
as tarefas em [docs/tasks.md](docs/tasks.md) e o contrato da API em
[docs/contracts/api.md](docs/contracts/api.md).

## O web não pode ser afetado

- Nada fora de `macos/` muda. As únicas exceções já aprovadas são o
  `--exclude 'macos/'` em `deploy/publish.sh` e o `@source not "../macos"` em
  `app/globals.css`.
- Se o app precisar de algo que a API não oferece, **não altere o servidor**.
  Descreva a necessidade no relatório.

## Propriedade de arquivos

- Cada tarefa do `docs/tasks.md` diz quais diretórios você pode alterar. Fora deles, só leitura.
- São do orquestrador: `Packages/DailyKit/Package.swift`, `DailyWeb.xcodeproj/`,
  `Config/`, `App/`, `Makefile`, `.swift-format` e as interfaces marcadas
  `FROZEN` (`Endpoint`, `APIClient`, `APIError`, `SessionTokenStore`,
  `ServerSettings`, `PanelResult`, `ModuleID`, `DashboardState`, `CurrentUser`,
  `ModuleRegistry`, `AppRoute`, `Theme`).
- Um tipo marcado `FROZEN NAME` pode ganhar campos pelo dono da tarefa, mas não
  pode ser renomeado nem perder membros públicos.
- Precisa mudar algo que não é seu? Não mude. Escreva no relatório o que, onde e por quê.
- Não faça commit. O orquestrador faz um commit por tarefa ao fechar a onda.

## Build e testes isolados

Use o seu próprio `--scratch-path` para não disputar o lock com outros agentes:

```sh
cd macos
swift build --package-path Packages/DailyKit --target <Target> --scratch-path .build/agents/<nome>
swift test  --package-path Packages/DailyKit --filter <Target>Tests --scratch-path .build/agents/<nome>
swift format lint --strict --recursive Packages/DailyKit/Sources/<Target> Packages/DailyKit/Tests/<Target>Tests
```

`make check` (lint, todos os testes e build do app no Xcode) é o gate de onda do orquestrador.

## Arquitetura

- Dependências permitidas: `Feature*` → `DailyCore`, `DailyDesign`, `DailyAPI`,
  `DailyModels`. **Uma feature nunca importa outra.** O que for compartilhado
  sobe para `DailyCore` (estado e ações) ou `DailyDesign` (visual).
- Estado: um store `@Observable final class` por feature (o isolamento padrão já é
  `MainActor`). Ele recebe `APIClient` e o store do painel no `init`. As views
  não chamam a API.
- Chamadas: endpoints da feature como funções estáticas que devolvem
  `Endpoint<Resposta>`, dentro do target da feature. Ids em caminho passam por
  `Endpoint.segment(_:)`.
- Modelos: `Codable`, `Sendable`, `Equatable`. Datas do servidor ficam como
  `String` (o servidor manda `""` como "sem data"). Valores de enum vindos do
  servidor decodificam com caso `unknown(String)` em vez de falhar.

## Código

- Swift 6, concorrência estrita e warnings como erro. Não use
  `@unchecked Sendable` nem `nonisolated(unsafe)` sem um comentário que
  justifique o uso.
- Erros explícitos: nada de `try?` que esconda falha, nada de `catch` vazio,
  nada de valor padrão mascarando erro. Mostre `APIError.userMessage` ao usuário
  e registre o detalhe com `os.Logger` (subsistema `io.github.novaisvictor.dailyweb`,
  categoria = target). Nunca logue token, senha ou conteúdo de e-mail.
- Comentários em inglês e só para explicar o **porquê**.
- Textos de interface em português, **copiados do componente web equivalente**
  (rótulos, vazios, confirmações, erros). Cite o arquivo web em comentário quando
  a regra não for óbvia.
- Acessibilidade: todo controle sem texto visível tem `accessibilityLabel`, igual
  ao `aria-label` do web. Tudo precisa ser alcançável por teclado.
- Previews com dados de exemplo e um `APIClient` falso. Previews nunca usam rede.

## Testes

- Swift Testing (`import Testing`, `@Test`, `#expect`).
- Stores testados com um `APIClient` falso que registra as chamadas: método,
  caminho e corpo. Cubra o sucesso, o erro do servidor e a reversão otimista.
- Decodificação testada com fixtures JSON em `Tests/<Target>Tests/Fixtures`. Os
  fixtures nunca contêm dado real de pessoa ou credencial.

## Relatório ao terminar

O relatório informa:

1. O que mudou, com os arquivos.
2. O que foi verificado: comandos e resultado.
3. As divergências do web: o que ficou diferente e por quê.
4. As pendências.
5. As mudanças necessárias fora da sua área.
