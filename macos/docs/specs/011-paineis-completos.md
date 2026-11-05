# Spec 011: Painéis com o módulo inteiro dentro

**Lacunas:** H-12 a H-19, EM-1/2 e NT-1 ([../gaps.md](../gaps.md)).
**Depende de:** a 013 (cabeçalho e superfícies de painel).
**É a base da 010:** a grade e as abas exibem estes painéis.

## Problema

No web, cada painel do Início é o módulo de verdade: dá para responder um
e-mail, marcar uma tarefa, trocar a pessoa do Jira ou adicionar um repositório
sem sair dele. No nativo, os módulos só existem como telas inteiras, e o "Hoje"
mostra cinco linhas só de leitura.

## Objetivo

Cada módulo passa a ter uma versão de **painel**, que pode ir para a grade ou
para as abas e tem as mesmas funções do painel do web. A tela inteira de cada
módulo continua existindo para janelas avulsas e para o modo "tela cheia".

## Requisitos

- **FR-011-01 · Moldura do painel.** Cada painel usa um cabeçalho com título,
  contagem e uma área de ações (`components/ui/Section.tsx:6-28`), sobre a
  superfície de painel da 013. O "Abrir ›" do protótipo atual sai do cabeçalho;
  abrir um módulo em janela própria fica como ação no menu "…" do painel.
- **FR-011-02 · E-mail.** O painel compacto do web é lista e leitor, sem a
  árvore de pastas. A árvore aparece só em **tela cheia**, que abre como janela
  ou folha grande (84rem, árvore à esquerda) com o botão "Tela cheia" /
  "Restaurar" (`EmailPanel.tsx:1005-1012,1636-1738`). Dentro do painel ficam
  todas as ações que a tela já tem.
- **FR-011-03 · Tarefas.** O painel tem a alternância Lista/Quadro (salva com
  `tasksView`), filtros, criação, conclusão, subtarefas, cores e agendar foco.
  Ou seja, a tela atual cabe no painel (`TasksPanel.tsx:395`).
- **FR-011-04 · Notas.** O painel tem a árvore, o editor, "Nova pasta" e "Nova
  nota" no cabeçalho (`NotesPanel.tsx:696-800`) e **Maximizar/Restaurar**. O
  modo maximizado tem barra lateral, editor e "Criar em: …" no cabeçalho da
  barra lateral, como no web (`NotesPanel.tsx:633-642,717-735,839-879`). Isso
  substitui a decisão anterior de deixar Notas fora do Início.
- **FR-011-05 · Agenda.** O painel tem os botões de período, a lista por dia e a
  área de soltar para bloco de foco (`AgendaPanel.tsx:111-175`).
- **FR-011-06 · Jira.** O painel tem o "Jira · Eu" com a troca de pessoa e o
  "Acompanhar pessoa", e o resumo da daily no cabeçalho quando a pessoa ativa é
  você (`JiraPanel.tsx:626-653`). Também tem as abas, a busca, os filtros, a
  ordenação, o "Acompanhando" e a árvore com ações.
- **FR-011-07 · GitHub.** O painel se chama **"GitHub"**, como no web (H-14). Ele
  tem as abas, os filtros, os grupos por repositório e, no rodapé de
  "Acompanhados", o "Repositórios acompanhados" com adicionar e remover
  repositórios e autores (`PullsPanel.tsx:280-391`).
- **FR-011-08 · Slack.** O painel tem as abas Menções e Mensagens diretas, o
  nome do time e as linhas como no web (`SlackPanel.tsx:71-93`).
- **FR-011-09 · Painel estreito.** Cada painel se adapta à largura que a grade
  der. Os metadados quebram linha, e as barras de filtro viram popover, nos
  mesmos pontos de quebra do web (por exemplo `@max-[34rem]` na lista de
  tarefas).
- **FR-011-10 · Estado.** Rolagem, aba ativa e filtros de cada painel persistem
  enquanto a disposição muda (mover ou trocar para o modo Abas não recria o
  estado), como o `hidden` sem desmontar do web (`DashboardGrid.tsx:315-323`).

## Abordagem técnica

- Cada feature passa a expor `public struct <Módulo>Panel: View`
  (`init(environment:)`), que é a variante compacta, ao lado da `<Módulo>Screen`
  que já existe.
  - Painel e tela compartilham o mesmo store. Ele fica no `AppEnvironment`, num
    registro de stores por módulo criado uma vez só, para que mover o painel não
    recrie o estado (FR-011-10).
  - Os componentes internos que hoje estão nas telas (listas, linhas, menus,
    barras) são extraídos para que painel e tela usem os mesmos.
- O `ModuleRegistry` ganha, para cada módulo, uma fábrica de painel ao lado da
  de tela.
- A tela Hoje com painéis que está sem commit (DP-7) vira o ponto de partida.
  Os tipos de linhas por aba de lá servem para o resumo de cada painel quando a
  altura dele for pequena.

## Fora de escopo

- Corpo do e-mail em HTML (limitação do servidor).

## Critérios de aceite

- **SC-011-1:** cada ação listada na matriz de paridade do módulo
  ([../audit.md](../audit.md), seção 1) funciona de dentro do painel.
- **SC-011-2:** mover um painel na grade ou passá-lo para as abas não perde a
  aba ativa, os filtros, o texto digitado nem a rolagem.
- **SC-011-3:** o painel de e-mail tem modo compacto e tela cheia, e as notas
  maximizam e restauram.
- **SC-011-4:** você confere cada painel lado a lado com o web, pelo roteiro.

## Tarefas (Onda B: um agente por módulo)

| Id | Tarefa | Dono |
|---|---|---|
| T011-0 | Registro de stores por módulo no `AppEnvironment`, fábrica de painel no `ModuleRegistry` e moldura de painel (orquestrador) | DailyCore, App, DailyDesign |
| T011-1 | `EmailPanel` (compacto) e tela cheia | FeatureEmail |
| T011-2 | `TasksPanel` | FeatureTasks |
| T011-3 | `NotesPanel` e maximizar | FeatureNotes |
| T011-4 | `AgendaPanel` | FeatureAgenda |
| T011-5 | `JiraPanel` com troca de pessoa e daily | FeatureJira |
| T011-6 | `GitHubPanel` com repositórios acompanhados, e `SlackPanel` | FeaturePulls, FeatureSlack |
