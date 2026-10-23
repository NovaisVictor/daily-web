# Ruflo Review 1

Execution: Ruflo reviewer/task orchestration with local Claude CLI. Direct Ruflo LLM execution had no configured provider. Supplied artifacts only; no source inspection claimed.

REJECTED

Fiz a revisão só lendo os documentos enviados. Não usei ferramentas: não consultei o AI Memory nem o Codebase Memory e não confirmei nada no código-fonte. Nenhum gate de implementação foi executado. Os achados se baseiam apenas no texto dos artefatos.

## Bloqueantes

**B1 — Segredos de Jira/GitHub passam pelo MCP, o que contradiz a constituição e a spec.**
- **Onde:**
  - `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/contracts/mcp-capabilities.md`, seção "Shared actions required by supported panels": as ferramentas `connections` permitem "add/edit … Jira/GitHub/task connection" com campos secretos como entrada.
  - `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/tasks.md`, T034.
- **Conflito:**
  - Princípio I da constituição: credenciais não podem aparecer em prompts.
  - User Story 3, AC1 da spec: o usuário autoriza "without copying … Jira/GitHub credential into the client".
  - Os argumentos de uma ferramenta MCP são gerados pelo modelo e ficam no contexto e no transcript do cliente. A promessa do contrato de "never place them in model prompts" não pode ser cumprida assim.
- **Contradição adicional:** a tabela "Constitution Check" de `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/plan.md` marca "User isolation and secrets: Pass by design".
- **Correção:** excluir do MCP qualquer escrita de conexão que carregue segredo. O MCP passa a devolver um link para o fluxo no navegador, como já acontece com a administração de credenciais. Leitura de metadados, teste e toggle podem continuar no MCP. Registrar essa exclusão como desvio explícito do inventário de paridade.

**B2 — Um restore pode reativar acessos revogados.**
- **Onde:**
  - `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/data-model.md`, último item de "Last-activity retention".
  - `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/tasks.md`, T009.
- **Problema:** o backup lógico exclui apenas dados de agentes. ApiCredential, OAuthGrant e OAuthToken continuam nele. Restaurar um backup anterior a uma revogação reativa a credencial ou o grant, o que viola FR-017 e SC-008.
- **Correção:** definir no data model que o restore não pode reativar o que foi revogado. Duas opções: excluir credenciais e grants do backup e forçar nova emissão depois do restore, ou revogar tudo por padrão no restore. Incluir um teste para isso em T009/T010.
- **Lacuna relacionada:** nenhuma task desativa ou ajusta um backup bruto do banco que já exista hoje. T001 deveria inventariar o mecanismo de backup atual.

**B3 — A unicidade de `externalId` conflita com expiração e recriação.**
- **Onde:** `/Users/joao.souza/projects/daily-web/specs/001-agent-workspace/data-model.md`, na tabela Entities (AgentTask com unique owner + externalId) e na seção "Last-activity retention".
- **Problema:** a seção diz que uma tarefa nova "explicitly creates a new identity". Entre a expiração na leitura e a limpeza física (até 1h, ou mais se a limpeza falhar), um POST /tasks com o mesmo `externalId` esbarra na constraint. Isso gera um 409 ou 500 não especificado, contrariando FR-009 (resultado definido e visível). Também não está claro se um `externalId` pode ser reutilizado depois que a tarefa expira. É comum agentes usarem a chave Jira como `externalId`.
- **Correção:** decidir uma das duas regras e documentar o código de erro correspondente:
  - unicidade apenas entre registros vivos, com o expirado tratado como inexistente na criação; ou
  - proibição de reutilização com um erro explícito.

## Não bloqueantes (resolver antes da task indicada)

**N1 — Recibos de DELETE.** Em `data-model.md`, recibos agent-local "expire with the affected agent resource". Um retry de DELETE então devolve 404 em vez do 204 original, o que contradiz "repeated key … returns its original outcome". Precisa ser definido antes de T006.

**N2 — DCR sem limite.** Em `contracts/oauth.md`, "Pre-register … or use constrained DCR" não define o que é "constrained". Os três clientes devem exigir DCR, e um registro aberto permite crescimento ilimitado no SQLite (FR-020). Definir cota, TTL de clientes não usados e rate limit antes de T026.

**N3 — Como a UI se atualiza para cumprir SC-002.** A meta de ≤5s depende do mecanismo de atualização da tela (polling ou push), que não está especificado em `plan.md` nem em T014/T016.

**N4 — Validação do token em `/mcp`.** Não está explícito como a rota `/mcp` no Next valida o token opaco emitido pela companion (leitura do adapter compartilhado ou introspecção pelo socket). Também faltam:
- quem roda as migrations das tabelas OAuth e a ordem de inicialização dos dois processos;
- `busy_timeout` para dois escritores no SQLite.

Isso afeta T004, T026 e T029.

**N5 — Ordem de dependência de T011.** T011 (Fase 2) exige descoberta por clientes reais, mas a infraestrutura de proxy e deploy só chega em T037. É preciso esclarecer se o spike roda em loopback ou se depende de T037.

**N6 — `expectedVersion` em atividade e heartbeat.** Em `contracts/reporting-api.md`, exigir `expectedVersion` em POST `/tasks/{id}/activity` faz relatos concorrentes de progresso entrarem em conflito o tempo todo e obriga um GET antes de cada relato. Avaliar se atividade append-only deveria dispensar versão.

**N7 — Escopo de tarefas pessoais.** Tarefas pessoais (incluindo mstodo) entram no MCP da US3 sob o rótulo "agents/tasks". A spec não deixa claro que isso inclui o módulo de tarefas pessoais. É preciso registrar essa interpretação como decisão de escopo.

## Dependências conferidas
A sequência Fase 1 → 2 → US1/US2 → US3 → US4 → US5 → gate integrado é coerente. A dependência US5 jira_sync → US4 está correta. As edições em `middleware.ts` (T022 e T030) e em `lib/db.ts` aparecem corretamente como serializadas.

Pela autorização recebida, a implementação não deve começar enquanto B1–B3 não forem corrigidos nos artefatos e revisados de novo.

— Claudinei
