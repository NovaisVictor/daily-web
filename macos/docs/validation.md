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
