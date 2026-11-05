# Spec 013: Linguagem visual do web

**Lacunas:** TH-1, TH-3, TH-4, TH-6, TH-7, TH-8 e CF-7, mais as diferenças de
linha e controle de todos os módulos: JR-01, JR-14, JR-18, GH-15, GH-18, SL-07,
EM-7, EM-8, EM-24, NT-8, NT-10, NT-26 e AG-5 ([../gaps.md](../gaps.md)).
**Decisões pendentes:** DP-4 (fonte) e DP-5 (vidro).
**É base para todas as outras specs.**

## Problema

O app usa as cores do web, mas não a aparência. Faltam:

- os painéis de vidro sobre o gradiente;
- a fonte Geist;
- os botões e chips em pílula;
- as sombras;
- as linhas zebradas com destaque ao passar o mouse.

No lugar disso entram controles e seleções do sistema. O resultado é um app
"de macOS" com as cores do web, e não o daily-web no Mac.

## Objetivo

Um design system no `DailyDesign` que reproduz a linguagem visual do web, usado
por todas as telas. Cada token e componente cita a regra CSS ou o componente de
origem.

## Requisitos

- **FR-013-01 · Fontes (DP-4a).** Embutir Geist Sans e Geist Mono, com a licença
  OFL junto (`node_modules/geist/LICENSE.txt`), e usá-las em todo o app. A
  Patrick Hand vai só nos títulos do quadro (spec 014), depois de confirmada a
  licença. A escala de tipos (`TypeRole`) já tem os tamanhos do web; troca só a
  família.
- **FR-013-02 · Superfícies de vidro (DP-5a).**
  - Componente `GlassSurface`, equivalente a `.glass` do web: fundo `--glass`
    com desfoque de 20 px e saturação de 150%, e borda de 1 px em `--glass-line`
    (`app/globals.css:919-925`; tokens `:98-100` no claro e `:211-213` no escuro).
  - Os painéis do Início, o cabeçalho, os menus, o popover do sino, a paleta e o
    cartão de login usam esse componente.
- **FR-013-03 · Fundo.** O gradiente (mesh, Catppuccin, Dracula, WezTerm) passa
  a ficar visível atrás de toda a janela. Sem a barra lateral (DP-1), nada mais
  o cobre (`globals.css:908-917`).
- **FR-013-04 · Sombras.** Tokens `e1` a `e5` com os valores de
  `globals.css:798-820`, aplicados onde o web aplica: cartões, menus, diálogos e
  a paleta.
- **FR-013-05 · Controles em pílula.** Componentes próprios com as variantes e
  os tamanhos do web, no lugar dos botões e seleções do sistema
  (`components/ui/*`, `globals.css:129-131`):
  - `PillButton`: primário, contorno, fantasma e destrutivo;
  - `IconButton`: botão só de ícone, com contorno ao passar o mouse;
  - `SegmentedPills`: abas de painel e Lista/Quadro;
  - `Chip`: filtro.

  O brilho do botão primário segue o "Entrar" do login.
- **FR-013-06 · Linhas de lista.** Componente `ListRow` com:
  - listras alternadas (`even:bg-muted/25`);
  - destaque na cor da marca ao passar o mouse (`hover:bg-brand-tint`);
  - divisória `line-soft`;
  - espaçamento `px-2 py-3`.

  Ele é usado nas listas de e-mail, Jira, GitHub, Slack, agenda, tarefas e
  notificações.
- **FR-013-07 · Seleção.** As listas com seleção (árvore de notas, resultados de
  busca, pastas de e-mail) usam a linha ativa do web, com fundo na cor da marca
  e uma barra de 3 px à esquerda (`NoteTree.tsx:143-149`), em vez da seleção do
  sistema.
- **FR-013-08 · Detalhes por módulo.**
  - Botão de ordenar do Jira num círculo de 32 px com contorno (JR-14).
  - Seta no "Jira · Eu" (JR-01).
  - Repositórios acompanhados como pílulas com sombra (GH-15).
  - Contador de pasta de e-mail com espaço sempre reservado (EM-24).
  - Ícones das linhas de e-mail com 28 px e contorno só ao passar o mouse (EM-8).
  - Mais espaço entre linhas no editor de notas (NT-26).
- **FR-013-09 · Login.** Cartão de vidro com sombra `e3`, ponto da marca e botão
  "Entrar" com brilho (`app/login/page.tsx:38-87`). O campo Servidor continua,
  porque é exclusivo do app.
- **FR-013-10 · Densidade.** Confortável e compacta mudam os espaçamentos como no
  web (`lib/theme.ts:21-53`), e isso é verificado nos componentes novos.

## Abordagem técnica

- **Fontes:** os arquivos ficam nos recursos do target do app, registrados com
  `ATSApplicationFontsPath`. Um `Font.daily(_:)` no DailyDesign escolhe a família.
- **Vidro:** `.background(.ultraThinMaterial)` com uma camada do token `--glass`
  por cima, e borda e sombra, calibrados lado a lado com o web nos quatro fundos.
  O Liquid Glass do macOS 26 (`glassEffect`) é opção para o cabeçalho (DP-5).
- **Galeria:** a galeria do DailyDesign ganha uma página por componente novo,
  nos dois esquemas e nos quatro fundos, para a conferência visual.

## Critérios de aceite

- **SC-013-1:** nenhum `.buttonStyle(.bordered|.borderedProminent)` nem seleção
  do sistema nas telas de feature (conferido com grep). Tudo passa pelos
  componentes do DailyDesign.
- **SC-013-2:** a galeria mostra cada componente nos quatro fundos e nos dois
  esquemas.
- **SC-013-3:** o contraste continua AA (os testes atuais do DailyDesign se
  estendem às superfícies de vidro).
- **SC-013-4:** você confere a galeria e duas telas ao lado do web, pelo roteiro.

## Tarefas (Onda A)

| Id | Tarefa | Dono | Paralelo |
|---|---|---|---|
| T013-1 | Fontes Geist embutidas, licença e `Font.daily` | DailyDesign + App (recursos) | sim |
| T013-2 | `GlassSurface`, sombras e1–e5, ajuste do fundo | DailyDesign | sim |
| T013-3 | `PillButton`, `IconButton`, `SegmentedPills`, `Chip`, `ListRow` e linha ativa | DailyDesign | sim |
| T013-4 | Migrar as telas de feature para os componentes novos (um agente por grupo de módulos) | Feature* | depois da T013-1 a T013-3 |
| T013-5 | Cartão de login | FeatureShell | depois da T013-2 e da T013-3 |
