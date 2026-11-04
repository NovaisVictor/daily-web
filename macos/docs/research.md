# Pesquisa: Daily Web para macOS

Levantamento de 2026-11-04. Cada decisão registra a alternativa rejeitada e o motivo.

## Decisões

| # | Decisão | Alternativa rejeitada | Por quê |
|---|---|---|---|
| D1 | Cliente nativo completo (SwiftUI) | Barra de menus só com resumo; `WKWebView` envolvendo o web | Escolha do Victor: paridade nativa com o web |
| D2 | Código em `macos/` dentro do repositório do web | Repositório separado | Escolha do Victor. O web não pode ser afetado (veja D9) |
| D3 | Início com barra lateral nativa (`NavigationSplitView`) | Reproduzir o grid de 12 colunas e as abas do Trellis | Padrão do Mac, mais leve, sem a parte mais cara de portar |
| D4 | Sessão por cookie (`/api/login`) com o token no Keychain e o `Cookie` enviado à mão | OAuth/OIDC com PKCE | Os escopos OAuth não cobrem e-mail, notas, pomodoro, preferências e usuários, e o Bearer só vale em `/mcp`. O cookie é `secure`, então o `HTTPCookieStorage` não o enviaria em `http://localhost` |
| D5 | Polling (20 s, ou 60 s em segundo plano) e notificações locais | SSE ou Web Push | O servidor não tem SSE nem WebSocket, e a API de push só aceita endpoints de navegador. Mudar o servidor está fora de escopo |
| D6 | Padrão MV com `@Observable` e pacote SPM com um target por feature (modelo: IceCubesApp) | TCA; MVVM com view models por tela | Menos cerimônia por feature, alinhado ao que a Apple recomenda hoje, e os targets mapeiam um para um nos sub-agentes |
| D7 | `.xcodeproj` mínimo com pasta sincronizada + SPM local | SwiftPM puro (montar o `.app` por script); XcodeGen/Tuist | Com pastas sincronizadas, adicionar arquivo não altera o `project.pbxproj`, e o código fica todo no SPM. Mantém asset catalog, entitlements e Info.plist sem script |
| D8 | Cask sem notarização em `NovaisVictor/homebrew-tap`, assinado com certificado próprio estável | Developer ID (US$ 99/ano); formula que compila do código-fonte | Escolha do Victor: sem custo. O certificado estável evita pedir acesso ao Keychain a cada versão |
| D9 | Só duas linhas fora de `macos/`: o `--exclude 'macos/'` no `deploy/publish.sh` (aprovado) e o `@source not "../macos"` no `app/globals.css` (pendente) | Nenhuma mudança fora de `macos/` | O rsync levaria o código Swift para produção, e o Tailwind v4 varre todo arquivo não ignorado em busca de classes |
| D10 | Documentação em `macos/docs/` | `specs/002-…` | Escolha do Victor: tudo do app dentro de `macos/` |
| D11 | macOS 26+ | macOS 15+ | O ambiente é 26.4. O `WebView` nativo do SwiftUI (para o corpo do e-mail) só existe no 26. Suposição: se o público incluir Macs mais antigos, revisar |
| D12 | Release por script local (`release.sh`) | Workflow do GitHub Actions | Um workflow no `.github/` iria para o repositório do João e mexeria no CI dele |

## Repositórios de referência

| Repositório | Licença | O que aproveitar |
|---|---|---|
| [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp) | AGPL-3.0, só ideias | **Padrão de arquitetura**: stores `@Observable` no `Environment`, pacotes por feature, cliente tipado com `Endpoint` por domínio, Swift 6 com isolamento padrão `MainActor`. Roda no Mac via Catalyst, mas aqui o alvo é macOS nativo |
| [steipete/RepoBar](https://github.com/steipete/RepoBar) | MIT | App macOS-first de cliente de rede: abre do cache e atualiza em segundo plano, Keychain, cask |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | MIT | Scripts de assinatura e release e atualização do tap |
| [Ranchero-Software/NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire) | MIT | Rigor do compilador (warnings como erro) e configuração por `xcconfig` |

Descartados: CodeEdit e Ice (Swift 5, sem rede), isowords (TCA, iOS) e Whisky (arquivado).

## Stack

| Área | Escolha | Observação |
|---|---|---|
| Concorrência | Swift 6, `defaultIsolation(MainActor)` nos targets de UI; `Models`/`API` `Sendable` e não isolados | "Approachable Concurrency", padrão dos projetos novos do Xcode 26 |
| Rede | `URLSession` async/await | Sem Alamofire. OpenAPI generator só se o servidor publicasse uma spec, o que não acontece |
| JSON | `JSONDecoder` único; datas como `String` ISO no modelo, convertidas na borda | O servidor mistura `AAAA-MM-DD`, ISO completo e `""`. Decodificar como `Date` quebraria com `""` |
| Keychain | Wrapper próprio de `Security.framework` (~60 linhas) | KeychainAccess está parado desde 2021 |
| Markdown | Textual 0.5.0 (versão exata) | O swift-markdown-ui está em modo manutenção; o sucessor é o Textual |
| HTML de e-mail | `WebView`/`WebPage` do SwiftUI, sem JS, armazenamento não persistente, regra que bloqueia carga remota | Botão "carregar conteúdo remoto" para não deixar o remetente rastrear a abertura |
| Cache | Arquivo JSON do último `DashboardState` | GRDB só se aparecer busca offline |
| Avisos | `UNUserNotificationCenter`, notificações locais | Sem APNs |
| Barra de menus | `MenuBarExtra` com estilo `.window` | — |
| Atalho global | KeyboardShortcuts 3.1.0 | Inclui gravador de atalho em SwiftUI |
| Abrir ao iniciar | `SMAppService.mainApp` | Nativo, sem dependência |
| Log | `os.Logger` por módulo, `privacy: .private` em dado pessoal | Nunca logar token |
| Testes | Swift Testing + `URLProtocol` stub | XCUITest só para poucos smoke tests |
| Formatação | `swift format` (vem no toolchain 6.3) | Nada a instalar |

## Homebrew: fatos verificados

| Quando | O que mudou |
|---|---|
| Ago/2024 (macOS 15) | Acabou o "Ctrl-clique → Abrir". Um app bloqueado só é liberado em Ajustes → Privacidade e Segurança → "Abrir mesmo assim" |
| Sempre (Apple Silicon) | Código arm64 precisa de assinatura para rodar, mas ad-hoc basta. Assinar não passa pelo Gatekeeper se o arquivo estiver em quarentena |
| 5.0.0 (12/11/2025) | `--no-quarantine` descontinuado |
| 6.0.0 (11/06/2026) | `--no-quarantine` removido, e download de cask sempre fica em quarentena. Tap de terceiros precisa ser marcado como confiável |
| Set/2026 | Casks oficiais que falham no Gatekeeper são desativados. Taps pessoais não são auditados nisso |
| 7.0.0 (13/09/2026) | `preflight`/`postflight` descontinuados em casks |

Fontes: [brew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/), [brew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/),
[brew 7.0.0](https://brew.sh/2026/09/13/homebrew-7.0.0/), [Homebrew/brew#20755](https://github.com/Homebrew/brew/issues/20755),
[Tap Trust](https://docs.brew.sh/Tap-Trust), [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks),
[Apple: Gatekeeper no Sequoia](https://developer.apple.com/news/?id=saqachfa).

Consequência para D8: cada versão nova exige "Abrir mesmo assim" uma vez. A
migração para Developer ID continua aberta. Ela só troca a identidade no
`sign.sh` e acrescenta `notarytool` e `stapler`.

## Inventário do web

Resumo dos componentes que o app espelha. As linhas exatas estão em `components/`.

- **Rotas**: `/` (NowBand + início), `/kanban`, `/agents`, `/agents/tasks/[id]`,
  `/access` (+ `/access/consent`, só no navegador), `/config`, `/perfil`, `/tools`, `/login`.
- **Navegação**: cabeçalho (Início, Kanban, Ferramentas; Ajustes: Acesso dos
  agentes, Configuração), menu do avatar (Perfil, Conectar agente, Configurações,
  Novidades, Sair) e paleta ⌘K (Ir para, Tema, Densidade, Fundo, Conta).
- **Cadências**: `/api/state` a cada 20 s, com `mutate` otimista
  (`lib/hooks/usePolling.tsx`). Agentes a cada 2 s, só com a aba visível
  (`components/agents/useAgentPolling.ts`). Sincronização de notas a cada 10 s.
  Autosave de nota em 700 ms. Lembretes a cada 30 s. Pomodoro com relógio local
  de 1 s, reancorado a cada consulta.
- **Tarefas** (`TasksPanel.tsx`, `TaskFormModal.tsx`, `components/tasks/*`):
  lista/quadro, grupos (Atrasadas, Hoje, Esta semana, Este mês, Depois, Sem
  data), formulário com data em linguagem natural ("amanhã 14:30"), prioridade e
  repetição, subtarefas, cor de papel e alfinete, mover por teclado, agendar foco.
- **Notas** (`NotesPanel.tsx`, `components/notes/*`): árvore com arrastar,
  renomear com clique duplo, editor com ⌘B/⌘I/⌘⇧X/⌘E/⌘K, pré-visualização,
  busca e status do Drive.
- **E-mail** (`EmailPanel.tsx`, `components/email/*`): pastas, filtros,
  ordenação, agrupamento, seleção com ↑↓/⇧/Espaço/⌘A, E (excluir) e M (mover),
  lote, etiquetas, corpo, rascunho por IA, resposta e criação de nota/tarefa.
- **Agenda** (`AgendaPanel.tsx`): período e área de soltar para bloco de foco.
- **Jira** (`JiraPanel.tsx`, `components/jira/*`, `JiraProblemFix.tsx`): quatro
  abas, filtros (papel, exibição, status, tipo, hierarquia), ordenação, acompanhar,
  pessoas, ações por issue, data de início em lote, resumo da daily.
- **Pulls** (`PullsPanel.tsx`, `components/pulls/*`): três abas, filtros,
  repositórios e autores, ações, sincronização com o Jira, alerta da branch padrão.
- **Slack** (`SlackPanel.tsx`): menções e DMs, só leitura.
- **Agentes** (`components/agents/*`): kanban, sessões, detalhe, ações, terminal
  ao vivo com resposta (⌘↩).
- **Acesso** (`AccessPanel.tsx`): tokens, prompt, URL do MCP, concessões.
- **Notificações** (`NotificationsBell.tsx`, `lib/desktopAlerts.ts`): central,
  filtros e avisos ("Novo e-mail", "Aprovação pendente", "Novo PR", "Revisão
  pedida", "Em N min", …).
- **Ajustes**: `AppearancePanel.tsx`, `IntegrationsPanel.tsx`, `ProfilePanel.tsx`
  e `UsersPanel.tsx` (admin).
- **Tema** (`app/globals.css`, `lib/theme.ts`): paleta oklch clara e escura,
  Catppuccin (Latte/Mocha), Dracula e WezTerm (os dois últimos só no escuro),
  raio 0.75rem, escala tipográfica de 2.75rem a 0.8125rem, Geist Sans/Mono,
  Patrick Hand nas notas do quadro, ícones lucide (no app, SF Symbols
  equivalentes).

Divergência encontrada no web (fora do escopo, só registro): o `LayoutPanel.tsx`
fala em botões "Organizar" e "Concluir" que não existem.
