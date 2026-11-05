# Spec 012: Navegação pela barra lateral, Kanban, Ferramentas e Configuração

**Lacunas:** SH-5, SH-7, KB-1 a KB-6, TL-1, CF-1 e H-21
([../gaps.md](../gaps.md#shell-kanban-páginas-e-tema-sh-kb-tl-cf-th)).
**Depende de:** a 013 (Liquid Glass e controles em pílula).
**Decisão:** DP-1 manteve a barra lateral. A pílula do topo do web (SH-1) não
será reproduzida, e isso fica registrado como divergência intencional.

## Problema

O web se organiza em três páginas no topo: Início, Kanban e Ferramentas. As
configurações e o perfil ficam no menu do avatar. O nativo usa uma barra
lateral com cada módulo, esconde o Kanban como "Agentes" dentro de "Ajustes" e
não tem as páginas Ferramentas e Configuração.

## Objetivo

Barra lateral nativa com a estrutura e o vocabulário do web: as páginas
principais primeiro e os módulos depois. Os atalhos e janelas do Mac continuam
(⌘K, ⌘1…⌘9, barra de menus, janelas avulsas).

## Requisitos

- **FR-012-01 · Barra lateral.** Três seções, na ordem do web (`nav-items.ts:17-33`):
  1. sem título: **Início**, **Kanban** e **Ferramentas**;
  2. "Módulos": E-mail, Tarefas, Notas rápidas, Agenda, Jira, GitHub e Slack,
     só os ligados;
  3. "Ajustes": Acesso dos agentes e Configuração.

  A barra de ferramentas da janela mantém busca, atualizar, sino e avatar, sobre
  Liquid Glass (spec 013). Os módulos continuam com tela própria na barra lateral
  **e** com painel no Início (spec 011).
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
  Atalhos: ⌘1 Início, ⌘2 Kanban, ⌘3 Ferramentas; os módulos vêm em seguida, na
  ordem da barra lateral.
## Abordagem técnica

- Continua o `NavigationSplitView`. O `SidebarModel` ganha a seção principal e a
  seção "Módulos", e o `AppRoute` ganha `.kanban`, `.ferramentas`,
  `.configuracao` e `.perfil` (o `.agents` continua para o modo de trabalho).
- Configuração e Perfil viram telas da janela principal. A cena `Settings` (⌘,)
  abre a Configuração.
- A barra lateral usa o material de barra lateral do macOS 26, que já é Liquid
  Glass, para o fundo do app aparecer por trás (spec 013).

## Critérios de aceite

- **SC-012-1:** a barra lateral, os títulos e o menu do avatar têm os mesmos
  itens e textos do web.
- **SC-012-2:** ⌘1, ⌘2 e ⌘3 e a paleta levam às mesmas páginas do web.
- **SC-012-3:** clicar numa notificação continua levando ao item certo.
- **SC-012-4:** você confere a navegação ao lado do web, pelo roteiro.

## Tarefas (Onda A, depois da base da 013)

| Id | Tarefa | Dono |
|---|---|---|
| T012-1 | Novas rotas, seções da barra lateral, atalhos e paleta | FeatureShell, DailyCore (rotas), App |
| T012-2 | Página Kanban (título, sem abas, colunas responsivas, "Ativar avisos") | FeatureAgents |
| T012-3 | Páginas Ferramentas, Configuração (com Disposição) e Perfil | FeatureSettings |
| T012-4 | Menu do avatar com Tema, Densidade e Fundo | FeatureShell |
