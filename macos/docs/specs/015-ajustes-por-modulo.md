# Spec 015: Ajustes por módulo e estado lembrado

**Lacunas:** EM-3, EM-9, EM-16, EM-19, EM-20, EM-21, EM-30, EM-31, NT-19, AG-2,
AG-6, AG-14, JR-05, GH-01, GH-04, SL-01, SL-03 e NF-02 ([../gaps.md](../gaps.md)).
**Depende de:** a 011 (os painéis) e a 013 (os componentes).

## Problema

Sobram diferenças pequenas de comportamento em cada módulo. Cada uma sozinha é
detalhe, mas juntas fazem o app parecer "quase" o web.

## Requisitos

### Estado lembrado

- **FR-015-01.** Cada painel lembra, por conta e servidor, o que o web guarda na
  URL:
  - E-mail: pasta, mensagem aberta, busca, ordenação, agrupamento e tela cheia (EM-3).
  - Jira: aba (JR-05).
  - GitHub: aba (GH-01).
  - Slack: aba (SL-01).

  Ao reabrir o app, tudo volta como estava.

### E-mail

- **FR-015-02.** O destaque do cursor fica visível mesmo sem foco na lista (EM-9).
- **FR-015-03.** O clique direito seleciona a linha antes de abrir o menu (EM-16).
- **FR-015-04.** Ao arrastar, a prévia é o "maço": cartões empilhados com o
  número de mensagens (até 20rem). As linhas selecionadas se juntam com
  deslocamento e sombra, respeitando a opção de reduzir movimento
  (`EmailPanel.tsx:127-182,1307-1326`) (EM-19/20).
- **FR-015-05.** A faixa de ações ao arrastar quebra linha em largura estreita (EM-21).
- **FR-015-06.** "Criar nota" escolhe a pasta da nota na própria tela, com
  "Sem pasta", carregando as pastas ao abrir. O sucesso aparece como aviso na
  tela, com "Abrir a nota" / "Abrir tarefas" e "dispensar" (EM-30/31).

### Notas

- **FR-015-07.** O painel de notas recarrega quando uma nota muda fora dele. O
  caso real é uma nota criada a partir de um e-mail. A mudança é avisada por um
  evento do núcleo (`NotesChanged`) e a nota nova abre (NT-19).

### Agenda

- **FR-015-08.** O erro ao mudar o período aparece dentro do painel e o período
  volta ao anterior. O toast sai (AG-2).
- **FR-015-09.** Enquanto carrega, o painel mostra três linhas-esqueleto (AG-6).
- **FR-015-10.** Depois de criar um bloco de foco, aparece o toast "Bloco de
  foco criado" e a agenda é atualizada. Antes de implementar, conferir se o
  `FocusScheduler` já faz isso (AG-14).

### GitHub, Slack e notificações

- **FR-015-11.** O nome do repositório no cabeçalho do grupo é link para o GitHub (GH-04).
- **FR-015-12.** A linha do Slack inteira é um link que abre a mensagem (SL-03).
  O menu "Copiar link" continua como extra do app.
- **FR-015-13.** O filtro do sino mostra um selo com o número de filtros ativos (NF-02).

## Critérios de aceite

- **SC-015-1:** fechar e reabrir o app restaura pasta, mensagem e abas.
- **SC-015-2:** criar uma nota a partir de um e-mail faz ela aparecer no painel
  de notas sem recarregar à mão.
- **SC-015-3:** cada requisito tem teste no store, ou entra no roteiro de
  conferência visual quando for só visual.

## Tarefas (Onda D)

| Id | Tarefa | Dono | Paralelo |
|---|---|---|---|
| T015-1 | Estado lembrado por painel (armazenamento por conta) | DailyCore + features | sim |
| T015-2 | Ajustes de e-mail (FR-015-02 a 06) | FeatureEmail | sim |
| T015-3 | Evento `NotesChanged` e recarga das notas | DailyCore + FeatureNotes + FeatureEmail | sim |
| T015-4 | Ajustes da agenda | FeatureAgenda | sim |
| T015-5 | GitHub, Slack e sino | FeaturePulls, FeatureSlack, FeatureNotifications | sim |
