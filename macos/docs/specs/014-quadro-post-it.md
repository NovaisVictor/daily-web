# Spec 014: Quadro de tarefas com visual de post-it e o formulário

**Lacunas:** TK-1 a TK-4, TK-7, TK-10, TK-11, TK-13, TK-16 e TK-17
([../gaps.md](../gaps.md#quadro-de-tarefas-e-tarefas-tk)).
**Depende de:** a 013 (Patrick Hand e controles).

## Problema

O quadro do web parece um mural de post-its: cada nota tem papel colorido,
alfinete desenhado à mão, título manuscrito, leve inclinação e, de vez em
quando, um canto dobrado. O quadro nativo usa os mesmos papéis, mas com
alfinetes de ícone do sistema, fonte do sistema, o cartão inteiro girando e
nenhum canto dobrado. A lista e o formulário também diferem em detalhes.

## Requisitos

- **FR-014-01 · Alfinetes.** Desenhar os alfinetes clássico, bola e coração como
  o SVG do web, com contorno de tinta e sem sombra preta
  (`components/tasks/PushPin.tsx:10-59`). As cores vêm do mapa do web.
- **FR-014-02 · Título manuscrito.** Os títulos das notas usam Patrick Hand em
  17 pt (`globals.css:1661-1668`).
- **FR-014-03 · Inclinação.** Só o papel inclina, entre −2° e 2°, com o mesmo
  hash do id. O alfinete fica reto, preso à borda (`TaskBoard.tsx:92`).
- **FR-014-04 · Canto dobrado.** Cerca de uma nota em cada três tem o canto
  dobrado, escolhida pela mesma regra do web (`lib/taskBoard.ts:156-158`,
  `globals.css:1624-1640`).
- **FR-014-05 · Colunas e notas.** Faixa, cabeçalho, contador, linha de
  metadados (prioridade, "repete", prazo com marca de atrasada, barra de
  progresso) e checklist com o visual de post-it (`globals.css:1316-1368`,
  `TaskBoard.tsx:154-195`, `SubtaskList.tsx:107-224`).
- **FR-014-06 · Quadro estreito.** Em largura pequena, as colunas viram abas
  (`TaskBoard.tsx:393-421`). Isso importa porque o quadro agora mora num painel
  da grade.
- **FR-014-07 · Foco.**
  - Ao mover uma nota por botão, o foco do teclado continua nela
    (`TaskBoard.tsx:344-380`).
  - Esc na adição rápida devolve o foco a "Adicionar" (`TaskBoard.tsx:249-330`).
- **FR-014-08 · Lista.**
  - Em largura estreita, os metadados quebram para a linha de baixo
    (`@max-[34rem]`).
  - A caixa de seleção usa a cor da marca (`TasksPanel.tsx:508-644`).
- **FR-014-09 · Formulário.**
  - O campo de data em texto fica atrás de "Digitar data", como no web.
  - O app envia a data já interpretada (`AAAA-MM-DD [HH:MM]`), igual ao web
    (`TaskFormModal.tsx:224,391-436`); o parser já foi portado.
  - Os extras do app ("Coluna" na criação e "Sem hora") ficam e são registrados
    como divergência.

## Critérios de aceite

- **SC-014-1:** o hash da inclinação e a regra do canto dobrado batem com
  `lib/taskBoard.ts` (testes com os mesmos ids).
- **SC-014-2:** criar e editar envia o mesmo `due` que o web enviaria para o
  mesmo texto (testes do parser).
- **SC-014-3:** você confere o quadro lado a lado com o web, nos quatro fundos.

## Tarefas (Onda B, em paralelo com a 011)

| Id | Tarefa | Dono |
|---|---|---|
| T014-1 | Alfinetes desenhados (`Shape`), inclinação só no papel e canto dobrado | FeatureTasks |
| T014-2 | Visual da faixa e da nota (metadados, checklist, Patrick Hand) e abas no estreito | FeatureTasks |
| T014-3 | Foco ao mover e na adição rápida, lista estreita, caixa de seleção na cor da marca | FeatureTasks |
| T014-4 | Formulário: "Digitar data" e envio da data interpretada | FeatureTasks |
