# Spec 010: Início com grade livre, modo Abas e disposição salva

**Lacunas:** H-1 a H-11, H-21, H-22 e H-23 ([../gaps.md](../gaps.md#início-h)).
**Depende de:** a 011 (os painéis) e a 013 (o visual).

## Problema

O Início do web é uma área de trabalho: painéis em grade livre que a pessoa
arrasta, redimensiona e salva para cada tamanho de tela, ou um modo de abas com
grupos e divisões. O "Hoje" nativo é uma lista fixa em duas colunas, sem
nenhuma organização.

## Objetivo

Reproduzir no Mac as duas disposições do Início do web, com a mesma regra de
gravação. A disposição em grade fica compartilhada com o web (DP-2).

## Requisitos

### Grade

- **FR-010-01**: grade de 12 colunas, com linha de 32 pt e margem de 24 pt
  (`lib/dashboardLayout.ts:21-23`, `DashboardGrid.tsx:273-281`). Cada painel
  ocupa `{x, y, w, h}` em unidades de grade.
- **FR-010-02**: o modo de organizar liga ao segurar um painel por 0,5 s
  (tolerância de 24 pt de movimento), ou pelo menu **Visualizar → Organizar
  painéis**. Esse item de menu é um acréscimo do Mac, para ter um caminho por
  teclado. Nesse modo:
  - arrastar move o painel;
  - a alça no canto inferior direito redimensiona;
  - os outros painéis se acomodam, como o `react-grid-layout` faz.
- **FR-010-03**: enquanto organiza, uma barra flutuante mostra "Arraste para
  mover, puxe o canto para redimensionar. Salvar guarda para L × A." e os botões
  "Salvar para esta tela" e "Descartar". Esc descarta. Arrastar não grava nada
  (`DashboardGrid.tsx:359-382`, `page.tsx:53-54`).
- **FR-010-04**: os tamanhos seguem a mesma limpeza do web: largura de 3 a 12,
  `x` de 0 a 12−w, altura de 4 a 80 (`lib/dashboardLayout.ts:52-70`). Um módulo
  sem posição salva entra na posição padrão do web (`:34-42`).
- **FR-010-05**: "Salvar" envia `PATCH /api/preferences {layout, viewport:{width,height}}`
  com o tamanho do conteúdo da janela.
  - A disposição exibida é a salva de tamanho mais próximo da janela atual
    (`nearestLayout`, distância euclidiana, `lib/dashboardLayout.ts:179-194`).
    Na falta dela, vale o `layout` antigo; na falta deste, o padrão.
  - Redimensionar a janela troca a disposição na hora, como o web faz ao mudar
    o tamanho da tela.
- **FR-010-06**: abaixo de 1023 pt de largura, a grade vira um módulo por vez,
  com uma barra de módulos (`DashboardGrid.tsx:296-341`). Os módulos fora de
  vista continuam montados, sem recarregar.

### Abas

- **FR-010-07**: o modo **Abas** mostra os painéis como abas em grupos, com
  divisões ajustáveis (`WorkspaceHome.tsx:98-120`). Ele permite:
  - arrastar uma aba para outro grupo;
  - arrastar uma aba para a borda de um grupo, criando uma divisão;
  - trocar a aba ativa;
  - redimensionar as divisões.

  As abas não fecham, e cada módulo aparece uma vez só (`singleton`,
  `closable={false}`). A disposição padrão é uma linha com duas colunas na
  proporção 3:2; a esquerda recebe a primeira metade dos módulos
  (`WorkspaceHome.tsx:43-49`). Os títulos são E-mail, Tarefas, Notas, Agenda,
  Jira, GitHub e Slack.
- **FR-010-08**: a disposição das abas fica salva localmente no Mac, por conta
  e servidor (DP-3), com versão do formato. Um módulo ligado depois aparece numa
  aba nova; um módulo desligado some (`WorkspaceHome.tsx:81-96`).
- **FR-010-09**: o botão "Restaurar abas" volta as abas à disposição padrão
  (`page.tsx:97-122`).

### Alternância e restauração

- **FR-010-10**: a alternância "Grade" / "Abas" fica no topo do Início (rótulo
  de acessibilidade "Disposição do Início") e é salva por conta com
  `PATCH /api/preferences {homeView}`. A tela muda antes da resposta do
  servidor; se ele recusar, volta e mostra "Falha ao guardar a disposição do
  Início" (`page.tsx:78-95`). Ela só aparece com algum módulo ligado.
- **FR-010-11**: "Restaurar disposição padrão" fica em Configuração → Disposição
  (spec 012). Ele usa `GET /api/preferences/layout-default` para saber se a
  disposição atual já é a padrão ("Os painéis estão na disposição padrão.") e
  envia `PATCH {layout:null}` (`LayoutPanel.tsx:13-83`). O texto do web que
  manda clicar em "Organizar" e "Concluir" está errado; vale o texto da
  FR-010-03.
- **FR-010-12**: o item da barra lateral e da navegação passa a se chamar
  "Início" (H-21).
- **FR-010-13**: as falhas ao salvar a disposição ou a alternância aparecem como
  erro no próprio Início ("Não deu para guardar a disposição" / "Não deu para
  trocar a disposição", `page.tsx:111-112`).

## Abordagem técnica

- **Grade:** um `Layout` próprio do SwiftUI (`GridDashboardLayout`) que posiciona
  os filhos em unidades de grade. O modo de organizar combina `LongPressGesture`
  e `DragGesture`, com uma alça de redimensionar. O algoritmo de acomodar os
  painéis replica o "compact vertical" do `react-grid-layout`; um tipo puro e
  testado faz mover, redimensionar, empurrar e compactar.
- **Abas:** o SwiftUI não tem abas com divisões em que se arrasta aba entre
  grupos. A estrutura será uma árvore de divisões e grupos de abas (o mesmo
  modelo do Trellis), desenhada com `HSplitView`/`VSplitView` ou `NSSplitView`.
  Os grupos usam uma barra de abas própria, e o arrastar usa `Transferable` com
  um tipo de conteúdo do app.
- **Persistência:** a grade usa os endpoints existentes. As abas ficam num
  arquivo JSON (`DiskCache`) com chave por conta.

## Fora de escopo

- Sincronizar a disposição das abas com o web: exigiria mudar o servidor.
- Painéis flutuantes do Trellis (o web não os usa).

## Critérios de aceite

- **SC-010-1:** organizar a grade no Mac e salvar faz o web, numa janela de
  tamanho parecido, mostrar a mesma disposição, e vice-versa.
- **SC-010-2:** o mover, redimensionar e compactar da grade tem testes com os
  mesmos casos de `tests/` do web para `dashboardLayout`.
- **SC-010-3:** no modo Abas, arrastar uma aba entre grupos, dividir e
  restaurar funciona, e a disposição sobrevive ao reabrir o app.
- **SC-010-4:** "Grade" ↔ "Abas" fica gravado no servidor e vale também no web.
- **SC-010-5:** você confere, pelo roteiro de teste, as duas disposições e o
  modo estreito.

## Tarefas

| Id | Tarefa | Dono | Paralelo |
|---|---|---|---|
| T010-1 | Modelo puro da grade: limpeza, padrão, `nearestLayout`, mover/redimensionar/compactar, com testes portados | FeatureHome (novo `DashboardLayoutEngine`) | sim |
| T010-2 | `GridDashboardLayout`, modo de organizar e barra de salvar | FeatureHome | depois da T010-1 |
| T010-3 | Endpoints e store da disposição (`layout`, `viewport`, `homeView`, `layout-default`) | DailyCore | sim |
| T010-4 | Modelo das abas (árvore de divisões e grupos, padrão 3:2, módulos ligados e desligados), com testes | FeatureHome | sim |
| T010-5 | Visual das abas (barra de abas, divisões, arrastar entre grupos, Restaurar abas) | FeatureHome | depois da T010-4 |
| T010-6 | Alternância Grade/Abas, modo estreito, erros e rótulo "Início" | FeatureHome + App | depois da T010-2 e da T010-5 |
