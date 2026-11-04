# Validação

Evidências de cada tarefa concluída. Comandos executados a partir da raiz do
repositório, salvo indicação.

## Base do web (T008), 2026-11-04, commit `85e6ad1`

Medida com `macos/` fora da árvore, ou seja, o estado do `main`:

| Verificação | Resultado |
|---|---|
| `npx tsc --noEmit` | exit 0 |
| `npm test` | 195 arquivos, 3145 testes, todos passando |
| `npm run build` | exit 0 |
| CSS gerado (`.next/static/**/*.css`, sha256) | `40fd8c84…dbfe2`, `d3b422f9…e7cae`, `6e6627b3…c4bc4b` |

Observação: o `node_modules` do checkout principal estava desatualizado (faltava
`@danfessler/trellis`). A worktree usa `npm ci`, que segue o lockfile sem mudar
dependências.

## T001: `deploy/publish.sh`

`--exclude 'macos/'` no rsync. Verificado por leitura: é o único rsync do script.

## T002: `app/globals.css`, `@source not "../macos"`

| Cenário | CSS comparado à base |
|---|---|
| `macos/probe/Probe.swift` com a string `"bg-fuchsia-900 grid-cols-11 translate-x-97"`, **sem** T002 | **diferente**: um arquivo mudou (`40fd8c84…` → `91e38e6c…`) |
| Mesmo arquivo de teste, **com** T002 | **idêntico** aos três hashes da base |

Depois da T002: `npx tsc --noEmit` exit 0 e `npm test` com 195 arquivos e 3145
testes passando. O arquivo de teste foi removido.

Nota de processo: `npx tsc --noEmit` reescreve o `tsconfig.tsbuildinfo`, que é
versionado. Restaure-o com `git checkout -- tsconfig.tsbuildinfo` depois de cada
verificação.

## T003: dependências

Tags confirmadas por `git ls-remote`: `gonzalezreal/textual` 0.5.0 e
`sindresorhus/KeyboardShortcuts` 3.1.0. As duas resolvem e compilam no `swift build`.

## T004–T007: esqueleto

Em `macos/`, `make check` termina com exit 0. Ele inclui:

- `swift format lint --strict`, sem achados;
- `swift test`, com 18 testes (um por target) passando;
- `xcodebuild` Debug compilando o app.

O app sai com o identificador `io.github.novaisvictor.dailyweb` e assinatura ad-hoc
(em Debug, `codesign` desliga o hardened runtime com ad-hoc, como esperado).

## Onda 1: T101–T104 (gate em 2026-11-04)

Em `macos/`, `make check` termina com exit 0: lint sem achados, **106 testes em 12 suítes** passando e o app compilando.

| Tarefa | Evidência |
|---|---|
| T101 Modelos | 73 fixtures fictícios; todos decodificam e fazem encode → decode igual; o reencode precisa conter toda chave não nula; enum desconhecido decodifica |
| T102 API/armazenamento | 31 testes com `URLProtocol` stub cobrindo `Cookie`, `Origin`, idempotência, `Authorization` nunca enviado, três formatos de erro, 401, mapeamento de `URLError`, 204. O Keychain de login passa. O Keychain moderno é pulado, porque com assinatura ad-hoc responde -34018 |
| T103 Design | 18 testes: contraste WCAG (ink/surface ≥ 11,4; inkMid ≥ 8,0 em todas as paletas), fallback de Dracula e WezTerm no tema claro, conversão de oklch |
| T104 Shell | 20 testes: ordem e fallback da barra lateral, busca da paleta, validação do endereço do servidor |

Ajustes do orquestrador no gate:

- `APIError.storage(detail:)`. Falha ao gravar no Keychain deixa de aparecer como "sessão expirou".
- Contrato corrigido em três respostas do Jira.

Fora de `macos/`, nada mudou nesta onda.

## Onda 2: contrato contra o servidor real (2026-11-04)

O servidor rodou com `npm run dev` na worktree, com `.env.local` local e um banco
SQLite descartável (`data/macos-dev.db`), usando o usuário de teste `macos-dev`
(admin). Um executável descartável usou o `HTTPAPIClient` real do DailyKit:

| Passo | Resultado |
|---|---|
| Login com senha errada | `.server(401)` → "usuário ou senha inválidos" |
| Login correto em `http://localhost:8010` | token do `Set-Cookie` (cookie `Secure`) guardado |
| `GET /api/me` | decodifica `CurrentUser` (`macos-dev`, admin) |
| `GET /api/state` | decodifica `DashboardState` real (módulos `tasks` e `notes`, pomodoro ligado) |
| `signOut` + `GET /api/me` | `.unauthorized` |

Ainda não verificado nesta etapa: o login pela interface do app empacotado, com
sandbox e Keychain de login.

## Onda 2: gate e revisão (T203)

A revisão independente (skill `code-review`, nível medium) encontrou 10 achados,
todos corrigidos com teste de regressão:

- sessão expirada mantendo dados da conta anterior;
- `restore` repetido por janela;
- ordem das atualizações de aparência;
- aparência não sincronizada (limitação do servidor, que não tem GET; o espelho passou a ser por conta);
- cadência por foco em vez de visibilidade;
- ATS sem mensagem própria;
- cache gravado na thread principal;
- erro de leitura antiga gravado;
- formatação de data duplicada;
- fallback silencioso em `Endpoint.segment`.

`make check` termina com exit 0, com **189 testes em 21 suítes**. Nada mudou
fora de `macos/` nesta onda.
