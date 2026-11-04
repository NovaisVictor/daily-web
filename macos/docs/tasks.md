# Tarefas: Daily Web para macOS

**Legenda**: `[P]` roda em paralelo com as outras `[P]` da mesma onda.
**Dono** é quem pode alterar os caminhos listados. **Orq.** é o orquestrador (a
sessão principal). Os caminhos são relativos a `macos/`, exceto quando indicado.
`Pkg` = `Packages/DailyKit`. Uma tarefa só é marcada `[x]` com evidência em
`validation.md`.

Cada onda termina com o **gate**:

1. `make check` passa: `xcodebuild` do app, `swift test` do pacote e `swift format lint --strict`.
2. Verificação de não interferência no web, descrita na seção [SC-003](#verificação-sc-003).
3. Um commit por tarefa, feito pelo Orq.

## Onda 0: fundação (Orq., sequencial)

- [-] **T000** ~~Abrir uma issue em `joaosouzacoder/daily-web`~~. Cancelada pelo Victor em 2026-11-04.
- [x] **T001** `deploy/publish.sh`: `--exclude 'macos/'` no rsync (aprovado em 2026-11-04).
- [x] **T002** `app/globals.css`: `@source not "../macos";` (aprovado em 2026-11-04).
  Prova: CSS do `npm run build` idêntico à base, mesmo com um arquivo Swift de teste em `macos/`.
- [x] **T003** Dependências aprovadas em 2026-11-04: Textual 0.5.0 e KeyboardShortcuts 3.1.0.
- [x] **T004** Esqueleto do projeto:
  - `DailyWeb.xcodeproj` com o target do app usando a pasta sincronizada `App/`
  - `Config/*.xcconfig` com Swift 6, warnings como erro e macOS 26
  - entitlements com sandbox e rede cliente
  - bundle id `io.github.novaisvictor.dailyweb`
- [x] **T005** `Pkg/Package.swift` com **todos** os targets do [plan.md](plan.md#arquitetura),
  seus test targets e as dependências aprovadas. Cada target recebe um arquivo
  placeholder que compila.
- [x] **T006** Interfaces congeladas do núcleo, só com assinaturas, sem
  implementação. Os agentes da Onda 1 codificam contra elas:
  - `DailyAPI`: `Endpoint<T>`, `EmptyResponse`, `APIClient`, `SessionTokenStore`,
    `ServerSettings`, `APIError`
  - `DailyModels`: `PanelResult<T>`, `ModuleID`, `DashboardState` e `CurrentUser`
    (só os nomes estão congelados; o T101 completa os campos)
  - `DailyCore`: `ModuleRegistry`, `ModuleEntry`, `AppRoute`
  - `DailyDesign`: `Theme`, `ThemePreference`, `Backdrop`, `Density`, `EnvironmentValues.theme`

  Sem protocolos de store: o shell (T104) recebe valores e closures, e o T201 faz a ligação.
- [x] **T007** `AGENTS.md`, `README.md` (esqueleto), `.swift-format`, `.gitignore`
  e `Makefile` (`build`, `test`, `lint`, `check`, `app`).
- [x] **T008** Gate da Onda 0 + medição de base do web (`npm test`, `npx tsc --noEmit`,
  `npm run build` e o hash do CSS gerado), guardada em `validation.md`.

## Onda 1: núcleo (4 agentes em paralelo)

- [x] **T101 [P] Modelos**: dono `Pkg/Sources/DailyModels`, `Pkg/Tests/DailyModelsTests`.
  - Escopo: todos os tipos de [contracts/api.md](contracts/api.md) e de
    `lib/types.ts`, `lib/agents/model.ts` e `lib/agents/schemas.ts`. Enums
    desconhecidos decodificam como `.unknown(String)`, sem falhar.
  - Fixtures: um JSON por tipo, incluindo um `DashboardState` completo com todos
    os módulos ligados e outro com módulos desligados.
  - Aceite: todo fixture decodifica, e `encode → decode` é idempotente nos corpos de requisição.
- [x] **T102 [P] API e armazenamento**: dono `Pkg/Sources/DailyAPI`, `Pkg/Sources/DailyStorage` e testes.
  - `APIClient` real implementando o protocolo do T006, com:
    - captura do `Set-Cookie` no login, `Cookie` manual e `Origin` em escrita
    - `Idempotency-Key`/`X-Request-Timestamp` opcionais
    - os dois formatos de erro, 401 → `.unauthorized` e timeout de 30 s
  - Endpoints do núcleo: login, logout, me, state, refresh, preferences.
  - Keychain (salvar, ler e apagar por host), cache JSON do último estado e
    configuração do servidor.
  - Aceite: testes com `URLProtocol` stub cobrindo cada header e cada formato de erro.
- [x] **T103 [P] Design**: dono `Pkg/Sources/DailyDesign` e testes.
  - Tokens de `app/globals.css` (claro/escuro × mesh/Catppuccin/Dracula/WezTerm),
    densidade, escala tipográfica, raio e durações.
  - Componentes: `EmptyState`, `ErrorState`, `PanelError`, `ConfirmDialog`
    (↩/Esc), `FilterBar`, `Chip`, `Badge`, `SearchField`, `Avatar`, `Toast`,
    `SectionHeader`, `LoadingState`, `FocusDropTarget`.
  - Galeria de previews.
  - Aceite: contraste AA nos pares texto/fundo de cada tema (teste) e previews renderizando.
- [x] **T104 [P] Shell**: dono `Pkg/Sources/FeatureShell` e testes.
  - `NavigationSplitView` com barra lateral montada do `ModuleRegistry` e de `state.modules`.
  - Tela de login (servidor, usuário, senha), paleta ⌘K com as entradas do
    `CommandPalette.tsx`, menu "Ajuda → Novidades" e contêiner de toasts.
  - Usa só as interfaces do T006, com stubs nos previews.

## Onda 2: estado (Orq. + 1 agente)

- [ ] **T201 Integração do núcleo** (Orq.): liga as implementações do T101–T104 no
  `App/`, troca os stubs e resolve divergências de interface.
- [ ] **T202 Stores do núcleo**: dono `Pkg/Sources/DailyCore` e testes.
  - `SessionStore` (login, logout, me, 401 → login).
  - `DashboardStore`: cache primeiro, `mutate` otimista com reversão e toast,
    refresh manual.
  - `Poller` com escopos e cadências do plano, pausa por visibilidade.
  - `PreferencesStore` (aparência, `agendaDays`, `tasksView`).
  - `FocusScheduler` (POST `focus-blocks`).
  - `AlertEngine` (diff → notificação local, regras de `lib/desktopAlerts.ts`,
    ids vistos em disco).
  - Aceite: testes de cadência com relógio injetável, reversão otimista e
    deduplicação de avisos.
- [ ] **T203** Gate + revisão do diff acumulado (skill `code-review`) + correções.

## Onda 3: features, lote A (5 agentes em paralelo)

Cada agente segue o prompt padrão do [plan.md](plan.md#prompt-padrão-de-um-sub-agente-de-feature).
O dono é sempre `Pkg/Sources/<Target>` + `Pkg/Tests/<Target>Tests`.

- [ ] **T301 [P] FeatureHome**: saudação, relógio, pomodoro (iniciar/pausar/zerar,
  relógio local reancorado, aviso de fase) e resumo "Hoje" dos módulos ligados.
  Ref.: `NowBand.tsx`, `Clock.tsx`, `Pomodoro.tsx`, `ShellUser.tsx`.
- [ ] **T302 [P] FeatureTasks**: tudo da linha "Tarefas" do spec.
  Ref.: `TasksPanel.tsx`, `TaskFormModal.tsx`, `components/tasks/*`, `lib/taskGrouping.ts`.
- [ ] **T303 [P] FeatureNotes**: tudo da linha "Notas", incluindo autosave em 700 ms
  e gravação ao fechar a janela. Ref.: `NotesPanel.tsx`, `components/notes/*`, `MarkdownView.tsx`.
- [ ] **T304 [P] FeatureEmail**: tudo da linha "E-mail", com o corpo HTML num
  `WebView` restrito. Ref.: `EmailPanel.tsx`, `components/email/*`,
  `lib/hooks/useMailboxGroups.tsx`, `lib/hooks/useFolderMessages.tsx`.
- [ ] **T305 [P] FeatureAgenda + FeatureSettings**: agenda (período, eventos, área
  de soltar) e a cena `Settings`:
  - Aparência, Perfil e Usuários (admin).
  - Integrações: ligar/desligar, conexões, testar, Google e Slack pelo navegador,
    escolha de calendários.

  Ref.: `AgendaPanel.tsx`, `AppearancePanel.tsx`, `ProfilePanel.tsx`,
  `UsersPanel.tsx`, `IntegrationsPanel.tsx`, `lib/modules.ts`.
- [ ] **T306** Gate da onda.

## Onda 4: features, lote B (4 agentes em paralelo)

- [ ] **T401 [P] FeatureJira**: tudo da linha "Jira", incluindo o resumo da daily
  (`lib/standup.ts`). Ref.: `JiraPanel.tsx`, `components/jira/*`,
  `JiraProblemFix.tsx`, `JiraMultiFilterDropdown.tsx`, `lib/jiraFilters.ts`, `lib/jiraOrder.ts`.
- [ ] **T402 [P] FeaturePulls**: tudo da linha "Pull requests".
  Ref.: `PullsPanel.tsx`, `components/pulls/*`.
- [ ] **T403 [P] FeatureSlack + FeatureNotifications**: Slack (menções e DMs) e a
  central de notificações (filtros, marcar lidas, responder menção do Jira usando
  o endpoint de comentário). Ref.: `SlackPanel.tsx`, `NotificationsBell.tsx`,
  `HeaderNotifications.tsx`.
- [ ] **T404 [P] FeatureAgents + FeatureAccess**:
  - Agentes: kanban, sessões, detalhe e transições com `expectedVersion`.
  - Terminal ao vivo com resposta (⌘↩) e aviso "aguardando você".
  - Tokens, prompt, MCP e concessões.

  Ref.: `components/agents/*`, `AccessPanel.tsx`.
- [ ] **T405** Gate + revisão do diff acumulado + correções.

## Onda 5: integração e acabamento (2 agentes em paralelo + Orq.)

- [ ] **T501 [P] Mac-isms**: dono `App/` (cedido pelo Orq. nesta onda) e `FeatureShell`.
  - `MenuBarExtra` (pomodoro, próximas tarefas e eventos, não lidas) e atalho global.
  - "Abrir ao iniciar" e janelas extras por módulo.
  - Menus com os atalhos de cada feature e ações nas notificações (abrir item, marcar lida).
- [ ] **T502 [P] Paridade e qualidade**: só leitura do código, escrita em `docs/validation.md`.
  - Roteiro manual por linha do spec, auditoria de VoiceOver e teclado, medições do NFR-001.
  - Teste de contrato contra `npm run dev` local, com usuário de teste e sem
    credencial real.
  - Os problemas encontrados viram tarefas `T5xx` para o dono da feature.
- [ ] **T503** Correções do T502 (agentes por feature) + gate.

## Onda 6: distribuição (Orq.)

- [ ] **T601** `Scripts/sign.sh`: criar e usar o certificado autoassinado estável
  (o certificado e a chave ficam no Keychain do Victor, nunca no repositório).
- [ ] **T602** `Scripts/build-app.sh` (Release, arm64) e `Scripts/release.sh <versão>`:
  zip com `ditto`, sha256, `gh release` no fork com a tag `macos-v<versão>` e
  atualização do cask.
- [ ] **T603** Criar `NovaisVictor/homebrew-tap` com `Casks/daily-web.rb` (aprovado em 2026-11-04).
  Repositório criado vazio e público em 2026-11-04 (https://github.com/NovaisVictor/homebrew-tap). Falta o cask. O tap é genérico e pode receber casks e formulas de outros projetos.
- [ ] **T604** `macos/README.md` completo: instalar pelo brew, confiar no tap,
  "Abrir mesmo assim", primeiro login, build local.
- [ ] **T605** Instalação limpa numa conta de usuário nova do macOS (SC-004),
  registrada em `validation.md`.
- [ ] **T606** Revisão final do diff completo + PR do fork para `joaosouzacoder/daily-web:main`
  (título e descrição em inglês, sem labels nem assignee, conforme o fluxo do fork).

## Verificação SC-003

Rodar no fim de cada onda, na raiz do repositório:

```sh
git diff --stat main -- . ':!macos'   # só deploy/publish.sh e, se aprovado, app/globals.css
npm test && npx tsc --noEmit && npm run build
# comparar o hash do CSS de .next/static/css com a base do T008
```

## Mapa de paralelismo

```
Onda 0  Orq. ───────────────────────────────▶ gate
Onda 1  T101 ┐
        T102 ├─ paralelos ──────────────────▶ gate
        T103 │
        T104 ┘
Onda 2  T201 (Orq.) ─▶ T202 ────────────────▶ gate + revisão
Onda 3  T301 T302 T303 T304 T305 (paralelos) ▶ gate
Onda 4  T401 T402 T403 T404 (paralelos) ────▶ gate + revisão
Onda 5  T501 T502 (paralelos) ─▶ T503 ──────▶ gate
Onda 6  Orq. ───────────────────────────────▶ revisão final + PR
```

O máximo é de 5 agentes simultâneos (Onda 3). As features ficam em dois lotes
para limitar o custo e para que o lote B reaproveite padrões já revisados no lote A.
