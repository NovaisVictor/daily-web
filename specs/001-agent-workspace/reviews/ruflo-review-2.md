# Ruflo Review 2

Ruflo task: task-1792785743878-tq0uci. Executor: local Claude CLI.

# APPROVED

**Escopo da aprovação:** cobre só os artefatos enviados: constitution, spec, plan, data-model, os três contratos e tasks. `research.md`, `quickstart.md` e `checklists/requirements.md` são citados, mas não foram enviados, então não os revisei. Não executei nenhum teste, ferramenta ou consulta ao código; a revisão é só documental.

## Bloqueios da rodada 1 conferidos

Não recebi a lista original de B1–B3 e N1–N7. Conferi os temas que dá para identificar no texto atual:

- **Entrada de segredos só pelo navegador:** está registrada de forma consistente como exceção à paridade aprovada pelo usuário em `spec.md`, nos Objetivos, no FR-014 e nas Clarifications. Também aparece em `plan.md`, em `contracts/mcp-capabilities.md` (seção "Shared actions") e na T034.
- **Retenção pela última atividade:** fechada nos três pontos que poderiam vazar. Leituras e retries não renovam o prazo (FR-011). Cada activity expira individualmente. A reutilização de um `externalId` expirado é atômica e gera um novo id.
- **Recibos:** recibos de DELETE não guardam conteúdo. Recibos externos pendentes nunca expiram antes de reconciliar.
- **Backup e restore:** o restore revoga todas as credenciais e grants antes de abrir qualquer listener. Jobs de backup bruto passam a fazer parte do inventário (T001 e T009).
- **Seleção de conexão:** o `connectionId` é obrigatório e não há escolha implícita da primeira conexão (seção "Connection selection" do contrato MCP).
- **Handoff OAuth:** usa socket Unix com permissão 0600, nonce de uso único amarrado a client, resource, redirect, PKCE e scopes. A introspecção não tem cache positivo. O app é o único dono das migrations e o `busy_timeout` está explícito.
- **DCR (registro dinâmico de clientes):** tem limites definidos e não remove clientes já autorizados.
- **Polling:** fica explícito como o mecanismo que sustenta o SC-002.

Não encontrei nenhum bloqueio material restante.

## Defeitos de documento não bloqueantes (corrigir em edição)

1. **`spec.md` FR-013 × `contracts/oauth.md`:** o spec diz "MCP SHOULD use OAuth", mas o contrato e o plano exigem só bearer OAuth no `/mcp`. Trocar para MUST.
2. **`plan.md` Constitution Check:** a frase "user-approved exception is browser-only secret entry" logo antes de "No constitution exception requested" sugere que é uma exceção à constituição. Reescrever deixando claro que a exceção é à paridade do spec.
3. **`.specify/memory/constitution.md`:** o comentário de sync-impact traz "Remove this review note before committing". Remover antes do commit.
4. **T035 e o grupo `focus`:** criar um focus block é uma escrita em agenda externa, mas a T035 não cita recibos de mutação nem reconciliação de resultado incerto, como fazem a T007 e a T048. Acrescentar a referência.
5. **`connections` "enable/disable supported module"** (contrato MCP): não diz se o toggle é por usuário ou do deployment. Se for do deployment, não deve ficar acessível pelo MCP de um usuário. Precisa ser definido no inventário da T002.

## Gates empíricos futuros (não são defeitos de documento)

- **T011 e T038:** interoperabilidade OAuth real com Claude, Codex e Gemini, inclusive DCR ou cliente pré-registrado, atrás do proxy. Se o gate falhar, o trabalho de MCP que depende dele para.
- **T051:** p95/p99 de report até ficar visível com o perfil de 100 sessões, 20 usuários e 10 atualizações por segundo.
- **T002:** expansão do inventário de paridade em linhas concretas com fixtures de proveniência verificada. A paridade só pode ser declarada depois disso.
- **T009 e T052:** prova de que o restore não revive dados expirados e de que nada vaza por logs, caches ou backups.
- **T004:** checagem de colisão de versões de migration contra todas as branches remotas.

A implementação pode começar pela Phase 1, respeitando a ordem de gates do `tasks.md`.

— Claudinei
