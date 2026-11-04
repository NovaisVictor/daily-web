# Auditoria de paridade e qualidade (T502)

Data: 2026-11-04. Base: commit `6fa7aa1` mais as mudanças ainda não commitadas da T501
(`App/`, `FeatureShell`, `FeatureSettings/SettingsScreen.swift`), que estavam na árvore
durante a auditoria. O build Release medido inclui esse trabalho em andamento.

Auditoria só de leitura do código. Caminhos Swift relativos a
`macos/Packages/DailyKit/Sources/`, salvo os que começam com `App/`.

Legenda: **feito**, **divergente** (com o motivo e onde ele está registrado),
**faltando**. Lacunas numeradas `G-n`, achados de acessibilidade `A-n`, regras de erro `R-n`.

## 1. Matriz de paridade

### Sessão

| Ação do web | Status | Onde |
|---|---|---|
| Entrar com usuário e senha (Enter envia, "Entrando", erro anunciado) | feito | `FeatureShell/LoginView.swift:99-105`, `:132-145` |
| Trocar de servidor | feito (no login; com sessão aberta, só depois de Sair) | `LoginView.swift:76` |
| Sair (menu da conta e paleta) | feito | `FeatureShell/ShellAccount.swift:57`, `ShellCommands.swift:51` |
| Voltar ao login em 401 | feito | `DailyCore/Session/SessionStore.swift:79`, `:107`; `SessionAwareClient.swift:19` |
| Sessão de 30 dias, restaurar ao abrir | feito (Keychain + `restore`); verificado ao vivo: o Release abriu já logado | `SessionStore.swift:60-83` |

### Hoje (início)

| Ação do web | Status | Onde |
|---|---|---|
| Saudação "Olá, nome" | feito | `FeatureHome/HomeScreen.swift:85-96` |
| "Bem-vindo" vs. "Bem-vindo de volta" | divergente: sempre "de volta"; o `/api/me` não informa (validation.md, Onda 3) | `FeatureHome/HomeStore.swift:27` |
| Relógio com segundos e data | feito | `HomeScreen.swift:99-115` |
| Pomodoro iniciar/pausar, zerar, fase e contagem | feito; rótulos "iniciar foco"/"zerar pomodoro" conferidos no app rodando | `HomeScreen.swift:127-164` |
| Painéis do grid / abas / "Restaurar abas" | divergente: cartões de resumo; grid fora de escopo (spec.md) | `HomeScreen.swift:49`, `:172` |
| "Conectar minhas contas" sem módulos ligados | divergente sem motivo: abre Configurações na aba Aparência → **G-2** | `HomeScreen.swift:258` |

### Tarefas

| Ação do web | Status | Onde |
|---|---|---|
| Alternar Lista/Quadro (grava em preferências) | feito | `FeatureTasks/TasksScreen.swift:71-81`, `TasksStore.swift:154` |
| Criar pelo formulário (⌘N) e criar rápido na coluna | feito | `TasksScreen.swift:82-90`, `TaskBoardView.swift:246-275` |
| Editar título, prioridade, repetição, cor | feito | `TaskFormSheet.swift:42-118` |
| Atalhos de data (Hoje/Amanhã/Próx. semana/Sem data) | feito | `TaskFormSheet.swift:56-62` |
| Data em linguagem natural | divergente sem motivo: campo sempre visível, sem a prévia ao vivo "→ …" → **G-7** | `TaskFormSheet.swift:63-68` |
| Seletores nativos de Dia e Hora | faltando → **G-7** | `TaskDraft.swift:31` |
| "Descartar as alterações?" ao fechar | feito | `TaskFormSheet.swift:166` |
| Apagar com confirmação | feito | `TaskFormSheet.swift:130`, `TasksScreen.swift:155-163` |
| Concluir (recorrente sem otimismo) | feito | `TaskListView.swift:67-73`, `TasksStore.swift:165-172` |
| Subtarefas: expandir, adicionar, concluir, apagar | feito (renomear é extra do app) | `SubtaskListView.swift:33-109` |
| Menu "…" (editar, subtarefa, foco, cor, mover, apagar) | feito, também no menu de contexto | `TaskActionsMenu.swift:32-98` |
| Cor de papel, alfinete, formato | feito | `TaskActionsMenu.swift:83-160` |
| Mover entre colunas (arrastar, ←/→, ⌘←/⌘→) | feito | `TaskBoardView.swift:70`, `:146-191` |
| "Mostrar todas (N)" em Concluídas | feito | `TaskBoardView.swift:53` |
| Abas de coluna do quadro estreito | faltando, sem motivo (pouco relevante no Mac) → **G-8** | `TaskBoardView.swift:21` |
| Busca, filtros Alta/Baixa/Concluídas/período, limpar | feito | `TasksScreen.swift:97-104`, `TaskBits.swift:89-106` |
| Agendar foco (ícone e arraste para a agenda) | feito | `TaskListView.swift:96-117`, `TaskBoardView.swift:190` |
| Anúncios ao VoiceOver (aria-live) | feito | `TasksStore.swift:54` |

### Notas

| Ação do web | Status | Onde |
|---|---|---|
| Criar nota e pasta | feito | `FeatureNotes/NotesScreen.swift:103-106`, `NotesStore.swift:271` |
| Criar subpasta | feito, só no menu de contexto → **A-1** | `NoteTreeView.swift:202` |
| Renomear (clique duplo, Return, menu) | feito | `NoteTreeView.swift:29-32`, `:182`, `:331-337` |
| Mover (arrastar e menu "Mover para") | feito; o menu só existe como menu de contexto → **A-1** | `NoteTreeView.swift:79-106`, `:184-216` |
| Reordenar | feito (extra: o web não tem UI) | `NoteTreeView.swift:101-106`, `:194-197` |
| Apagar nota/pasta com confirmação | feito; só alcançável pelo menu de contexto → **A-1** | `NotesScreen.swift:248-266` |
| Botão "…" (`ações de X` / `ações da pasta X`) | faltando, sem motivo → **G-3** | `NoteTreeView.swift:27` |
| Expandir/recolher (botão e ←/→), escopos | feito | `NoteTreeView.swift:42-43`, `:129-139`, `:224-231` |
| Editor com autosave | feito | `NotesScreen.swift:195-201`, `NotesStore.swift:195` |
| ⌘B, ⌘I, ⌘E, ⌘K, ⌘⇧X; continuar lista no Enter | feito (Ctrl → ⌘, comentado em `MarkdownEditing.swift:66-70`); conflito do ⌘K com a paleta não verificado → **G-11** | `NoteEditor.swift:106-125` |
| Barra de formatação, mostrar/esconder lista, Visualizar/Editar | feito | `NotesScreen.swift:152-193` |
| Maximizar/Restaurar e "Criar em: …" | faltando, sem motivo → **G-4** | — |
| Busca, "Só nesta pasta", abrir resultado | feito | `NotesScreen.swift:117-129` |
| Status salvo/salvando · Drive | feito | `NotesScreen.swift:232-242` |

### E-mail

| Ação do web | Status | Onde |
|---|---|---|
| Árvore de pastas, recolher conta, "tentar de novo" | feito | `FeatureEmail/EmailFolderTree.swift:28-106` |
| Marcar pasta como lida | feito; botão invisível com foco → **A-3** | `EmailFolderTree.swift:142-164` |
| Soltar e-mails em pasta (inclusive de outra conta) | feito | `EmailFolderTree.swift:169` |
| Busca, "Não lidos", chips por caixa, ordenar, agrupar, limpar | feito | `EmailScreen.swift:83-124` |
| ↑↓, ⇧↑↓, Espaço, ⌘A, E, M, Esc | feito | `EmailConversationList.swift:55-93`; seletor do M em `EmailScreen.swift:241-281` |
| Checkbox, ⇧/⌘ clique, selecionar grupo | feito | `EmailConversationList.swift:110-198` |
| Lote (lido, não lido, mover, excluir) e menu de contexto | feito | `EmailScreen.swift:208-233`, `EmailConversationList.swift:318-353` |
| Arrastar para alvos (lido/não lido/excluir) | feito, alvos também clicáveis | `EmailFolderTree.swift:206-298` |
| Etiquetas | feito | `EmailConversationList.swift:358-422` |
| Criar nota/tarefa a partir do e-mail | feito | `EmailConversationList.swift:427-456`, `EmailStore.swift:804-812` |
| Abrir conversa, expandir fio, histórico citado | feito | `EmailConversationList.swift:197`, `:274`; `EmailDetailView.swift:28` |
| Rascunho por IA e enviar resposta | feito | `EmailDetailView.swift:111-116` |
| Corpo em HTML | divergente: o servidor manda só texto (validation.md, Onda 3) | — |
| "Abrir em tela cheia"/"Restaurar" | faltando, sem motivo registrado → **G-5** | `EmailScreen.swift:7` |
| Esc fecha o e-mail aberto em qualquer foco | divergente sem motivo: só com a lista em foco → **G-6** | `EmailConversationList.swift:71` |

### Agenda

| Ação do web | Status | Onde |
|---|---|---|
| Período hoje a 14 dias (grava) | feito | `FeatureAgenda/AgendaScreen.swift:32-38` |
| Eventos por dia, "dia", conta | feito | `AgendaScreen.swift:59-126` |
| Soltar item para bloco de foco + formulário | feito | `AgendaScreen.swift:27-30`, `FocusBlockSheet.swift:16-41`, `DailyDesign/FocusBlockForm.swift:106-153` |
| "Reconectar <conta>" sem agenda gravável | feito | `FocusBlockSheet.swift:24-40` |

### Jira

| Ação do web | Status | Onde |
|---|---|---|
| Abas, período, busca | feito | `FeatureJira/JiraScreen.swift:51-123` |
| Filtros (papel, exibição, status, tipo, hierarquia, = / ≠, busca de opção) e ordenação | feito; rótulo do modo difere → **A-5** | `JiraFilterPopover.swift:29-195`, `JiraScreen.swift:124-137` |
| Remover filtro / limpar tudo | feito | `JiraBits.swift:173-188` |
| Pessoas: trocar, acompanhar, deixar | feito | `JiraPeopleViews.swift:12-72` |
| Acompanhar/deixar issue | feito | `JiraScreen.swift:248-260`, `JiraRows.swift:338` |
| Árvore, abrir no Jira, abrir PRs | feito | `JiraRows.swift:68`, `:171`; `JiraBits.swift:101-129` |
| Transição, comentário, impedimento, prazo, prioridade, atribuir, história, aprovar/recusar | feito | `TransitionPicker.swift:25-99`, `IssueDialogs.swift:96-593`, `JiraRows.swift:46-215` |
| Agendar foco (botão e arraste) | feito | `JiraRows.swift:141-155` |
| Problemas (data de início, épico) e data de início em lote | feito | `ProblemFixViews.swift:80-151`, `BulkStartDate.swift:85-213` |
| Resumo da daily | feito | `JiraScreen.swift:95`, `StandupSheet.swift:27-53` |

### Pull requests

| Ação do web | Status | Onde |
|---|---|---|
| Abas, busca, filtros repo/autor/estado (incluir/excluir), limpar | feito | `FeaturePulls/PullsScreen.swift:31`, `PullFiltersView.swift:13-167` |
| Aprovar, pedir mudanças, comentar, pedir revisão | feito | `PullsStore.swift:315-344`, `PullActionSheet.swift:152-167` |
| Merge com método, rerun dos checks que falharam | feito | `PullsStore.swift:355-364`, `PullActionSheet.swift:186-220` |
| Sincronizar Jira | feito | `PullRowView.swift:290-342`, `PullsStore.swift:389-404` |
| Alerta de CI vermelho na branch padrão | feito | `PullsScreen.swift:219-231` |
| Repositórios e autores (adicionar/remover) | feito | `TrackedReposView.swift:18-105` |
| Agendar foco, abrir PR/repo/Jira | feito | `PullRowView.swift:52-139` |

### Slack

| Ação do web | Status | Onde |
|---|---|---|
| Menções e DMs | feito | `FeatureSlack/SlackScreen.swift:28` |
| Abrir no Slack (Return, duplo clique, menu) | feito ("Copiar link" é extra) | `SlackScreen.swift:75-79` |

### Agentes

| Ação do web | Status | Onde |
|---|---|---|
| Kanban, abas Tarefas/Sessões, busca (⌘F), filtros, finalizadas, paginação | feito | `FeatureAgents/AgentsScreen.swift:66-190`, `AgentBoardViews.swift:264-410` |
| "N aguardando você" leva à primeira tarefa | divergente sem motivo: rola mas não move o foco → **A-4** | `AgentsScreen.swift:96` |
| Avisos (PushToggle) | divergente: Web Push fora de escopo (spec.md) | — |
| Detalhe: transições, aguardar/bloquear com motivo, editar, excluir, paginar | feito | `AgentTaskDetailView.swift:140-426`, `AgentsLogic.swift:85` |
| Terminal ao vivo, Última resposta, responder com ⌘↩ | feito | `AgentLivePanel.swift:59-142` |

### Acesso dos agentes

| Ação do web | Status | Onde |
|---|---|---|
| Criar token com escopo, copiar uma vez | feito | `FeatureAccess/AccessScreen.swift:80-93`, `:338-348` |
| Revogar token e concessão OAuth | feito | `AccessScreen.swift:183-197`, `:291-303` |
| Copiar prompt e URL do MCP | feito | `AccessScreen.swift:130`, `:244` |
| Consentimento OAuth (`/access/consent`) | divergente: só no navegador (research.md) | — |

### Notificações

| Ação do web | Status | Onde |
|---|---|---|
| Central, filtro por fonte (inclui Slack, motivo no código) | feito | `FeatureNotifications/NotificationsBell.swift:24-88`, `NotificationsLogic.swift:6-7` |
| Marcar todas / uma como lida | feito | `NotificationsBell.swift:139`, `:220` |
| Responder menção do Jira (⌘↩) | feito | `NotificationsBell.swift:213`, `:275-305` |
| "Avisar no computador" e aviso de permissão negada | feito | `NotificationsBell.swift:115-123` |
| Avisos: novo e-mail, aprovação pendente, issue nova/com problema, PR novo, revisão pedida, agenda, Slack, "Em N min", resumo, pomodoro | feito | `DailyCore/Alerts/AlertRules.swift:158-313`, `AlertEngine.swift:92` |
| Aviso de tarefa de agente aguardando você | divergente sem motivo: título "Aguardando você" (web: "Pedindo permissão: X" / "Aguardando sua resposta: X", `lib/push/dispatch.ts:53-54`) e só dispara com a tela de agentes em polling → **G-9** | `AlertRules.swift:235`, `FeatureAgents/AgentsStore.swift:116-129` |
| Clique no aviso abre o item | feito | `App/AppDelegate.swift` (`handle(action:userInfo:)`) |

### Configurações

| Ação do web | Status | Onde |
|---|---|---|
| Tema, densidade, fundo, limitar largura | feito (dica vira subtítulo do Toggle, aceitável) | `FeatureSettings/AppearanceSettingsView.swift:26-57` |
| LayoutPanel | divergente: grid fora de escopo | `SettingsScreen.swift:12-13` |
| Integrações: conectar/gerenciar, formulário, editar, remover, testar, agendas, iCal, navegador (Google/Slack), recarregar ao voltar | feito | `IntegrationsSettingsView.swift:31-127`, `ModuleDetailsSheet.swift:37-238`, `IntegrationForm.swift:109-118` |
| Mensagem conectado/erro depois do OAuth | divergente: o app só recarrega (comentário em `IntegrationsSettingsView.swift:29-30`) | — |
| Ligar/desligar por módulo | divergente: o web removeu (validation.md, Onda 3) | — |
| Perfil: foto (pôr/remover), nome e e-mail, senha | feito | `ProfileSettingsView.swift:27-87` |
| Usuários: criar, trocar senha, remover, "Só admins…" | feito | `UsersSettingsView.swift:26-103` |

### Shell

| Ação do web | Status | Onde |
|---|---|---|
| Barra lateral (+ ⌘1…⌘9) | feito | `FeatureShell/ShellRootView.swift:47-58`, `ShellKeyboardShortcuts.swift` |
| Paleta ⌘K: Ir para, Tema, Densidade, Fundo, Conta; ↑↓/Enter/Esc | feito | `ShellCommands.swift:19-52`, `CommandPalette.swift:140-150` |
| "Atualizar agora" (⌘R) | feito | `ShellRootView.swift` (`RefreshButton`) |
| Menu da conta: Perfil, Conectar agente, Configurações, Sair | feito | `ShellAccount.swift:52-57` |
| Perfil / Trocar senha / Alterar foto abrem a aba certa | divergente sem motivo: todas abrem a aba Aparência → **G-2** | `App/MainWindow.swift` (`accountActions`, `paletteCommands`: `openSettings()` sem destino) |
| "Novidades" (menu e diálogo após atualização) | faltando → **G-1** | — |
| Toasts e confirmações | feito | `App/RootView.swift`, `DailyDesign/Overlays.swift:41` |
| FR-010: barra de menus, atalho global, janela por módulo | em andamento na T501 (`App/MenuBarContent.swift`, `App/ModuleWindow.swift`, `FeatureShell/GlobalShortcut.swift`, ainda não commitados) → **G-12** | — |

### Lacunas da matriz

| Id | Lacuna | Dono |
|---|---|---|
| G-1 | "Novidades" ausente (item do menu da conta e diálogo depois de atualizar) | FeatureShell |
| G-2 | Perfil, Trocar senha, Alterar foto e "Conectar minhas contas" abrem Configurações sempre na Aparência; precisa de destino por aba | App (Orq./T501) + FeatureSettings + FeatureHome |
| G-3 | Notas sem botão "…" de ações por nota/pasta (`ações de X`) | FeatureNotes |
| G-4 | Notas sem Maximizar/Restaurar nem "Criar em: …" (ou registrar divergência: janela nativa) | FeatureNotes |
| G-5 | E-mail sem "Abrir em tela cheia" (registrar divergência, ou abrir em janela própria via FR-010) | FeatureEmail |
| G-6 | Esc só fecha o e-mail com a lista em foco | FeatureEmail |
| G-7 | Formulário de tarefa sem prévia ao vivo da data em linguagem natural e sem seletores Dia/Hora | FeatureTasks |
| G-8 | Quadro estreito sem abas de coluna (registrar divergência) | FeatureTasks |
| G-9 | Aviso de agente aguardando: título diferente do web e só dispara com a tela de agentes aberta (FR-006) | FeatureAgents + DailyCore |
| G-10 | Divergências "sem motivo registrado" acima (G-4, G-5, G-6, G-8, A-4, aviso de e-mail que abre no app) precisam de nota em `validation.md` | cada dono |
| G-11 | Conferir se ⌘K no editor de notas (link) perde para o ⌘K da paleta | FeatureNotes + FeatureShell |
| G-12 | FR-010 (barra de menus, atalho global, janelas por módulo) só existe como trabalho não commitado da T501 | T501 |
| G-13 | `.app` Release de 32 MB, acima do limite de 25 MB, porque não sai sem símbolos (ver seção 4) | Orq. (T602) |
| G-14 | Ao ocultar o app com `visible = false`, ele voltou a ficar visível sozinho uns 40–50 s depois, duas vezes; numa delas ficou sem janela nenhuma (ver seção 4) | App (T501) |
| G-15 | Dependências transitivas fora da tabela do `plan.md`: `swiftui-math` (via Textual, 7,1 MB de fontes matemáticas no bundle) e `swift-concurrency-extras` | Orq. |

## 2. Acessibilidade e teclado (estático)

Varredura de `Button` só com ícone, `Image` com significado sem `accessibilityLabel`,
e ações que só funcionam com mouse, em todos os `Feature*`, `DailyDesign` e `App`.

**Botões só com ícone sem rótulo: nenhum.** Todos têm `accessibilityLabel` igual
ao `aria-label` do web, ou usam `Label(...)` com `.labelStyle(.iconOnly)`, que
carrega o texto. As imagens decorativas usam `accessibilityHidden`. Exemplos
conferidos: `DailyDesign/Overlays.swift:198-204` ("Fechar"),
`FeatureShell/ShellRootView.swift` (`RefreshButton`: "Atualizar agora"),
`PullRowView.swift:59`, `JiraRows.swift:34-344`, `NotificationsBell.swift:45-227`.
No app rodando, os botões do Hoje expõem "iniciar foco", "zerar pomodoro",
"abrir Tarefas" e "abrir Notas rápidas" ao VoiceOver.

| Id | Achado | Arquivo | Prioridade |
|---|---|---|---|
| A-1 | Mover, Mover para cima/baixo, Nova subpasta, Apagar nota e Apagar pasta só existem no `contextMenu` da árvore de notas; sem botão "…", sem atalho, sem Delete. Inalcançável só por teclado (NFR-005) | `FeatureNotes/NoteTreeView.swift:27` (menu em `:182-216`) | P1 |
| A-2 | Renomear subtarefa só com clique duplo ou menu de contexto (há `accessibilityAction` para VoiceOver, nada para teclado). Ação extra do app | `FeatureTasks/SubtaskListView.swift:92-99` | P3 |
| A-3 | "Marcar a pasta … como lida" fica com opacidade 0 fora do hover, inclusive quando focado; o web mostra com `focus-visible:opacity-100` (`FolderTree.tsx:248`) | `FeatureEmail/EmailFolderTree.swift:146` | P2 |
| A-4 | "N aguardando você" rola até o card mas não move o foco (o web chama `card.focus()`) | `FeatureAgents/AgentsScreen.swift:96` | P3 |
| A-5 | Modo do filtro é um segmented "modo de X"; o web tem dois botões "modo é igual a para X" / "modo não é igual a para X" (`JiraMultiFilterDropdown.tsx:181`, `:192`) | `FeatureJira/JiraFilterPopover.swift:193` | P3 |
| A-6 | Rótulo "Jira · nome" sem `aria-label` equivalente no web (o web usa o texto visível) | `FeatureJira/JiraPeopleViews.swift:36` | P3 |

Arrastos com alternativa por teclado (sem achado): tarefas entre colunas
(botões e ⌘←/⌘→, `TaskBoardView.swift:146-191`), e-mail para pasta (M e barra
do lote), foco para a agenda (botão "agendar foco para …" em Tarefas, Jira e
Pulls). O kanban de agentes não tem arraste nem no web. A área de soltar da
agenda é só arraste, igual ao web. A lista de e-mail não abre a conversa com
Return, igual ao web.

## 3. Regras de erro do AGENTS.md

Varredura em `Packages/DailyKit/Sources` e `App` por `try?`, `catch` vazio,
`try!`, `as!`, desembrulho forçado (`x!`), `@unchecked Sendable`,
`nonisolated(unsafe)` e `print(`.

Sem ocorrência: `catch {}` vazio, `try!`, `as!`, `nonisolated(unsafe)`, `print(`.
Desembrulho forçado: nenhum encontrado pela expressão
`[A-Za-z0-9_)\]]![^=]` fora de comentários e strings.

| Id | Ocorrência | Justificada? |
|---|---|---|
| R-1 | `try?` em `DailyAPI/ServerErrorBody.swift:21` | sim: comentário em `:22-23`; só sonda o formato, o caminho alternativo lança |
| R-2 | `try?` em `FeatureSlack/SlackLogic.swift:75` e `:78` | sim: comentário em `:72-73`; data ilegível é valor esperado (o web mostra "—") |
| R-3 | `try? await Task.sleep(for: .seconds(5))` em `App/AppDelegate.swift:44` | sim no mérito (é o lado do tempo-limite da corrida; o cancelamento é esperado), mas o `try?` não tem comentário próprio; o comentário em `:38-40` explica só o limite. Sugestão: comentar |
| R-4 | `@unchecked Sendable` em `DailyStorage/UserDefaultsServerSettings.swift:10` | sim: comentário em `:5-6` (`UserDefaults` é thread-safe e a referência é imutável) |
| R-5 | `catch` que devolve "Erro N do servidor" sem registrar o erro de decodificação, em `DailyAPI/HTTPAPIClient.swift:228` | sim por comentário (`:229`), mas o detalhe se perde; sugestão: `Logger.debug` com o erro |
| R-6 | `catch` de cancelamento do `sleep`, sem log: `AgentsStore.swift:167`, `PomodoroController.swift:144`, `ToastCenter.swift:64`, `NotesStore.swift:184` e `:483`, `JiraPeopleViews.swift:86` | sim: cada um comentado (cancelado pela próxima tecla ou pelo encerramento) |
| R-7 | `catch` que registra e segue: `EmailStore.swift:256`, `NotesStore.swift:502` (nível `debug`), `AlertEngine.swift:127` e `:138`, `CacheWriter.swift:70` | sim: comentados e com `Logger` |

## 4. Desempenho (NFR-001)

Build: `xcodebuild -project DailyWeb.xcodeproj -scheme DailyWeb -configuration Release
-destination 'platform=macOS,arch=arm64' -derivedDataPath .build/agents/audit-xcode build`
→ `BUILD SUCCEEDED`, sem warnings de compilação. Inclui o trabalho não commitado da T501.

**Tamanho do `.app`: 32 MB (`du -sh`) — acima do limite de 25 MB.**

| Parte | Tamanho |
|---|---|
| `Contents/MacOS/DailyWeb` (arm64) | 24 MB, com `__LINKEDIT` de 17 MB: o `build` roda com `DEPLOYMENT_POSTPROCESSING = NO`, então `STRIP_INSTALLED_PRODUCT = YES` não tem efeito |
| `swiftui-math_SwiftUIMath.bundle` | 7,1 MB (fontes matemáticas, dependência transitiva do Textual) |
| Demais recursos | < 0,3 MB |

Numa cópia, `strip` reduz o binário para 8,8 MB, o que daria cerca de 16–17 MB
de `.app`. A T602 (`Scripts/build-app.sh`) precisa gerar o binário sem símbolos
(`archive`, ou `DEPLOYMENT_POSTPROCESSING=YES`) e medir de novo (G-13).

**Execução** (Release, sessão já salva no Keychain, servidor local com só
Tarefas e Notas ligados, então quase nenhum dado):

| Medição | Resultado | Limite |
|---|---|---|
| RSS com a janela no Hoje, 2–4 min após abrir | 106–129 MB | — |
| RSS com a janela no Hoje, 13 min após abrir | 119,5 MB | < 150 MB: **atende** |
| Physical footprint (vmmap) ao fim | 65–77 MB; pico de 159,5 MB (durante as consultas de acessibilidade por AppleScript) | — |
| CPU com a janela visível no Hoje, sem consultas de acessibilidade | 1,9% (1,17 s em 61 s) | sem limite no NFR |
| CPU visível, 13 min, depois de vários clientes de acessibilidade terem se conectado | 4,1% (2,84 s em 70 s) | sem limite no NFR |
| CPU oculto (`visible = false` confirmado, RSS caiu para 47–51 MB) | 0,17% (0,05 s em ~30 s) | < 1%: **atende na janela curta** |

Observações:

- O relógio com segundos e o pomodoro atualizam a tela a cada 1 s; é a
  provável origem do ~2% com a janela visível.
- A medição em segundo plano foi curta, porque o app voltou a ficar visível
  sozinho cerca de 40–50 s depois de ocultado, duas vezes seguidas; numa delas
  ficou visível sem janela nenhuma (G-14). Uma segunda tentativa com
  `NSRunningApplication.hide` não chegou a ocultar o app. Antes de fechar o NFR,
  repetir 10 min oculto, sem consultas de acessibilidade.
- Instância encerrada com `kill -TERM` ao fim.

## 5. Contrato ao vivo (GETs)

Servidor `http://localhost:8010`, usuário `macos-dev`. Login por `curl`, com o
cookie num arquivo temporário do scratchpad, apagado ao fim. Nenhum dado criado.
Cada resposta foi decodificada com os tipos do `DailyModels` (as fontes do target
compiladas com `swiftc -swift-version 6` e as mesmas features do `Package.swift`,
num executável descartável, com `JSONDecoder()` padrão como o `HTTPAPIClient`).
Depois, cada valor foi recodificado e as chaves comparadas com o JSON original.

| Endpoint | HTTP | Tipo | Resultado |
|---|---|---|---|
| `GET /api/me` | 200 | `CurrentUser` | decodifica |
| `GET /api/state` | 200 | `DashboardState` | decodifica |
| `GET /api/notes` | 200 | `NotesResponse` | decodifica |
| `GET /api/notes/folders` | 200 | `NoteFoldersResponse` | decodifica |
| `GET /api/notes/sync` | 200 | `NotesSyncResponse` | decodifica |
| `GET /api/integrations` | 200 | `IntegrationsPayload` | decodifica (7 módulos no catálogo) |
| `GET /api/users` | 200 | `UsersResponse` | decodifica |
| `GET /api/agents?days=7&scope=roots&sort=newest&limit=100` | 200 | `AgentsBoard` | decodifica |
| `GET /api/agent-access/tokens` | 200 | `APICredentialsResponse` | decodifica |
| `GET /api/agent-access/prompt` | 200 | `AgentAccessPrompt` | decodifica |
| `GET /api/agent-access/config` | 200 | `AgentAccessConfig` | decodifica |
| `GET /api/agent-access/grants` | 200 | `OAuthGrantsResponse` | decodifica |
| `GET /api/pulls/repos` | 200 (não deu 409) | `PullReposResponse` | decodifica |
| `GET /api/preferences/layout-default` | 200 | — | sem tipo no app: o grid está fora de escopo |
| `GET /api/push` | 200 | — | sem tipo no app: Web Push fora de escopo |

**13 de 13 decodificam; nenhuma falha.** A recodificação não perdeu nenhuma chave
com valor: as únicas diferenças são chaves `null` omitidas (`avatarUrl`,
`fullName`, `email`, `nextCursor`, `lastError`, `lastSyncedAt`).

Limite da verificação: o banco local está quase vazio. Notas, pastas, tokens,
concessões, tarefas de agentes e repositórios vieram como listas vazias, então os
tipos dos elementos dessas listas não foram exercitados contra o servidor real
(os fixtures da T101 cobrem esses formatos).

## Lacunas priorizadas

**P1: corrigir antes do release**

1. A-1 / G-3: ações de nota e pasta só no menu de contexto. Adicionar o botão "…" (`ações de X`, `ações da pasta X`) com as mesmas ações, alcançável por Tab (FeatureNotes).
2. G-13: `.app` com 32 MB. Gerar o binário sem símbolos na T602 e medir de novo, com meta < 25 MB (Orq.).
3. G-12: FR-010 (barra de menus, atalho global, janela por módulo) precisa estar entregue e commitado pela T501.
4. G-2: Perfil, Trocar senha, Alterar foto e "Conectar minhas contas" precisam abrir a aba certa das Configurações (App + FeatureSettings + FeatureHome).

**P2: deveria corrigir**

5. G-9: aviso de agente aguardando com o título do web e disparado também fora da tela de agentes (FR-006).
6. G-14: investigar por que o app oculto volta a ficar visível; depois repetir a medição de CPU oculto por 10 min (SC-005).
7. A-3: botão "Marcar a pasta como lida" visível quando focado.
8. G-7: prévia ao vivo da data em linguagem natural no formulário de tarefa (e decidir sobre os seletores Dia/Hora).
9. G-1: "Novidades".
10. G-11: conferir o conflito de ⌘K entre o editor de notas e a paleta.

**P3: desejável**

11. G-10: registrar em `validation.md` as divergências sem motivo (G-4, G-5, G-6, G-8, A-4, aviso de e-mail que abre no app).
12. G-4, G-5, G-6, G-8: maximizar nota, tela cheia do e-mail, Esc global no e-mail, abas de coluna; ou registrar como divergência.
13. A-2, A-4, A-5, A-6: teclado na renomeação de subtarefa, foco no "aguardando você", rótulos do filtro do Jira.
14. R-3, R-5: comentar o `try?` do tempo-limite e registrar o erro de decodificação do corpo de erro.
15. G-15: listar `swiftui-math` e `swift-concurrency-extras` no `plan.md § Dependências`, ou avaliar o custo de 7,1 MB de fontes.
