# Plano de implementação: Daily Web para macOS

**Spec**: [spec.md](spec.md) · **Pesquisa**: [research.md](research.md) ·
**Contrato**: [contracts/api.md](contracts/api.md) · **Tarefas**: [tasks.md](tasks.md)

## Contexto técnico

| Item | Escolha |
|---|---|
| Linguagem | Swift 6.3, modo de linguagem 6, concorrência estrita completa, warnings como erro |
| UI | SwiftUI (AppKit só quando o SwiftUI não cobrir, via `NSViewRepresentable`) |
| Alvo | macOS 26+, arm64 |
| Toolchain local | Xcode 26.6, Swift 6.3.3, Homebrew 7.0.12 |
| Projeto | `.xcodeproj` mínimo com pasta sincronizada + pacote SPM local `DailyKit` |
| Estado | MV com stores `@Observable` injetados por `Environment` (padrão do IceCubesApp) |
| Rede | `URLSession` async/await, um tipo `Endpoint<Response>` por chamada, um decoder |
| Persistência | Keychain (sessão) + cache JSON em `Application Support` (último `DashboardState`) |
| Testes | Swift Testing, `URLProtocol` stub e fixtures JSON |
| Formatação | `swift format` do toolchain (sem instalar nada) |
| Distribuição | Cask sem notarização num tap pessoal, com assinatura própria estável (ver [Distribuição](#distribuição)) |

## Arquitetura

```
DailyWeb.app (target do Xcode: só montagem de cenas e ciclo de vida)
 └── DailyKit (pacote SPM local)
      ├── DailyModels     tipos Codable espelhando lib/types.ts; sem dependências
      ├── DailyAPI        APIClient, Endpoint<T>, erros, auth headers; → Models
      ├── DailyStorage    Keychain, cache em disco, configurações locais
      ├── DailyDesign     tokens de tema, tipografia, componentes base; sem rede
      ├── DailyCore       SessionStore, DashboardStore, Poller, AlertEngine,
      │                   Router, Toasts; → Models, API, Storage
      └── Feature*        uma por módulo; → Core, Design (nunca outra Feature)
           FeatureShell, FeatureHome, FeatureTasks, FeatureNotes, FeatureEmail,
           FeatureAgenda, FeatureJira, FeaturePulls, FeatureSlack,
           FeatureAgents, FeatureAccess, FeatureNotifications, FeatureSettings
```

Regras de dependência (o compilador garante pelos targets):

- Uma feature **não importa outra feature**. O que for compartilhado sobe para
  `DailyCore` (estado/ações) ou `DailyDesign` (visual). Exemplos: "agendar foco"
  é usado por Tarefas, Jira e Pulls, então `FocusScheduler` mora em `DailyCore`
  e `FocusDropTarget` em `DailyDesign`.
- O `FeatureShell` monta a navegação. Para não importar as features, ele recebe
  as telas por um registro (`ModuleRegistry`) que o target do app preenche.
- Os endpoints de cada módulo ficam **dentro da feature**, como extensões de
  `Endpoint`. O `DailyAPI` só tem o mecanismo e os endpoints do núcleo (login,
  me, state, refresh, preferences).

### Estrutura de pastas

```
macos/
├── AGENTS.md                 regras para quem (pessoa ou agente) mexe aqui
├── README.md                 build, instalação via brew, primeiro uso
├── Makefile                  build, test, lint, app, release
├── .swift-format
├── .gitignore                .build/, DerivedData/, dist/
├── Config/                   Base/Debug/Release.xcconfig, DailyWeb.entitlements
├── DailyWeb.xcodeproj
├── App/                      pasta sincronizada do target do app
│   ├── DailyWebApp.swift     cenas: WindowGroup, Settings, MenuBarExtra
│   ├── AppDelegate.swift
│   ├── ModuleRegistry+App.swift
│   └── Assets.xcassets
├── Packages/DailyKit/
│   ├── Package.swift         todos os targets declarados na Onda 0
│   ├── Sources/<Target>/
│   └── Tests/<Target>Tests/  + Fixtures/*.json
├── Scripts/                  build-app.sh, sign.sh, release.sh, cask.rb.tmpl
└── docs/                     este plano
```

### Padrões de código (detalhados em `macos/AGENTS.md`)

- **Store por feature**: `@Observable @MainActor final class TasksStore`. Ele
  recebe `APIClient` e `DashboardStore` no `init` e expõe estado e ações `async`.
  As views não chamam a API diretamente.
- **Endpoint tipado**: `Endpoint<Response: Decodable>` com método, caminho,
  query, corpo `Encodable` e flags (`write`, `idempotent`).
  `APIClient.send(_:) async throws(APIError) -> Response`.
- **Erros**: `APIError` cobre os dois formatos do servidor (`{error: string}` e
  `{error: {code, message, retry}}`), além de `unauthorized`, `offline`,
  `decoding` e `server(status)`. Nada de `try?` que esconda falha (regra do repositório).
- **Otimista**: `DashboardStore.mutate { state in … } commit: { try await … }`
  aplica a mudança, envia e desfaz se der erro, avisando com toast.
- **Fixtures**: cada tipo decodificável tem um JSON real ou derivado do servidor
  em `Tests/DailyModelsTests/Fixtures/`. Os testes decodificam todos.
- **Textos**: português, iguais aos do web (copiar o rótulo do componente
  correspondente), para que web e app digam a mesma coisa.

## Autenticação e rede

- O servidor (URL base) fica em `UserDefaults`. Padrão vazio, então o primeiro
  uso pede servidor, usuário e senha.
- No login, o app lê o `Set-Cookie` de `daily_web_session` na resposta e grava o
  valor no Keychain (`kSecClassGenericPassword`, serviço = host do servidor). O
  `URLSession` usa `httpCookieStorage = nil`, e o header `Cookie` é montado à mão
  em toda requisição. Isso funciona em http local e em https.
- Escritas enviam `Origin: <servidor>`. Pulls e mensagens para agentes enviam
  também `Idempotency-Key` (UUID) e `X-Request-Timestamp`.
- Um 401 limpa o Keychain e leva ao login, sem loop de nova tentativa.
- Timeout de 30 s, igual ao do web para e-mail. Sem retry automático em escrita.

## Polling, ciclo de vida e avisos

- Um único `Poller` no `DailyCore` com escopos registrados. `state` roda a 20 s
  em primeiro plano e a 60 s em segundo plano. `agents` roda a 2 s só com a tela
  visível. `notesSync` roda a 10 s com Drive conectado e a tela aberta.
- A visibilidade vem de `scenePhase`/`NSApplication.occlusionState`: janela
  oculta conta como segundo plano.
- O `AlertEngine` compara o estado novo com o anterior, com as mesmas regras de
  `lib/desktopAlerts.ts`, e dispara `UNUserNotificationCenter`. Os ids já vistos
  ficam em disco para não repetir aviso depois de reabrir o app.
- O cache do último `DashboardState` é carregado ao abrir, então a janela aparece
  preenchida e atualiza em seguida.

## Interface

- `NavigationSplitView`: barra lateral com Hoje, depois os módulos ligados
  (`state.modules`) na ordem do web, depois Agentes, Acesso e Configurações.
- A paleta de comandos (⌘K) usa as mesmas entradas do `CommandPalette.tsx`.
- `Settings` (⌘,) tem abas Aparência, Integrações, Perfil, Usuários (admin) e
  Disposição. A aba Disposição só tem o atalho global e "abrir ao iniciar".
- A barra de menus (`MenuBarExtra`) mostra pomodoro, próximas tarefas e eventos,
  e notificações não lidas.
- O markdown das notas usa o Textual (veja Dependências). O corpo de e-mail HTML
  usa o `WebView` do SwiftUI com JavaScript desligado, armazenamento não
  persistente e conteúdo remoto bloqueado até o usuário liberar.

## Dependências

Precisam de aprovação antes da Onda 0 (regra do repositório):

| Pacote | Versão | Para quê | Alternativa rejeitada |
|---|---|---|---|
| [Textual](https://github.com/gonzalezreal/textual) | 0.5.0 exata | Pré-visualização Markdown com GFM e highlight | swift-markdown-ui (em manutenção); `AttributedString(markdown:)` puro (sem tabela nem bloco de código) |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 3.1.0 | Atalho global configurável | Carbon `RegisterEventHotKey` à mão (mais código, sem gravador de atalho) |

Fica de fora: TCA, Alamofire, KeychainAccess, GRDB/SwiftData e Sparkle (o brew
cuida das atualizações).

## Distribuição

Decisão de 2026-11-04: **cask sem notarização** num tap pessoal, sem pagar o Developer ID.

- **Repositório do tap**: `NovaisVictor/homebrew-tap`, a criar. Instalação:
  `brew tap novaisvictor/tap`, confiar no tap (Homebrew 6+), depois
  `brew install --cask daily-web`.
- **Release**: `macos/Scripts/release.sh <versão>` roda na máquina do Victor.
  O script compila em Release, assina, gera o zip com `ditto`, calcula o sha256,
  cria `gh release` no fork (`macos-v<versão>`) e atualiza o cask no tap. Não
  há workflow no `.github/` do upstream, então o CI do João fica intocado.
- **Assinatura**: um certificado de assinatura autoassinado e estável, criado uma
  vez e guardado no Keychain do Victor, em vez de ad-hoc. Com ad-hoc, cada versão
  é um "app diferente" para o Keychain e o usuário teria que permitir de novo o
  acesso ao token a cada atualização. Com identidade estável, a ACL do Keychain
  continua valendo entre versões. O Gatekeeper continua bloqueando a primeira
  abertura de cada versão baixada (quarentena), e o usuário libera em Ajustes →
  Privacidade e Segurança → "Abrir mesmo assim". O README documenta isso.
- **Não usar `postflight` para tirar a quarentena**: o Homebrew 7 descontinuou
  esses hooks, e isso contornaria o Gatekeeper.

## Estratégia de paralelismo (sub-agentes)

**Uma branch, uma PR.** Os sub-agentes trabalham **na mesma worktree**
(`.claude/worktrees/macos-app`), cada um dono de diretórios que não se sobrepõem.
Não há merge entre branches (o hook do repositório bloqueia `git merge`).

1. **Propriedade de arquivo**: cada tarefa em [tasks.md](tasks.md) lista os
   diretórios que pode tocar. O `Package.swift`, o `.xcodeproj`, `Config/` e
   `App/` são do orquestrador. Um agente que precise mudar algo fora da sua área
   descreve a mudança no relatório em vez de fazê-la.
2. **Build isolado**: cada agente compila e testa só o seu target, com cache
   próprio. Exemplo:
   `swift build --package-path macos/Packages/DailyKit --target FeatureTasks --scratch-path macos/.build/agents/tasks`.
   Assim os agentes não disputam o lock do `.build` padrão.
3. **Interfaces congeladas por onda**: as features só começam depois que
   `DailyModels`, `DailyAPI`, `DailyCore` e `DailyDesign` passam pelo gate. Mudar
   uma API do núcleo durante as ondas de feature é tarefa do orquestrador.
4. **Commits**: os agentes não fazem commit. No fim de cada onda, o orquestrador
   roda o gate e faz um commit por tarefa (Conventional Commits, em inglês).
5. **Gate de onda**: `make check` em `macos/` (build do app com `xcodebuild`, todos
   os testes, `swift format lint --strict`) e a verificação de não interferência no
   web (SC-003). Se falhar, a onda não fecha.
6. **Revisão**: no fim das Ondas 2, 4 e 6, uma revisão independente do diff
   acumulado (skill `code-review`), com os achados corrigidos antes de seguir.

### Prompt padrão de um sub-agente de feature

> Você implementa `<Feature>` do app macOS em `macos/Packages/DailyKit/Sources/<Target>`
> e `Tests/<Target>Tests`. Leia `macos/AGENTS.md`, `macos/docs/spec.md` (linha do
> módulo), `macos/docs/contracts/api.md` (seção do módulo) e os componentes web de
> referência `<lista>`, buscando paridade de ações, textos e estados vazios e de
> erro. Só altere os diretórios listados. Compile e teste só o seu target com
> `--scratch-path macos/.build/agents/<nome>`. Não faça commit. Relate o que foi
> feito, o que foi verificado, as divergências do web e o que precisou de mudança
> fora da sua área.

## Riscos

| Risco | Mitigação |
|---|---|
| A API muda no web e o app quebra sem aviso | Fixtures por tipo e decodificação tolerante (campos novos ignorados, opcionais onde o TS é opcional). Na fase de validação, um teste de contrato contra `npm run dev` local |
| PR enorme recusada no upstream (o `CONTRIBUTING.md` pede issue antes) | Abrir issue no `joaosouzacoder/daily-web` antes da Onda 0 (tarefa T000) |
| Tailwind v4 varre arquivos não ignorados e pode gerar CSS a partir de strings Swift | T002: `@source not "../macos"` em `app/globals.css`, com prova de CSS idêntico |
| Gatekeeper a cada atualização incomoda | Documentado. Migrar para Developer ID depois é só trocar a identidade em `sign.sh` |
| Agentes paralelos tocando o mesmo arquivo | Propriedade explícita por tarefa + revisão do orquestrador por onda |
| Concorrência estrita do Swift 6 trava o progresso de agentes | Núcleo `Sendable` desde a Onda 1; UI com `defaultIsolation(MainActor)` |
