# Lacunas entre o web e o app nativo

Levantamento de 2026-11-04, feito depois do primeiro uso real do app. Seis agentes
compararam, só lendo o código, cada área do web (`components/`, `app/(app)/`,
`lib/`) com o nativo (`macos/`). Cada item tem um id, o comportamento do web com
o arquivo de origem e o estado no nativo:

- **faltando**: o nativo não tem;
- **parcial**: tem, mas incompleto;
- **diferente**: existe, mas se comporta ou aparece de outro jeito.

As specs que resolvem estas lacunas estão em [specs/](specs/README.md).

**Conclusão geral.** Dentro das telas de cada módulo, a paridade de funções é
alta. A distância que o uso real mostrou está em três lugares:

1. **O Início**: grade livre, modo Abas e painéis com o módulo inteiro dentro.
2. **A navegação e as páginas**: menu em pílula no topo, Kanban e Ferramentas.
3. **A linguagem visual**: vidro sobre o gradiente, Geist, controles em pílula,
   linhas zebradas e o quadro de post-its.

**Nenhuma lacuna exige mudar o servidor**, salvo as quatro já registradas
(corpo HTML do e-mail, leitura da aparência, "Bem-vindo" e changelog).

## Início (H)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| H-1 | Grade livre de 12 colunas: arrastar e redimensionar painéis | `components/DashboardGrid.tsx:9,273-281`, `lib/dashboardLayout.ts:21-23` | faltando (duas colunas fixas, `FeatureHome/HomeScreen.swift:72-81`) |
| H-2 | Modo de organizar ao segurar o painel por 0,5 s; Esc descarta | `DashboardGrid.tsx:36-40,154-225,262-269` | faltando |
| H-3 | Barra "Arraste para mover… Salvar guarda para L × A", com "Salvar para esta tela" e "Descartar" | `DashboardGrid.tsx:359-382` | faltando |
| H-4 | Alça de redimensionar no canto inferior direito; mínimo 3×4, altura máxima 80 | `DashboardGrid.tsx:291-294`, `lib/dashboardLayout.ts:24-25,68` | faltando |
| H-5 | Disposição salva por tamanho de janela (até 20), escolhendo a mais próxima | `app/(app)/page.tsx:37-74`, `lib/dashboardLayout.ts:113-194`, `PATCH /api/preferences {layout, viewport}` | faltando (o modelo decodifica, mas ignora) |
| H-6 | Disposição padrão (e-mail e tarefas largos à esquerda; agenda, Jira e PRs à direita) | `lib/dashboardLayout.ts:34-42` | diferente (alterna colunas pela ordem) |
| H-7 | Janela estreita (< 1023 px): um módulo por vez, com barra de módulos | `DashboardGrid.tsx:296-341`, `MobileModuleNav.tsx` | diferente (empilha abaixo de 820 pt) |
| H-8 | Modo **Abas** (Trellis): grupos de abas, divisões, arrastar abas entre grupos | `components/dashboard/WorkspaceHome.tsx:98-120` | faltando |
| H-9 | Alternância Grade / Abas, salva por conta | `HomeViewSwitch.tsx:15-37`, `page.tsx:78-95`, `PATCH {homeView}` | faltando |
| H-10 | "Restaurar abas" | `page.tsx:97-122`, `WorkspaceHome.tsx:52-58` | faltando |
| H-11 | "Restaurar disposição padrão" nas configurações | `components/LayoutPanel.tsx:13-83`, `PATCH {layout:null}` | faltando |
| H-12 | Cabeçalho do painel com espaço para ações | `components/ui/Section.tsx:6-28` | parcial (só "Abrir ›") |
| H-13 | Painel do Jira com "Jira · Eu" (troca de pessoa) e resumo da daily | `JiraPanel.tsx:626-653` | faltando no Início |
| H-14 | Painel "GitHub" (não "Pull requests") com "Repositórios acompanhados" | `PullsPanel.tsx:280-391` | diferente / faltando no Início |
| H-15 | Painel de Notas com editor, pastas e "Nova pasta"/"Nova nota" | `NotesPanel.tsx:696-800` | faltando no Início |
| H-16 | Painel de E-mail com a caixa completa (ações, seleção) | `EmailPanel.tsx:1650` | parcial (5 linhas só de leitura) |
| H-17 | Painel de Tarefas com Lista/Quadro e ações | `TasksPanel.tsx:395` | parcial (5 linhas só de leitura) |
| H-18 | Botões de período da Agenda dentro do painel | `AgendaPanel.tsx:111-146` | parcial |
| H-19 | Slack no painel com o mesmo comportamento da tela | `SlackPanel.tsx:71-93` | parcial |
| H-20 | "Bem-vindo" na primeira visita | `lib/preferences.ts:218-223` | diferente (depende do servidor) |
| H-21 | Rótulo "Início" | `components/shell/nav-items.ts:17` | diferente ("Hoje") |

Formatos persistidos que o nativo precisa respeitar para ficar compatível com o web:

- **`dashboardLayout`**: lista de `{i,x,y,w,h}`, com `w` entre 3 e 12, `x` entre 0 e 12−w, `y` ≥ 0 e `h` entre 4 e 80.
- **`dashboardLayouts`**: lista de `{width,height,layout}`, até 20, a mais nova primeiro.
- **`homeView`**: `grid` ou `workspace`.
- **Abas (Trellis)**: ficam só no `localStorage` do navegador, na chave `daily-web:teste-home`, versão 1. O servidor não guarda essa disposição.

## Shell, Kanban, páginas e tema (SH, KB, TL, CF, TH)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| SH-1 | Menu em pílula no topo: Início, Kanban, Ferramentas | `components/shell/Header.tsx:61-105` | faltando (barra lateral) |
| SH-5 | Menu do avatar com Tema, Densidade, Fundo e Novidades | `AccountMenu.tsx:136-181` | parcial |
| SH-7 | "Ir para" da paleta com Kanban, Ferramentas e Configuração | `CommandPalette.tsx:103-177` | diferente |
| SH-9 | Novidades (changelog) | `ChangelogDialog.tsx:95-145` | faltando (depende do servidor) |
| KB-1 | Kanban como item principal da navegação | `nav-items.ts:18`, `app/(app)/kanban/page.tsx` | diferente ("Agentes", dentro de "Ajustes") |
| KB-2 | Título "Kanban de tarefas" | `AgentBoard.tsx:58` | diferente ("Agentes e atividades") |
| KB-3 | Abas Tarefas/Sessões só na tela de agentes, não no Kanban | `AgentBoard.tsx:66` | diferente (sempre visíveis) |
| KB-4 | "Ativar avisos" e "Testar aviso" no Kanban | `PushToggle.tsx:91-96` | faltando (o equivalente nativo seria o aviso local) |
| KB-6 | Colunas responsivas (1, 2 ou 4) | `BoardViews.tsx:28,42` | parcial |
| TL-1 | Página **Ferramentas** (integrações) | `app/(app)/tools/page.tsx` | diferente (aba Integrações da janela de Configurações) |
| CF-1 | Página Configuração em duas colunas, incluindo Disposição | `app/(app)/config/page.tsx:21-39` | parcial (janela de Configurações, sem Disposição) |
| CF-7 | Login em cartão de vidro com botão brilhante | `app/login/page.tsx:38-87` | diferente |
| TH-1 | Fontes Geist Sans/Mono e Patrick Hand (títulos das notas no quadro) | `app/layout.tsx:3-5` | diferente (SF Pro). A Geist é OFL 1.1 (`node_modules/geist/LICENSE.txt`) e pode ir no app |
| TH-3 | Painéis de vidro (desfoque de 20 px sobre o gradiente) | `app/globals.css:919-925` | faltando |
| TH-4 | Gradiente atrás de tudo | `globals.css:908-917` | parcial (a barra lateral provavelmente o cobre) |
| TH-6 | Botões e chips em pílula | `globals.css:129-131` | diferente (botões do sistema) |
| TH-7 | Escala de sombras e1–e5 | `globals.css:798-820` | faltando |
| TH-8 | Cabeçalho de vidro em pílula | `Header.tsx:63-97` | faltando (barra de ferramentas do sistema) |

## Quadro de tarefas e Tarefas (TK)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| TK-1 | Post-it: alfinetes desenhados à mão e título em Patrick Hand 17 px | `components/tasks/PushPin.tsx:10-59`, `globals.css:1661-1668` | diferente (alfinetes em SF Symbol com sombra; fonte do sistema) |
| TK-2 | Canto dobrado em cerca de 1 a cada 3 notas | `lib/taskBoard.ts:156-158`, `globals.css:1624-1640` | faltando |
| TK-3 | Inclinação só no papel; o alfinete fica reto | `TaskBoard.tsx:92` | diferente (gira o cartão inteiro) |
| TK-4 | Abas de coluna com o quadro estreito | `TaskBoard.tsx:395-421` | faltando |
| TK-7 | Esc na adição rápida devolve o foco a "Adicionar" | `TaskBoard.tsx:249-330` | parcial |
| TK-10/11 | Linha de metadados e checklist com o estilo de post-it | `TaskBoard.tsx:154-195`, `SubtaskList.tsx:107-224` | parcial |
| TK-13 | O foco segue o cartão depois de mover por botão | `TaskBoard.tsx:344-380` | parcial |
| TK-16 | Na lista estreita, os metadados quebram linha; caixa de seleção na cor da marca | `TasksPanel.tsx:508-644` | diferente |
| TK-17 | Data em texto atrás de "Digitar data"; envio da data já interpretada | `TaskFormModal.tsx:224,391-436` | diferente |

## E-mail (EM)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| EM-1/2 | Painel compacto (sem árvore de pastas) e modo **tela cheia** com a árvore | `EmailPanel.tsx:1636-1738` | faltando (árvore sempre visível, sem modo compacto) |
| EM-3 | Pasta, mensagem, busca e ordenação lembradas | `EmailPanel.tsx:254` | faltando |
| EM-7/8 | Linhas zebradas; ícones de 28 px com contorno só ao passar o mouse | `EmailPanel.tsx:1320,1934` | diferente |
| EM-9 | Destaque do cursor visível mesmo sem foco na lista | `EmailPanel.tsx:1325` | diferente |
| EM-16 | Clique direito seleciona a linha antes do menu | `EmailPanel.tsx:1335` | parcial |
| EM-19/20 | "Maço" ao arrastar (cartões empilhados com contador) e linhas se juntando | `EmailPanel.tsx:127-182,1307-1326` | parcial / faltando |
| EM-21 | Faixa de ações ao arrastar quebra linha em largura estreita | `ActionDropTargets.tsx:68-135` | parcial |
| EM-24 | Espaço do contador da pasta sempre reservado | `FolderTree.tsx:483-521` | diferente |
| EM-30/31 | Pasta da nota escolhida na própria tela; aviso na tela com "Abrir a nota" | `CreateFromEmailMenu.tsx:223-242`, `EmailPanel.tsx:1191-1212` | diferente |

## Notas e Agenda (NT, AG)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| NT-1 | Maximizar a nota (diálogo com barra lateral e editor) | `NotesPanel.tsx:633-642,839-879` | faltando |
| NT-8/10 | Linha ativa com fundo na cor da marca e barra de 3 px à esquerda | `NoteTree.tsx:143-149`, `NoteSearchResults.tsx` | diferente (seleção do sistema) |
| NT-19 | Recarregar ao mudar uma nota por fora (por exemplo, criada a partir de um e-mail) | `NotesPanel.tsx:205-262` | faltando |
| NT-26 | Editor com mais espaço entre linhas | `NotesPanel.tsx:671-680` | diferente |
| AG-2 | Erro ao mudar o período mostrado no próprio painel | `AgendaPanel.tsx:92-108` | diferente (só toast) |
| AG-5 | Linha com destaque ao passar o mouse | `AgendaPanel.tsx:164` | faltando |
| AG-6 | Três linhas-esqueleto enquanto carrega | `AgendaPanel.tsx:151` | parcial |
| AG-14 | Toast "Bloco de foco criado" e agenda atualizada depois de criar | `FocusBlockProvider.tsx:91-93` | não verificado |

## Jira, GitHub, Slack e notificações (JR, GH, SL, NF)

| Id | Lacuna | Web | Nativo |
|---|---|---|---|
| JR-01 | Seta e título truncado no "Jira · Eu" | `PersonSwitcher.tsx:54-55` | parcial |
| JR-05, GH-01, SL-01 | Aba escolhida lembrada | `JiraPanel.tsx:132-135`, `PullsPanel.tsx:98-104`, `SlackPanel.tsx:14` | faltando |
| JR-14 | Botão de ordenar em círculo com contorno | `JiraPanel.tsx:840-864` | diferente |
| JR-18, GH-18, SL-07 | Linhas zebradas com destaque ao passar o mouse | `JiraPanel.tsx:102-103`, `PullRow.tsx:31`, `SlackPanel.tsx:35` | diferente (divisórias) |
| GH-04 | Nome do repositório com link para o GitHub | `PullsPanel.tsx:53-57` | parcial |
| GH-15 | Repositórios acompanhados como pílulas | `PullsPanel.tsx:343-358` | diferente |
| SL-03 | A linha inteira é um link | `SlackPanel.tsx:36-41` | diferente |
| NF-02 | Selo com o número de filtros ativos | `NotificationsBell.tsx:265-274` | faltando |

## Correções em documentos anteriores

O código já resolveu os seguintes itens de `audit.md`: A-4, A-5, G-2 e boa parte do G-7.

Bug encontrado no web, fora do escopo do app nativo:
`components/JiraPanel.tsx:1033` e `:1179` usam `origin` sem definir, que vira
`window.origin`. Com isso, o escurecimento dos ancestrais na árvore do Jira nunca
é aplicado.
