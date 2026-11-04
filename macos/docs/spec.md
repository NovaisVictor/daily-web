# Spec: Daily Web para macOS (cliente nativo)

**Identidade**: `macos-native-app` · **Branch**: `feat/macos-native-app` · **Data**: 2026-11-04
**Estado**: planejamento. Nada implementado além da exclusão de `macos/` no deploy.

## Problema

O daily-web roda no navegador, ou instalado como PWA. Quem passa o dia no Mac
quer o painel como app nativo: leve, com atalhos e notificações do sistema e
integrado ao Dock e à barra de menus. Não quer depender de uma aba aberta.

## Objetivo

Um app macOS nativo (SwiftUI) com **paridade completa** com o web. Ele consome
a mesma API do servidor e fica em `macos/`, sem alterar o comportamento do web.
A instalação é feita por `brew install --cask`.

## Escopo: paridade por módulo

A referência é o inventário em [research.md § Inventário do web](research.md#inventário-do-web).
O contrato da API está em [contracts/api.md](contracts/api.md).

| Módulo | O que precisa existir no app |
|---|---|
| Sessão | Login, logout, sessão de 30 dias, volta ao login em 401, troca de servidor |
| Hoje (início) | Saudação, relógio, pomodoro (iniciar/pausar/zerar), resumo dos módulos ligados |
| Tarefas | Lista e quadro, criar/editar/apagar, data em linguagem natural, prioridade, repetição, subtarefas, cor da nota e alfinete, mover entre colunas, filtros, agendar foco |
| Notas | Árvore de pastas, criar/renomear/mover/apagar, editor Markdown com atalhos, pré-visualização, busca, reordenação, status do Drive |
| E-mail | Contas, pastas, lista com filtros/ordenação/agrupamento, seleção múltipla e atalhos (E, M, Espaço, ⌘A), lote, etiquetas, leitura do corpo, resposta com rascunho por IA, criar nota/tarefa a partir do e-mail |
| Agenda | Período (hoje a 14 dias), eventos, criar bloco de foco por arrastar e soltar |
| Jira | Abas abertas/entregues/aprovados/problemas, filtros, ordenação, acompanhar issue, pessoas, ações (transição, comentário, aprovação, impedimento, prazo, prioridade, atribuir, história, épico, data de início em lote), resumo da daily |
| Pull requests | Acompanhados/revisões/meus, filtros, repositórios e autores, aprovar, pedir mudanças, comentar, pedir revisão, merge, rerun, sincronizar Jira |
| Slack | Menções e DMs (só leitura), abrir no Slack |
| Agentes | Kanban por status, sessões, detalhe com subtarefas e atividade, transições, editar/excluir, terminal ao vivo com resposta |
| Acesso dos agentes | Tokens (criar/revogar), prompt de instruções, URL do MCP, concessões OAuth |
| Notificações | Central com filtro e "marcar lidas", resposta a menção do Jira, avisos do sistema equivalentes aos do web |
| Configurações | Aparência (tema, densidade, fundo, largura), integrações (ligar/desligar, conexões, testar, Google e Slack via navegador), perfil (nome, e-mail, foto, senha), usuários (admin) |
| Shell | Barra lateral, paleta de comandos (⌘K), "Novidades", toasts, confirmações |

## Fora de escopo

- **Qualquer mudança no servidor ou no web.** As únicas exceções aprovadas são a
  exclusão de `macos/` no `deploy/publish.sh` e a linha `@source not` do Tailwind
  (T002, pendente de aprovação). Se o app precisar de algo que a API não tem, isso
  vira uma proposta separada.
- **Grid arrastável do início.** O app usa barra lateral nativa, decisão tomada em
  2026-11-04. Ele não lê nem grava `layout`/`layouts` e não usa as abas do Trellis.
- **Web Push.** A API só aceita endpoints de navegador. Os avisos do Mac são
  notificações locais, geradas a partir do polling.
- **Login por OAuth/OIDC.** Os escopos não cobrem e-mail, notas, pomodoro,
  preferências nem usuários, e o Bearer só vale em `/mcp`. O app usa a sessão por cookie.
- **iOS/iPadOS, Intel (x86_64) e App Store.**

## Requisitos funcionais

- **FR-001**: O app autentica com `POST /api/login` e guarda o token de sessão no
  Keychain. Ele envia o token no header `Cookie` em toda requisição, inclusive em
  `http://localhost`, onde o cookie `secure` não seria reenviado automaticamente.
- **FR-002**: Toda escrita envia `Origin` igual à origem do servidor configurado.
  As escritas de pulls também enviam `Idempotency-Key` e `X-Request-Timestamp`.
- **FR-003**: O estado do painel vem de `GET /api/state`, com uma única consulta
  compartilhada a cada 20 s enquanto alguma janela está visível e a cada 60 s em
  segundo plano. Também há atualização manual (`POST /api/refresh`, ⌘R).
- **FR-004**: As mutações aplicam a mudança antes da resposta e desfazem se der
  erro, como o `mutate` do web.
- **FR-005**: Os agentes são consultados a cada 2 s só com a tela de agentes
  visível. A sincronização de notas é consultada a cada 10 s só com o Drive conectado
  e a tela de notas aberta.
- **FR-006**: Os avisos do sistema reproduzem os do web (`lib/desktopAlerts.ts`):
  novo e-mail, aprovação pendente, issue nova ou com problema, PR novo, revisão
  pedida, evento da agenda, menção ou DM no Slack, lembrete "Em N min", fase do
  pomodoro e tarefa de agente aguardando você. Clicar abre o item no app.
- **FR-007**: Os fluxos que dependem do navegador (Google Agenda e Drive, Slack)
  abrem o navegador padrão na URL do servidor. O app recarrega as integrações
  quando volta ao primeiro plano.
- **FR-008**: Os temas reproduzem os tokens de `app/globals.css`: claro/escuro/sistema,
  fundos mesh, Catppuccin, Dracula e WezTerm, e densidade. A aparência é gravada
  em `PATCH /api/preferences`, então vale igual no web e no app.
- **FR-009**: Os erros da API aparecem por módulo (`PanelResult.error`) sem
  derrubar o resto. Mensagens do servidor em português são exibidas como vêm.
- **FR-010**: O app tem uma janela principal, janelas extras por módulo (⌘ clique
  ou menu "Abrir em nova janela"), um item na barra de menus e um atalho global
  configurável para abrir o app.

## Requisitos não funcionais

- **NFR-001 (leveza)**: com a janela aberta no "Hoje", memória residente < 150 MB
  depois de 10 min. Em segundo plano sem janela visível, CPU média < 1%. Pacote
  `.app` < 25 MB. As medições ficam registradas em `validation.md`.
- **NFR-002**: macOS 26 ou superior, Apple Silicon.
- **NFR-003**: Swift 6, concorrência estrita completa e warnings tratados como erro.
- **NFR-004**: Dependências externas só as aprovadas em [plan.md § Dependências](plan.md#dependências).
- **NFR-005**: Acessibilidade com rótulos do VoiceOver equivalentes aos `aria-label`
  do web e navegação completa por teclado.
- **NFR-006**: Nenhum segredo em log ou disco fora do Keychain.

## Critérios de aceitação

- **SC-001**: Cada linha da tabela de escopo tem um roteiro de teste manual
  executado e registrado em `validation.md`.
- **SC-002**: `make check` em `macos/` passa: build, testes e lint.
- **SC-003**: Fora de `macos/`, o diff da PR só contém as exceções aprovadas.
  `npm test`, `npx tsc --noEmit` e `npm run build` dão o mesmo resultado antes e
  depois, e o CSS gerado pelo build é idêntico.
- **SC-004**: `brew install --cask novaisvictor/tap/daily-web` instala o app numa
  máquina limpa, e o roteiro do primeiro uso (incluindo "Abrir mesmo assim") está
  documentado em `macos/README.md`.
- **SC-005**: Os limites do NFR-001 são medidos e atendidos.
