# Spec 012: Navegação em pílula, Kanban, Ferramentas e Configuração

**Lacunas:** SH-1, SH-5, SH-7, KB-1 a KB-6, TL-1, CF-1 e H-21
([../gaps.md](../gaps.md#shell-kanban-páginas-e-tema-sh-kb-tl-cf-th)).
**Depende de:** a 013 (cabeçalho de vidro e controles em pílula).
**Decisão pendente:** DP-1.

## Problema

O web se organiza em três páginas no topo: Início, Kanban e Ferramentas. As
configurações e o perfil ficam no menu do avatar. O nativo usa uma barra
lateral com cada módulo, esconde o Kanban como "Agentes" dentro de "Ajustes" e
não tem as páginas Ferramentas e Configuração.

## Objetivo

A mesma estrutura de navegação do web, com o vocabulário do web. Os atalhos e
janelas do Mac continuam (⌘K, ⌘1…⌘9, barra de menus, janelas avulsas).

## Requisitos

- **FR-012-01 · Cabeçalho.**
  - Do lado esquerdo vai o ponto da marca com "daily-web"; no centro, a
    navegação em pílula **Início**, **Kanban** e **Ferramentas**, com ícones e a
    pílula ativa destacada (`components/shell/Header.tsx:61-105`, `nav-items.ts:17-19`).
  - Do lado direito ficam busca, atualizar, sino e avatar.
  - Ele ocupa a área da barra de título, com as setas do semáforo à esquerda.
  - Com DP-1(a), a barra lateral sai.
- **FR-012-02 · Kanban.**
  - Vira página principal com o título "Kanban de tarefas", sem as abas
    Tarefas/Sessões, que são do `/agents` (KB-1 a KB-3, `AgentBoard.tsx:58-66`).
  - As colunas se distribuem como no web: 1, 2 ou 4, conforme a largura (KB-6).
  - A página "Agentes e atividades" (modo workspace, com Sessões) continua
    acessível pelo menu do avatar e pela paleta.
- **FR-012-03 · Avisos do Kanban.** "Ativar avisos" no Kanban liga os avisos
  locais de agentes aguardando você. É o equivalente nativo do
  `PushToggle.tsx:91-96`. "Testar aviso" dispara um aviso local de teste.
- **FR-012-04 · Ferramentas.** Vira página própria com o título "Ferramentas" e
  as integrações (`app/(app)/tools/page.tsx`). A tela usada hoje na aba
  Integrações da janela de Configurações é reaproveitada.
- **FR-012-05 · Configuração.**
  - Vira página, aberta pelo avatar → Configurações e por ⌘,. Ela tem Aparência,
    **Disposição** (com "Restaurar disposição padrão", spec 010) e Usuários (só
    admin), em duas colunas (`app/(app)/config/page.tsx:21-39`).
  - Perfil vira página própria ("Perfil", "Sua foto, seus dados e sua senha.").
  - A aba "Geral" (atalho global e abrir ao iniciar) fica em Configuração como
    seção do Mac.
- **FR-012-06 · Menu do avatar.** Igual ao web: Perfil, Conectar agente,
  Configurações, os grupos **Tema**, **Densidade** e **Fundo** como opções
  marcáveis, e Sair (`AccountMenu.tsx:136-181`). "Novidades" depende da DP-6.
- **FR-012-07 · Paleta.** O "Ir para" lista as páginas do web: Início, Kanban,
  Ferramentas, Acesso dos agentes, Configuração e Perfil (`nav-items.ts:17-33`).
  Atalhos: ⌘1 Início, ⌘2 Kanban, ⌘3 Ferramentas.
- **FR-012-08 · Módulos fora do Início.** Sem barra lateral, cada módulo abre a
  partir do painel dele no Início (menu "…" → "Abrir em nova janela"), da paleta
  ("Ir para → E-mail" etc.) ou da barra de menus. As notificações levam ao
  painel do módulo no Início e destacam o item.

## Abordagem técnica

- Janela com `.windowStyle(.hiddenTitleBar)` e um cabeçalho próprio em SwiftUI,
  que fica na área do título. A área de arrastar a janela é preservada nas
  partes livres do cabeçalho.
- O `AppRoute` passa a ter `.inicio`, `.kanban`, `.ferramentas`,
  `.configuracao`, `.perfil`, `.acesso` e `.agentes`. Os módulos deixam de ser
  rotas da janela principal e viram rotas de janela avulsa ou de destaque no
  Início.
- O `FeatureShell` troca o `NavigationSplitView` por um contêiner com cabeçalho
  e conteúdo. Navegação, menus e testes de atalhos são atualizados.

## Critérios de aceite

- **SC-012-1:** a navegação, os títulos e o menu do avatar têm os mesmos itens e
  textos do web.
- **SC-012-2:** ⌘1, ⌘2 e ⌘3 e a paleta levam às mesmas páginas do web.
- **SC-012-3:** clicar numa notificação leva ao item certo sem barra lateral.
- **SC-012-4:** você confere o cabeçalho ao lado do web, pelo roteiro.

## Tarefas (Onda A, depois da base da 013)

| Id | Tarefa | Dono |
|---|---|---|
| T012-1 | Novas rotas, cabeçalho em pílula, sem barra lateral, atalhos e paleta | FeatureShell, DailyCore (rotas), App |
| T012-2 | Página Kanban (título, sem abas, colunas responsivas, "Ativar avisos") | FeatureAgents |
| T012-3 | Páginas Ferramentas, Configuração (com Disposição) e Perfil | FeatureSettings |
| T012-4 | Menu do avatar com Tema, Densidade e Fundo | FeatureShell |
