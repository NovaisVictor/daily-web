# Validação

Evidências de cada tarefa concluída. Comandos executados a partir da raiz do
repositório, salvo indicação.

## Base do web (T008), 2026-11-04, commit `85e6ad1`

Medida com `macos/` fora da árvore, ou seja, o estado do `main`:

| Verificação | Resultado |
|---|---|
| `npx tsc --noEmit` | exit 0 |
| `npm test` | 195 arquivos, 3145 testes, todos passando |
| `npm run build` | exit 0 |
| CSS gerado (`.next/static/**/*.css`, sha256) | `40fd8c84…dbfe2`, `d3b422f9…e7cae`, `6e6627b3…c4bc4b` |

Observação: o `node_modules` do checkout principal estava desatualizado (faltava
`@danfessler/trellis`). A worktree usa `npm ci`, que segue o lockfile sem mudar
dependências.

## T001: `deploy/publish.sh`

`--exclude 'macos/'` no rsync. Verificado por leitura: é o único rsync do script.

## T002: `app/globals.css`, `@source not "../macos"`

| Cenário | CSS comparado à base |
|---|---|
| `macos/probe/Probe.swift` com a string `"bg-fuchsia-900 grid-cols-11 translate-x-97"`, **sem** T002 | **diferente**: um arquivo mudou (`40fd8c84…` → `91e38e6c…`) |
| Mesmo arquivo de teste, **com** T002 | **idêntico** aos três hashes da base |

Depois da T002: `npx tsc --noEmit` exit 0 e `npm test` com 195 arquivos e 3145
testes passando. O arquivo de teste foi removido.

Nota de processo: `npx tsc --noEmit` reescreve o `tsconfig.tsbuildinfo`, que é
versionado. Restaure-o com `git checkout -- tsconfig.tsbuildinfo` depois de cada
verificação.

## T003: dependências

Tags confirmadas por `git ls-remote`: `gonzalezreal/textual` 0.5.0 e
`sindresorhus/KeyboardShortcuts` 3.1.0. As duas resolvem e compilam no `swift build`.

## T004–T007: esqueleto

Em `macos/`, `make check` termina com exit 0. Ele inclui:

- `swift format lint --strict`, sem achados;
- `swift test`, com 18 testes (um por target) passando;
- `xcodebuild` Debug compilando o app.

O app sai com o identificador `io.github.novaisvictor.dailyweb` e assinatura ad-hoc
(em Debug, `codesign` desliga o hardened runtime com ad-hoc, como esperado).

## Onda 1: T101–T104 (gate em 2026-11-04)

Em `macos/`, `make check` termina com exit 0: lint sem achados, **106 testes em 12 suítes** passando e o app compilando.

| Tarefa | Evidência |
|---|---|
| T101 Modelos | 73 fixtures fictícios; todos decodificam e fazem encode → decode igual; o reencode precisa conter toda chave não nula; enum desconhecido decodifica |
| T102 API/armazenamento | 31 testes com `URLProtocol` stub cobrindo `Cookie`, `Origin`, idempotência, `Authorization` nunca enviado, três formatos de erro, 401, mapeamento de `URLError`, 204. O Keychain de login passa. O Keychain moderno é pulado, porque com assinatura ad-hoc responde -34018 |
| T103 Design | 18 testes: contraste WCAG (ink/surface ≥ 11,4; inkMid ≥ 8,0 em todas as paletas), fallback de Dracula e WezTerm no tema claro, conversão de oklch |
| T104 Shell | 20 testes: ordem e fallback da barra lateral, busca da paleta, validação do endereço do servidor |

Ajustes do orquestrador no gate:

- `APIError.storage(detail:)`. Falha ao gravar no Keychain deixa de aparecer como "sessão expirou".
- Contrato corrigido em três respostas do Jira.

Fora de `macos/`, nada mudou nesta onda.

## Onda 2: contrato contra o servidor real (2026-11-04)

O servidor rodou com `npm run dev` na worktree, com `.env.local` local e um banco
SQLite descartável (`data/macos-dev.db`), usando o usuário de teste `macos-dev`
(admin). Um executável descartável usou o `HTTPAPIClient` real do DailyKit:

| Passo | Resultado |
|---|---|
| Login com senha errada | `.server(401)` → "usuário ou senha inválidos" |
| Login correto em `http://localhost:8010` | token do `Set-Cookie` (cookie `Secure`) guardado |
| `GET /api/me` | decodifica `CurrentUser` (`macos-dev`, admin) |
| `GET /api/state` | decodifica `DashboardState` real (módulos `tasks` e `notes`, pomodoro ligado) |
| `signOut` + `GET /api/me` | `.unauthorized` |

Ainda não verificado nesta etapa: o login pela interface do app empacotado, com
sandbox e Keychain de login.

## Onda 2: gate e revisão (T203)

A revisão independente (skill `code-review`, nível medium) encontrou 10 achados,
todos corrigidos com teste de regressão:

- sessão expirada mantendo dados da conta anterior;
- `restore` repetido por janela;
- ordem das atualizações de aparência;
- aparência não sincronizada (limitação do servidor, que não tem GET; o espelho passou a ser por conta);
- cadência por foco em vez de visibilidade;
- ATS sem mensagem própria;
- cache gravado na thread principal;
- erro de leitura antiga gravado;
- formatação de data duplicada;
- fallback silencioso em `Endpoint.segment`.

`make check` termina com exit 0, com **189 testes em 21 suítes**. Nada mudou
fora de `macos/` nesta onda.

## Onda 3: T301–T305 (gate em 2026-11-04)

Em `macos/`, `make check` termina com exit 0: **470 testes em 50 suítes**, lint
limpo e o app compilando. Nada mudou fora de `macos/`.

**App empacotado de ponta a ponta** (Debug, sandbox, assinatura ad-hoc, Keychain de login):

- Login pela interface com `macos-dev` em `http://localhost:8010` funcionou.
- A barra lateral mostra só os módulos ligados no servidor (Tarefas e Notas).
- O quadro de tarefas e a tela Hoje aparecem com os textos do web.
- Memória residente: cerca de 137 MB em Debug. A medição em Release fica para a T502.
- Sair pelo menu encerra o app pelo caminho ordenado (`ShutdownTasks`).

**Ajustes do orquestrador no gate:**

- 401 de credencial digitada (`/api/me/password`) não encerra mais a sessão.
- Navegador e encerramento ordenado no núcleo.
- Formulário de bloco de foco único no DailyDesign.
- Liga/desliga por módulo removido, porque o web o tirou de propósito.
- Tipos de arraste declarados no `Info.plist`.
- Destaque na cor da marca.

**Divergências registradas, que dependem do servidor:**

- O corpo do e-mail chega só em texto puro, sem HTML.
- O "Bem-vindo" vs. "Bem-vindo de volta" não vem no `/api/me`.
- Não existe GET da aparência, então o app guarda a aparência localmente por conta.

## Onda 4: T401–T404 e revisão (T405), 2026-11-04

Em `macos/`, `make clean && make check` termina com exit 0: **778 testes em 78
suítes**, lint limpo e o app compilando. Nada mudou fora de `macos/`.

| Tarefa | Testes do target |
|---|---|
| T401 Jira | 106 (filtros, ordem e resumo da daily portados dos testes do web, todos os endpoints) |
| T402 Pulls | 80 (todas as escritas `idempotent`, `headSha` em merge/rerun) |
| T403 Slack + Notificações | 41 (lotes de até 200 ao marcar como lidas, chave do Jira para responder) |
| T404 Agentes + Acesso | 57 (transições por status, `expectedVersion`, 409, escopos de token) |

Não exercitados contra o servidor real: Jira, GitHub, Slack, e-mail e Google,
porque o servidor local não tem credenciais. A cobertura dessas telas é de código
e de testes com cliente falso.

**Revisão independente (T405):** 10 achados, todos corrigidos com teste:

- item pendente de notificação consumido cedo, ou vazando entre telas (navegador redesenhado);
- texto de nota perdido num autosave que falhou;
- autosaves fora de ordem;
- espera de encerramento sem limite (agora 5 s);
- janela de dias dos agentes gerando aviso duplicado;
- agenda com calendário não gregoriano;
- três cópias da janela de foco e URL de reconexão divergente;
- arraste de e-mail para pasta de outra conta.

**Incidente de build:** um campo novo em `Endpoint` deixou binários com layout
antigo no build incremental do SwiftPM, e os testes caíram com sinal 10/11.
Foi resolvido com build limpo. Criado o `make clean`, com nota no `AGENTS.md`.

## Onda 5: T501–T503 (2026-11-04)

Em `macos/`, `make clean && make check` termina com exit 0: **824 testes em 87
suítes**, lint limpo e o app compilando. Nada mudou fora de `macos/`.

- **T501:**
  - item da barra de menus;
  - atalho global (padrão ⌃⌥⌘D);
  - abrir ao iniciar (`SMAppService`);
  - janela principal única e janelas por módulo;
  - menus "Ir" com ⌘1…⌘9 e ⌘K, e ⌘R;
  - ações nos avisos do sistema ("Abrir", "Marcar como lida").
- **T502:** auditoria em [audit.md](audit.md).
  - Contrato contra o servidor local: 13 de 13 GETs decodificam.
  - Release: 119,5 MB de RSS no Hoje e 0,17% de CPU oculto (amostra curta).
- **T503:** todos os P1 e os P2 da auditoria corrigidos.
  - Release sem símbolos de debug: o `.app` foi de 32 MB para **16 MB**.
  - Teclado nas ações de Notas, E-mail, Jira, subtarefas e Agentes.
  - Configurações abrindo na aba pedida.
  - Aviso de agente aguardando com o título do web, também sem a tela aberta.
  - Prévia da data em linguagem natural (parser portado com os testes do web).

**App reaparecendo sozinho (G-14):** causa provável é o atalho padrão antigo,
⌥⌘D, que coincide com o atalho do macOS "Ocultar/mostrar o Dock", ativo nesta
máquina. O padrão mudou e as reaberturas da janela são registradas com o motivo.
Não foi reproduzido.

**Ainda não verificado:**

- Item da barra de menus e menu "Ir" vistos na tela. Pela acessibilidade eles não
  apareceram durante a T501; a suspeita é que o app não ficou em primeiro plano.
- CPU com o app oculto por 10 minutos (SC-005).

**Divergências intencionais em relação ao web:**

- "Novidades" ausente: não há rota no servidor, e copiar `lib/changelog.ts`
  deixaria os dois divergindo.
- ⌘K no editor de notas insere link e não abre a paleta. O web faz as duas coisas.
- Campo de data em texto sempre visível no formulário de tarefa, e data inválida
  recusada pelo servidor.
- Quadro de tarefas estreito sem abas de coluna.
- Aviso de agente também para retenções de decisão, acesso e credencial, e com
  checagem em segundo plano a cada 60 s; o web depende de Web Push.
- Tela cheia do e-mail e "Maximizar" das notas substituídos pela tela cheia nativa.
- Dependências transitivas do Textual (`swiftui-math`, cerca de 7 MB de fontes)
  dentro do pacote: aceitas, porque o `.app` está em 16 MB.

## Checagens finais da Onda 5 (2026-11-04, build Release)

| Verificação | Resultado |
|---|---|
| Menu "Ir" | Lista Hoje e os módulos com a janela principal em foco; sem foco, só "Buscar…" |
| Item da barra de menus | Painel com pomodoro, tarefas, não lidas, "Abrir notificações", "Abrir Daily Web" e "Sair" |
| App oculto por 10 min | Não voltou a ficar visível (G-14 não se repetiu com o novo atalho) |
| CPU oculto, antes | Média de 2,7%: o relógio da tela Hoje redesenhava a janela a cada segundo |
| CPU oculto, depois da correção | **0,04%** (0,11 s de CPU em 300 s); RSS de 104 MB |
| Tamanho do `.app` Release | **16 MB** |

O NFR-001 está atendido: menos de 150 MB, menos de 1% de CPU em segundo plano e
menos de 25 MB de `.app`.

`make check` final: **824 testes em 87 suítes**, lint limpo e o app compilando.

`Scripts/sign.sh`, testado numa cópia do Release:

- A identidade "Daily Web Self-Signed" foi criada no Keychain de login.
- `codesign --verify --strict` passa.
- Requisito designado: `identifier "io.github.novaisvictor.dailyweb" and certificate leaf = H"7770…e88a"`.
  Ele é estável entre builds; com ad-hoc, era o cdhash de cada build.

## Onda 6: distribuição (2026-11-04)

- **T602:** `Scripts/release.sh 0.1.0` compilou em Release, assinou com a
  identidade estável e gerou `DailyWeb-0.1.0.zip` (sha256 `ee1e0022…c426`). Depois
  publicou a release
  [macos-v0.1.0](https://github.com/NovaisVictor/daily-web/releases/tag/macos-v0.1.0)
  no fork e enviou `Casks/daily-web.rb` ao `NovaisVictor/homebrew-tap`.
- **T603:** o brew avisou que `depends_on macos: ">= :tahoe"` está
  descontinuado. O modelo e o cask publicado passaram a usar `:tahoe`.
- **T605 (parcial):** testado nesta conta, não numa conta limpa.
  - `brew tap novaisvictor/tap && brew install --cask daily-web` instala em
    `/Applications`, na versão 0.1.0, com quarentena, assinado por
    "Daily Web Self-Signed", e mostra as instruções de primeiro uso.
  - `spctl --assess` resulta em `rejected`, o esperado sem Developer ID.
  - **Não verificado:** a liberação por "Abrir mesmo assim" e o primeiro login
    no app instalado pelo brew, que dependem de uma ação manual nos Ajustes.

## Revisão final (T606) e PR

- A revisão independente das Ondas 5 e 6 apontou 10 achados, todos corrigidos:
  - alerta de agentes parado com o app oculto;
  - "Marcar como lida" antes de a sessão ser restaurada;
  - ⌘N duplicado ("Nova tarefa" passou para ⌘T);
  - pedidos do navegador consumidos pela janela errada;
  - calendário gregoriano no formulário de tarefa;
  - lógica de dia triplicada, agora em `DailyCore/Features/TaskDay.swift`;
  - `ThemedRoot` duplo no painel da barra de menus;
  - "marcar todas" duplicado;
  - `release.sh` sem checar arquivos não rastreados;
  - `release.sh` sem como retomar quando o tap falha.
- `make clean && make check` final: **837 testes em 89 suítes**.
- PR: https://github.com/joaosouzacoder/daily-web/pull/102
