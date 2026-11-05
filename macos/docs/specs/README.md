# Specs de paridade com o web

As specs desta pasta fecham as lacunas mapeadas em [../gaps.md](../gaps.md) depois
do primeiro uso real do app. Elas complementam o plano original
([../plan.md](../plan.md)); onde houver conflito, valem estas.

| Spec | Tema | Lacunas |
|---|---|---|
| [010](010-inicio-grade-e-abas.md) | Início: grade livre, modo Abas e disposição salva | H-1 a H-11, H-21 |
| [011](011-paineis-completos.md) | Painéis com o módulo inteiro dentro, e os modos compacto e tela cheia | H-12 a H-19, EM-1/2, NT-1 |
| [012](012-navegacao-e-paginas.md) | Navegação em pílula, Kanban, Ferramentas e Configuração | SH-1/5/7, KB-1 a 6, TL-1, CF-1 |
| [013](013-linguagem-visual.md) | Linguagem visual: vidro, Geist, pílulas, sombras e linhas | TH-1 a 8, CF-7, linhas de todos os módulos |
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

## Decisões que ficam com você

Cada decisão tem uma recomendação. Nenhuma spec avança antes da resposta.

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| DP-1 | Navegação principal | (a) Pílula no topo como no web (Início, Kanban, Ferramentas), sem barra lateral; (b) Pílula no topo **e** barra lateral recolhível com os módulos | **(a)**: é o que deixa o app igual ao web, e os módulos ficam nos painéis do Início, como lá |
| DP-2 | Disposição da grade | (a) Compartilhada com o web (mesmo `layouts` no servidor, por tamanho de janela); (b) Só no Mac | **(a)**: usa a API existente; a janela do Mac escolhe a disposição salva mais próxima do tamanho dela |
| DP-3 | Disposição do modo Abas | O web guarda só no navegador, então não há como compartilhar sem mudar o servidor | Guardar localmente no Mac (inevitável) |
| DP-4 | Fonte | (a) Embutir Geist Sans/Mono (OFL 1.1) e Patrick Hand; (b) Manter a fonte do sistema | **(a)**: a Patrick Hand precisa ter a licença confirmada antes |
| DP-5 | Vidro | (a) Material translúcido parecido com o do web (desfoque sobre o gradiente); (b) Liquid Glass do macOS 26 | **(a)** nos painéis, para ficar igual ao web; (b) só no cabeçalho |
| DP-6 | Novidades | (a) Fica de fora; (b) Proposta separada ao servidor (rota do changelog) | **(a)** agora; (b) junto das outras quatro limitações do servidor |
| DP-7 | Tela Hoje com painéis (código sem commit) | (a) Descartar e partir das specs; (b) Aproveitar como base da 011 | **(b)**: a lógica de linhas por aba e os testes servem para o modo compacto |

## Regras para os agentes

Valem as do [../../AGENTS.md](../../AGENTS.md). Para estas specs:

- **Fonte da verdade:** o comportamento e o texto vêm do componente web citado em
  cada requisito, nunca de memória.
- **Divergência só com motivo:** toda diferença em relação ao web precisa estar
  escrita na spec ou no [../validation.md](../validation.md).
- **Telas novas com preview:** cada tela ou painel novo tem preview com dados de
  exemplo, para a conferência visual não depender de servidor.
