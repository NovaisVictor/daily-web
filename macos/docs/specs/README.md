# Specs de paridade com o web

As specs desta pasta fecham as lacunas mapeadas em [../gaps.md](../gaps.md) depois
do primeiro uso real do app. Elas complementam o plano original
([../plan.md](../plan.md)); onde houver conflito, valem estas.

| Spec | Tema | Lacunas |
|---|---|---|
| [010](010-inicio-grade-e-abas.md) | Início: grade livre, modo Abas e disposição salva | H-1 a H-11, H-21 |
| [011](011-paineis-completos.md) | Painéis com o módulo inteiro dentro, e os modos compacto e tela cheia | H-12 a H-19, EM-1/2, NT-1 |
| [012](012-navegacao-e-paginas.md) | Navegação pela barra lateral, Kanban, Ferramentas e Configuração | SH-5/7, KB-1 a 6, TL-1, CF-1 (SH-1 não será reproduzida, DP-1) |
| [013](013-linguagem-visual.md) | Linguagem visual: Liquid Glass, Geist, pílulas, sombras e linhas | TH-1 a 8, CF-7, linhas de todos os módulos |
| [014](014-quadro-post-it.md) | Quadro de tarefas com o visual de post-it e o formulário | TK-1 a 17 |
| [015](015-ajustes-por-modulo.md) | Ajustes por módulo e estado lembrado | EM-3/9/16/19-21/30/31, NT-19/26, AG-2/5/6/14, JR-05, GH-01/04, SL-01/03, NF-02 |

## Ordem e dependências

```
Onda A   013 base visual (tokens, vidro, fonte, controles)  ─┐
         012 navegação e páginas  (depende dos controles da 013)
Onda B   011 painéis por módulo  (até 6 agentes em paralelo, um por módulo)
         014 quadro post-it       (em paralelo com a 011)
Onda C   010 grade e abas         (o motor de disposição pode começar na Onda B
                                    com painéis provisórios; a integração vem depois)
Onda D   015 ajustes por módulo + revisão independente + validação no app
```

Cada onda termina com o mesmo gate do plano original:

- `make check` passa;
- nada muda fora de `macos/`;
- revisão independente do diff.

Além disso, toda onda passa por uma **conferência visual feita por você**,
seguindo um roteiro curto. Não uso automação de interface.

## Decisões (tomadas em 2026-11-04)

| # | Decisão | Escolha |
|---|---|---|
| DP-1 | Navegação principal | **Barra lateral** (escolha do Victor). A pílula do topo do web não é reproduzida. A barra lateral ganha os itens principais do web (Início, Kanban, Ferramentas) acima dos módulos |
| DP-2 | Disposição da grade | Compartilhada com o web (mesmo `layouts` no servidor, por tamanho de janela) |
| DP-3 | Disposição do modo Abas | Guardada localmente no Mac (o web só a guarda no navegador) |
| DP-4 | Fonte | Embutir Geist Sans/Mono (OFL 1.1). Patrick Hand nos títulos do quadro, depois de confirmar a licença |
| DP-5 | Vidro | **Liquid Glass do macOS 26** (`glassEffect`), escolha do Victor, em vez de imitar o desfoque do web |
| DP-6 | Novidades | Fica de fora; vai para a proposta ao servidor |
| DP-7 | Tela Hoje com painéis (sem commit) | Aproveitada como base da 011 |

## Regras para os agentes

Valem as do [../../AGENTS.md](../../AGENTS.md). Para estas specs:

- **Fonte da verdade:** o comportamento e o texto vêm do componente web citado em
  cada requisito, nunca de memória.
- **Divergência só com motivo:** toda diferença em relação ao web precisa estar
  escrita na spec ou no [../validation.md](../validation.md).
- **Telas novas com preview:** cada tela ou painel novo tem preview com dados de
  exemplo, para a conferência visual não depender de servidor.
