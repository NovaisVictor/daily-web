'use client';

import { createContext, useCallback, useContext, useMemo, useRef, useState, useEffect } from 'react';
import { ArrowUpDown, CalendarPlus, ChevronRight, Flag, GitPullRequest, Plus, X } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { NavArrowRight } from 'iconoir-react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { useJiraPersonView } from '@/lib/hooks/useJiraPersonView';
import { isJiraAccountId } from '@/lib/jiraAccount';
import type {
  JiraDatedItem,
  JiraItem,
  JiraPerson,
  JiraPersonView,
  JiraProblemItem,
  PanelResult,
  PullRequestItem,
} from '@/lib/types';
import { pullsByJiraKey } from '@/lib/pullJira';
import { PanelError } from '@/components/data/PanelError';
import type { ActiveFilter } from '@/lib/filters';
import { JiraMultiFilterDropdown } from './JiraMultiFilterDropdown';
import { PersonSwitcher } from './jira/PersonSwitcher';
import {
  EMPTY_JIRA_FILTERS,
  JIRA_TIERS,
  JIRA_TIER_LABEL,
  activeJiraFilters,
  changeJiraFilter,
  clearJiraFilter,
  hasJiraFilters,
  isJiraFilterField,
  jiraFilterOptions,
  jiraFiltersToParams,
  matchesJiraFilters,
  parseJiraFilters,
  type JiraFilterState,
} from '@/lib/jiraFilters';
import {
  buildJiraTree,
  dueLabel,
  groupByStatusCategory,
  isOverdue,
  issueMarker,
  stalenessLabel,
} from '@/lib/parsers/jira';
import type { JiraNode, JiraNodeOrigin, JiraProjectGroup } from '@/lib/parsers/jira';
import { PROBLEM_LABEL } from '@/lib/parsers/jiraProblems';
import {
  JIRA_ORDER_DEFAULT,
  JIRA_ORDER_LABEL,
  JIRA_ORDER_PARAM,
  parseJiraOrder,
  sortJira,
  sortJiraTree,
  type JiraOrder,
} from '@/lib/jiraOrder';
import { JiraProblemFix } from './JiraProblemFix';
import { Section } from './ui/Section';
import { Tabs } from './ui/legacy-tabs';
import { FilterBar } from './ui/FilterBar';
import { SearchInput } from './ui/SearchInput';
import { Chip } from './ui/Chip';
import { ActiveFilters } from './ui/ActiveFilters';
import { FilterPopover, FilterPopoverSection } from './ui/FilterPopover';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from './ui/dropdown-menu';
import { EmptyState } from '@/components/data/EmptyState';
import { SkeletonRows } from './ui/legacy-skeleton';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { JiraStatus } from './data/JiraStatus';
import { cn } from '@/lib/utils';
import { focusRing, tabular } from '@/lib/theme';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import { JiraActionsProvider, type JiraViewer } from './jira/actions/context';
import { IssueActions } from './jira/IssueActions';
import { TransitionAction } from './jira/actions/TransitionAction';
import { ApprovalBadge } from './jira/actions/ApprovalAction';
import { FlagIndicator } from './jira/actions/FlagAction';
import { BulkStartDate } from './jira/actions/BulkStartDate';
import { StandupDialog } from './jira/StandupDialog';

/**
 * A panel that cannot reach its integration is information, not an alarm: the
 * message stays inside a quiet block with a side marker instead of loose red text
 * competing with the sections that did load.
 */

const emptyNote = 'py-8 text-sm text-ink-dim';

/** The group heading above a project or a situation bucket. */
const groupLabel = 'mb-2 block type-caption text-ink-dim';

const rowShell =
  'flex items-start gap-3 border-b border-line-soft py-3 transition-colors duration-100 ease-brand even:bg-muted/25 hover:bg-brand-tint motion-reduce:transition-none';

const caret =
  'inline-flex size-[18px] shrink-0 items-center justify-center rounded-md text-ink-dim transition-transform duration-100 ease-brand hover:bg-muted hover:text-ink aria-expanded:rotate-90 motion-reduce:transition-none';

const roleBadge =
  'inline-flex shrink-0 items-center rounded-full border px-1.5 py-0.5 type-caption';

type Filter = 'assignee' | 'both' | 'reporter';

const FILTER_LABEL: Record<Filter, string> = {
  assignee: 'Minhas',
  both: 'Ambas',
  reporter: 'Relator',
};

const FILTER_LABEL_PESSOA: Record<Filter, string> = {
  assignee: 'Responsável',
  both: 'Ambas',
  reporter: 'Relator',
};

/** As listas do painel. Não são recortes da mesma coleção: "Em aberto" é
 *  o que ainda pede trabalho, "Entregues" é o que saiu das suas mãos,
 *  "Aprovados" é o que passou por uma decisão sua e "Problemas" é o que está
 *  mal preenchido. */
const ABAS = ['abertas', 'entregues', 'aprovados', 'problemas'] as const;
type Aba = (typeof ABAS)[number];

// A aba vive na URL para sobreviver ao recarregar e ir junto num link. A
// padrão fica fora dela, e o valor que não for uma aba conhecida cai na padrão.
const ABA_PARAM = 'jira';
const ABA_PADRAO: Aba = 'abertas';

// A pessoa vive na URL para manter a aba ativa.
const PESSOA_PARAM = 'jiraPessoa';

// O papel também: um recorte que some ao recarregar não é recorte.
const PAPEL_PARAM = 'jiraPapel';

function parsePapel(value: string | null): Filter {
  return value === 'both' || value === 'reporter' ? value : 'assignee';
}

const VISTA_VAZIA: JiraPersonView = {
  jira: { data: [], error: null },
  delivered: { data: [], error: null },
  approved: { data: [], error: null },
  problems: { data: [], error: null },
  ancestors: [],
};

function parseAba(value: string | null): Aba {
  return ABAS.find((aba) => aba === value) ?? ABA_PADRAO;
}

/** O recorte de tempo das duas listas fechadas. As issues das duas já chegam
 *  cobrindo a semana, com a marca de quais são de hoje, então trocar aqui não
 *  vai ao servidor. */
type Periodo = 'hoje' | 'semana';

const PERIODO_LABEL: Record<Periodo, string> = {
  hoje: 'Hoje',
  semana: '7 dias',
};

interface Props {
  jira: PanelResult<JiraItem[]>;
  /** Issues acompanhadas por escolha, mesmo não sendo suas. */
  watched: PanelResult<JiraItem[]>;
  /** Issues que você encerrou nos últimos sete dias. */
  delivered: PanelResult<JiraDatedItem[]>;
  /** Issues que você aprovou nos últimos sete dias. */
  approved: PanelResult<JiraDatedItem[]>;
  /** Histórias e épicos com defeito de preenchimento. */
  problems: PanelResult<JiraProblemItem[]>;
  /** Os pais das issues acima, até o objetivo. Não são suas: ligam o que é
   *  seu ao topo da hierarquia. */
  ancestors: JiraItem[];
  people: JiraPerson[];
  refreshedAt: string | null;
  onChanged: () => void;
  loading?: boolean;
  /** Os PRs do painel do GitHub. Os que citam uma issue aparecem sob ela. */
  pulls?: PullRequestItem[];
  /** Os seus PRs abertos, de qualquer repositório, para o resumo da daily. */
  myPulls?: PullRequestItem[];
}

const SEM_PRS = new Map<string, PullRequestItem[]>();

// As linhas ficam três componentes abaixo do painel; o contexto evita passar
// os PRs por cada um deles só para chegar à linha.
const JiraPullsContext = createContext<Map<string, PullRequestItem[]>>(SEM_PRS);

/** Os PRs que citam a issue, cada um com o link para o GitHub. */
function JiraPullLinks({ issueKey }: { issueKey: string }) {
  const pulls = useContext(JiraPullsContext).get(issueKey);
  if (!pulls?.length) return null;
  return (
    <ul className="flex flex-col gap-0.5 pt-0.5" aria-label={`PRs de ${issueKey}`}>
      {pulls.map((pr) => (
        <li key={pr.url} className="min-w-0">
          <a
            className={cn(
              'flex min-w-0 items-center gap-1.5 type-caption text-ink-dim hover:text-ink hover:underline',
              focusRing,
            )}
            href={pr.url}
            target="_blank"
            rel="noreferrer"
          >
            <GitPullRequest className="size-3.5 shrink-0" aria-hidden />
            <span className={cn('shrink-0', tabular)}>
              {pr.repo}#{pr.number}
            </span>
            <span className="min-w-0 truncate">{pr.title}</span>
          </a>
        </li>
      ))}
    </ul>
  );
}

export function JiraPanel({
  jira: meJira,
  watched,
  delivered: meDelivered,
  approved: meApproved,
  problems: meProblems,
  ancestors: meAncestors,
  people,
  refreshedAt,
  onChanged,
  loading: meLoading = false,
  pulls,
  myPulls,
}: Props) {
  const prsPorChave = useMemo(() => (pulls ? pullsByJiraKey(pulls) : SEM_PRS), [pulls]);
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  const rawPessoa = searchParams.get(PESSOA_PARAM);
  const pessoaAtiva =
    rawPessoa && isJiraAccountId(rawPessoa) && people.some((p) => p.accountId === rawPessoa)
      ? rawPessoa
      : null;
  const pessoaAtivaObj = pessoaAtiva ? people.find((p) => p.accountId === pessoaAtiva) : null;

  // Os filtros são da lista de quem está sendo olhado: trocar de pessoa
  // começa limpo, na mesma navegação, para o voltar desfazer as duas coisas.
  const setPessoa = (next: string) => {
    const params = jiraFiltersToParams(searchParams, EMPTY_JIRA_FILTERS);
    params.delete(PAPEL_PARAM);
    const removing = next === 'eu';
    if (removing) params.delete(PESSOA_PARAM);
    else params.set(PESSOA_PARAM, next);
    const query = params.toString();
    const dest = query ? `${pathname}?${query}` : pathname;
    if (removing) {
      router.replace(dest, { scroll: false });
    } else {
      router.push(dest, { scroll: false });
    }

    setRamos(new Map());
  };

  const {
    view,
    loading: personLoading,
    error: personError,
  } = useJiraPersonView(pessoaAtiva, refreshedAt);

  const fonte = pessoaAtiva
    ? (view ?? VISTA_VAZIA)
    : {
        jira: meJira,
        delivered: meDelivered,
        approved: meApproved,
        problems: meProblems,
        ancestors: meAncestors,
      };

  const jira = fonte.jira;
  const delivered = fonte.delivered;
  const approved = fonte.approved;
  const problems = fonte.problems;
  const loading = pessoaAtiva ? personLoading : meLoading;

  const aba = parseAba(searchParams.get(ABA_PARAM));
  // Trocar de aba é navegação: entra no histórico, e o voltar desfaz.
  const setAba = (next: Aba) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === ABA_PADRAO) params.delete(ABA_PARAM);
    else params.set(ABA_PARAM, next);
    const query = params.toString();
    router.push(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };
  const [periodo, setPeriodo] = useState<Periodo>('hoje');
  const [novaChave, setNovaChave] = useState('');
  const [watchError, setWatchError] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const [removendo, setRemovendo] = useState<Set<string>>(new Set());
  // Ramos que o usuário abriu ou fechou na mão, pela chave da issue. O que
  // não está aqui segue o padrão do nó: o caminho até o objetivo nasce
  // aberto, porque esconder o trabalho atrás dele seria pior que a lista
  // plana de antes; o que é da pessoa nasce fechado, como as subtarefas.
  const [ramos, setRamos] = useState<Map<string, boolean>>(new Map());

  const [formAberta, setFormAberta] = useState(false);
  const campoBuscaPessoa = useRef<HTMLInputElement>(null);
  const [buscaNovaPessoa, setBuscaNovaPessoa] = useState('');
  const [resultadosPessoas, setResultadosPessoas] = useState<JiraPerson[]>([]);
  const [buscandoPessoas, setBuscandoPessoas] = useState(false);
  const [erroPessoas, setErroPessoas] = useState<string | null>(null);

  const alternarRamo = (chave: string, aberto: boolean) => {
    setRamos((prev) => new Map(prev).set(chave, aberto));
  };

  // O servidor é a verdade; `removendo` só antecipa a saída da lista até a
  // próxima resposta chegar sem a chave.
  const acompanhadas = useMemo(
    () => (watched.data ?? []).filter((i) => !removendo.has(i.key)),
    [watched.data, removendo],
  );

  const acompanhar = async () => {
    const chave = novaChave.trim().toUpperCase();
    if (!chave || salvando) return;
    setSalvando(true);
    const res = await fetch('/api/jira/watch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key: chave }),
    });
    setSalvando(false);
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      setWatchError(data.error ?? 'Falha ao acompanhar');
      return;
    }
    setWatchError(null);
    setNovaChave('');
    onChanged();
  };

  const parar = async (chave: string) => {
    // Sai da lista na hora. Esperar o `onChanged` significaria esperar o Jira
    // responder de novo — segundos para uma decisão que é toda local.
    setRemovendo((prev) => new Set(prev).add(chave));
    const res = await fetch('/api/jira/watch', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key: chave }),
    });
    if (!res.ok) {
      setRemovendo((prev) => {
        const next = new Set(prev);
        next.delete(chave);
        return next;
      });
      setWatchError('Falha ao remover do acompanhamento');
      return;
    }
    setWatchError(null);
    onChanged();
  };

  const acompanharPessoa = async (accountId: string) => {
    setFormAberta(false);
    setBuscaNovaPessoa('');
    setResultadosPessoas([]);
    setErroPessoas(null);
    const res = await fetch('/api/jira/people', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ accountId }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setErroPessoas(body.error || 'Falha ao acompanhar pessoa');
      return;
    }
    onChanged();
    setPessoa(accountId);
  };

  const pararPessoa = async (accountId: string) => {
    const res = await fetch('/api/jira/people', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ accountId }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setErroPessoas(body.error || 'Falha ao remover pessoa');
      return;
    }
    if (pessoaAtiva === accountId) setPessoa('eu');
    onChanged();
  };

  useEffect(() => {
    if (!formAberta) return;
    const q = buscaNovaPessoa.trim();
    if (q.length < 2) {
      setResultadosPessoas([]);
      setErroPessoas(null);
      return;
    }

    setBuscandoPessoas(true);
    setErroPessoas(null);
    const ac = new AbortController();

    const handler = setTimeout(async () => {
      try {
        const res = await fetch(`/api/jira/people/search?q=${encodeURIComponent(q)}`, {
          signal: ac.signal,
        });
        if (!res.ok) {
          const body = await res.json().catch(() => ({}));
          throw new Error(body.error || `Erro ${res.status}`);
        }
        const data = await res.json();
        setResultadosPessoas(data.people || []);
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') return;
        setErroPessoas(err instanceof Error ? err.message : String(err));
      } finally {
        setBuscandoPessoas(false);
      }
    }, 300);

    return () => {
      clearTimeout(handler);
      ac.abort();
    };
  }, [buscaNovaPessoa, formAberta]);

  const filtros = useMemo(() => parseJiraFilters(searchParams), [searchParams]);
  const filter = parsePapel(searchParams.get(PAPEL_PARAM));

  // Mexer num filtro não é navegação: substitui a URL em vez de empilhar,
  // para o voltar não refazer cada tecla da busca.
  const trocarUrl = (params: URLSearchParams) => {
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, {
      scroll: false,
    });
  };
  const setFiltros = (next: Partial<JiraFilterState>) =>
    trocarUrl(jiraFiltersToParams(searchParams, { ...filtros, ...next }));
  const setFilter = (next: Filter) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === 'assignee') params.delete(PAPEL_PARAM);
    else params.set(PAPEL_PARAM, next);
    trocarUrl(params);
  };
  const ordem = parseJiraOrder(searchParams.get(JIRA_ORDER_PARAM));
  const setOrdem = (next: JiraOrder) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === JIRA_ORDER_DEFAULT) params.delete(JIRA_ORDER_PARAM);
    else params.set(JIRA_ORDER_PARAM, next);
    trocarUrl(params);
  };
  const [grouped, setGrouped] = useState(false);

  const all = useMemo(() => jira.data ?? [], [jira.data]);

  // O caminho até o objetivo não é do usuário e por isso não entra em
  // `visible`: ele não é filtrado por papel nem por busca, só liga o que foi
  // filtrado ao topo da hierarquia.
  const ancestors = fonte.ancestors;

  // Tudo o que se conhece de cada issue, para subir dela até a iniciativa:
  // é o que o filtro de hierarquia e a busca pelo caminho precisam.
  const conhecidas = useMemo(
    () =>
      new Map(
        [
          ...ancestors,
          ...(delivered.data ?? []),
          ...(approved.data ?? []),
          ...(problems.data ?? []),
          ...all,
        ].map((i) => [i.key, i]),
      ),
    [ancestors, delivered.data, approved.data, problems.data, all],
  );
  // O caminho de cada árvore sai de tudo o que se conhece, não só dos
  // ancestrais buscados: o servidor não busca de novo o que já está numa
  // lista, então o épico que é seu em aberto não vem como ancestral da
  // história que você entregou. O que não liga a nada da aba é podado.
  const caminho = useMemo(() => [...conhecidas.values()], [conhecidas]);

  const recortar = useCallback(
    <T extends JiraItem>(itens: T[]): T[] =>
      itens.filter((i) => matchesJiraFilters(i, filtros, conhecidas)),
    [filtros, conhecidas],
  );

  // Uma issue com papel 'both' é genuinamente das duas naturezas: aparece
  // tanto em "minhas" quanto em "relator". O que espera pela sua aprovação
  // atravessa o filtro: aprovar não é um dos papéis, e escondê-la ao recortar
  // por responsável ou relator tiraria da tela justamente o que pede decisão.
  const visible = useMemo(
    () =>
      recortar(all).filter(
        (i) => filter === 'both' || i.role === filter || i.role === 'both' || i.awaitingApproval,
      ),
    [all, recortar, filter],
  );

  const projects = useMemo(
    () => sortJiraTree(buildJiraTree(visible, caminho), ordem),
    [visible, caminho, ordem],
  );
  const situations = useMemo(
    () => groupByStatusCategory(sortJira(visible, ordem)),
    [visible, ordem],
  );

  // Entregues e Aprovados repetem a estrutura de "Em aberto": hierarquia,
  // separada por projeto, para DAD e PDS não se misturarem só porque saíram no
  // mesmo dia. O período recorta as duas ao mesmo tempo — são a mesma pergunta
  // feita sobre dois acontecimentos.
  const noPeriodo = useCallback(
    (itens: JiraDatedItem[]) => (periodo === 'hoje' ? itens.filter((i) => i.today) : itens),
    [periodo],
  );

  const noPeriodoEntregues = useMemo(
    () => noPeriodo(delivered.data ?? []),
    [delivered.data, noPeriodo],
  );
  const entregues = useMemo(() => recortar(noPeriodoEntregues), [noPeriodoEntregues, recortar]);
  const entreguesProjects = useMemo(
    () => sortJiraTree(buildJiraTree(entregues, caminho), ordem),
    [entregues, caminho, ordem],
  );

  const noPeriodoAprovados = useMemo(
    () => noPeriodo(approved.data ?? []),
    [approved.data, noPeriodo],
  );
  const aprovados = useMemo(() => recortar(noPeriodoAprovados), [noPeriodoAprovados, recortar]);
  const aprovadosProjects = useMemo(
    () => sortJiraTree(buildJiraTree(aprovados, caminho), ordem),
    [aprovados, caminho, ordem],
  );

  const problemas = useMemo(
    () => sortJira(recortar(problems.data ?? []), ordem),
    [problems.data, recortar, ordem],
  );

  // As opções falam da aba aberta, antes do recorte: o seletor de status
  // mostra os status desta lista, não os de outra aba.
  const baseDaAba: JiraItem[] =
    aba === 'entregues'
      ? noPeriodoEntregues
      : aba === 'aprovados'
        ? noPeriodoAprovados
        : aba === 'problemas'
          ? (problems.data ?? [])
          : all;
  const opcoes = jiraFilterOptions(baseDaAba, conhecidas, filtros);

  const rotuloDe = (chave: string) => {
    const issue = conhecidas.get(chave);
    return issue ? `${chave} ${issue.summary}` : chave;
  };
  const issueOption = (item: JiraItem) => ({
    value: item.key,
    label: rotuloDe(item.key),
    secondary: item.key,
  });

  const activeFilters: ActiveFilter[] = [
    ...activeJiraFilters(filtros, rotuloDe),
    ...(aba === 'abertas' && filter !== 'assignee'
      ? [
          {
            id: 'role',
            label: pessoaAtiva ? FILTER_LABEL_PESSOA[filter] : FILTER_LABEL[filter],
          },
        ]
      : []),
  ];

  // The search stays in plain sight, so the badge counts only what the panel
  // hides. Display is left out: it narrows nothing, and the list itself shows
  // which view is on.
  const secondaryCount = activeFilters.filter((f) => f.id !== 'query').length;

  const clearFilter = (id: string) => {
    if (id === 'role') return setFilter('assignee');
    if (id === 'query' || isJiraFilterField(id)) setFiltros(clearJiraFilter(id));
  };

  const clearAll = () => {
    const params = jiraFiltersToParams(searchParams, EMPTY_JIRA_FILTERS);
    params.delete(PAPEL_PARAM);
    trocarUrl(params);
  };

  const filtrando = hasJiraFilters(filtros);
  // Com filtro, o que casou é o que se quer ver: a árvore abre inteira em vez
  // de esconder o resultado num ramo fechado.
  const abertura: Abertura = filtrando ? 'tudo' : 'caminho';

  const nome = pessoaAtivaObj?.displayName.split(' ')[0] ?? '';
  const viewer: JiraViewer = pessoaAtivaObj
    ? { kind: 'person', name: pessoaAtivaObj.displayName }
    : { kind: 'self' };

  return (
    <JiraActionsProvider value={{ viewer, onChanged }}>
      <JiraPullsContext.Provider value={prsPorChave}>
        <Section
          eyebrow={
            <PersonSwitcher
              people={people}
              active={pessoaAtivaObj ?? null}
              onSelect={setPessoa}
              onFollow={() => setFormAberta(true)}
              searchField={campoBuscaPessoa}
              onUnfollow={(accountId) => void pararPessoa(accountId)}
            />
          }
          count={
            aba === 'abertas' && activeFilters.length > 0
              ? `${visible.length} de ${all.length}`
              : undefined
          }
          actions={
            pessoaAtiva ? undefined : (
              <StandupDialog
                source={{
                  open: meJira.data ?? [],
                  delivered: meDelivered.data ?? [],
                  approved: meApproved.data ?? [],
                  myPulls: myPulls ?? [],
                }}
              />
            )
          }
        >
          {formAberta && (
            <div className="mb-4 rounded-lg border border-line-soft bg-muted/30 p-4">
              {/* The menu that opens this card closes on choosing it, so this
                  is the only way out besides Escape inside the field. */}
              <div className="flex items-center gap-2">
                <Input
                  ref={campoBuscaPessoa}
                  autoFocus
                  aria-label="buscar pessoa no Jira"
                  placeholder="nome da pessoa"
                  value={buscaNovaPessoa}
                  onChange={(e) => setBuscaNovaPessoa(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') setFormAberta(false);
                  }}
                />
                <IconAction
                  label="fechar busca de pessoa"
                  onClick={() => setFormAberta(false)}
                  icon={<X className="size-4" />}
                />
              </div>
              {erroPessoas && <PanelError>{erroPessoas}</PanelError>}
              {buscandoPessoas && <p className="mt-2 text-sm text-ink-dim">Buscando…</p>}
              {!buscandoPessoas && resultadosPessoas.length > 0 && (
                <ul className="mt-2 flex flex-wrap gap-2">
                  {resultadosPessoas.map((p) => {
                    if (people.some((fp) => fp.accountId === p.accountId)) return null;
                    return (
                      <li key={p.accountId}>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => void acompanharPessoa(p.accountId)}
                        >
                          {p.displayName}
                        </Button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          )}

          {personError && pessoaAtiva && <PanelError>{personError}</PanelError>}

          <div className="flex flex-wrap items-start justify-between gap-x-3">
            <Tabs
              id="jira"
              label="listas do Jira"
              active={aba}
              onChange={(id) => setAba(parseAba(id))}
              tabs={[
                { id: 'abertas', label: 'Em aberto', count: all.length },
                {
                  id: 'entregues',
                  label: 'Entregues',
                  count: entregues.length,
                },
                {
                  id: 'aprovados',
                  label: 'Aprovados',
                  count: aprovados.length,
                },
                {
                  id: 'problemas',
                  label: 'Problemas',
                  count: problemas.length,
                },
              ]}
            />
          </div>

          {/* O período pertence às duas listas fechadas, e não a uma delas: ficar
          fora do painel da aba evita duas barras iguais e mantém o recorte
          visível ao trocar de aba. */}
          {(aba === 'entregues' || aba === 'aprovados') && (
            <FilterBar label="Período">
              {(Object.keys(PERIODO_LABEL) as Periodo[]).map((p) => (
                <Chip key={p} active={periodo === p} onClick={() => setPeriodo(p)}>
                  {PERIODO_LABEL[p]}
                </Chip>
              ))}
            </FilterBar>
          )}

          <FilterBar label="Filtrar o Jira">
            <SearchInput
              value={filtros.query}
              onChange={(query) => setFiltros({ query })}
              label="buscar issues"
              placeholder="chave ou resumo, até do épico"
            />
            <FilterPopover label="filtros do Jira" count={secondaryCount}>
              {/* Role and display only apply to "Em aberto". */}
              {aba === 'abertas' && (
                <>
                  <FilterPopoverSection title="Papel">
                    {(Object.keys(FILTER_LABEL) as Filter[]).map((f) => (
                      <Chip key={f} active={filter === f} onClick={() => setFilter(f)}>
                        {pessoaAtiva ? FILTER_LABEL_PESSOA[f] : FILTER_LABEL[f]}
                      </Chip>
                    ))}
                  </FilterPopoverSection>
                  <FilterPopoverSection title="Exibição">
                    <Chip active={!grouped} onClick={() => setGrouped((g) => !g)}>
                      {grouped ? 'Lista simples' : 'Hierarquia'}
                    </Chip>
                  </FilterPopoverSection>
                </>
              )}
              <FilterPopoverSection title="Status">
                <JiraMultiFilterDropdown
                  label="filtrar por status"
                  title="Filtrar por Status"
                  placeholder="Status"
                  name="Status"
                  filter={filtros.status}
                  options={opcoes.statuses.map((status) => ({
                    value: status,
                    label: status,
                  }))}
                  onChange={(status) => setFiltros({ status })}
                />
              </FilterPopoverSection>
              <FilterPopoverSection title="Tipo">
                <JiraMultiFilterDropdown
                  label="filtrar por tipo"
                  title="Filtrar por Tipo"
                  placeholder="Tipo"
                  name="Tipo"
                  filter={filtros.tier}
                  options={JIRA_TIERS.map((tier) => ({
                    value: tier,
                    label: JIRA_TIER_LABEL[tier],
                  }))}
                  onChange={(tier) => setFiltros({ tier })}
                />
              </FilterPopoverSection>
              <FilterPopoverSection title="Hierarquia">
                {/* Os três degraus descem em cascata, e a seta diz isso: cada um
                recorta as opções do seguinte. */}
                <div
                  role="group"
                  aria-label="hierarquia do Jira"
                  className="inline-flex max-w-full flex-wrap items-center gap-0.5"
                >
                  <JiraMultiFilterDropdown
                    label="filtrar por iniciativa"
                    title="Filtrar por Iniciativa"
                    placeholder="Iniciativa"
                    name="Iniciativa"
                    filter={filtros.initiative}
                    options={opcoes.initiatives.map(issueOption)}
                    formatLabel={rotuloDe}
                    onChange={(initiative) =>
                      setFiltros(changeJiraFilter(filtros, 'initiative', initiative))
                    }
                  />
                  <ChevronRight aria-hidden className="size-3.5 shrink-0 text-ink-dim" />
                  <JiraMultiFilterDropdown
                    label="filtrar por épico"
                    title="Filtrar por Épico"
                    placeholder="Épico"
                    name="Épico"
                    filter={filtros.epic}
                    options={opcoes.epics.map(issueOption)}
                    formatLabel={rotuloDe}
                    onChange={(epic) => setFiltros(changeJiraFilter(filtros, 'epic', epic))}
                  />
                  <ChevronRight aria-hidden className="size-3.5 shrink-0 text-ink-dim" />
                  <JiraMultiFilterDropdown
                    label="filtrar por história"
                    title="Filtrar por História"
                    placeholder="História"
                    name="História"
                    filter={filtros.story}
                    options={opcoes.stories.map(issueOption)}
                    formatLabel={rotuloDe}
                    onChange={(story) => setFiltros({ story })}
                  />
                </div>
              </FilterPopoverSection>
            </FilterPopover>
            <DropdownMenu>
              <DropdownMenuTrigger
                aria-label={`Ordenar: ${JIRA_ORDER_LABEL[ordem]}`}
                title={`Ordenar: ${JIRA_ORDER_LABEL[ordem]}`}
                className={cn(
                  'inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-line-strong bg-surface-2 text-ink-mid shadow-e1 transition-colors duration-100 ease-brand hover:bg-accent hover:text-accent-foreground motion-reduce:transition-none',
                  focusRing,
                )}
              >
                <ArrowUpDown aria-hidden className="size-4" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuLabel>Ordenar por</DropdownMenuLabel>
                <DropdownMenuRadioGroup
                  value={ordem}
                  onValueChange={(value) => setOrdem(parseJiraOrder(value))}
                >
                  {(Object.keys(JIRA_ORDER_LABEL) as JiraOrder[]).map((o) => (
                    <DropdownMenuRadioItem key={o} value={o}>
                      {JIRA_ORDER_LABEL[o]}
                    </DropdownMenuRadioItem>
                  ))}
                </DropdownMenuRadioGroup>
              </DropdownMenuContent>
            </DropdownMenu>
          </FilterBar>

          <ActiveFilters filters={activeFilters} onRemove={clearFilter} onClearAll={clearAll} />

          {aba === 'entregues' && (
            <div id="jira-panel-entregues" role="tabpanel" aria-labelledby="jira-tab-entregues">
              {delivered.error && <PanelError>{delivered.error}</PanelError>}

              {loading && entregues.length === 0 && <SkeletonRows count={3} />}

              {filtrando && noPeriodoEntregues.length > 0 && entregues.length === 0 && (
                <EmptyState title="Nenhuma issue com esses filtros." />
              )}

              {!loading && noPeriodoEntregues.length === 0 && !delivered.error && (
                <EmptyState
                  title={
                    pessoaAtivaObj
                      ? periodo === 'hoje'
                        ? `Nenhuma issue entregue por ${nome} hoje.`
                        : `Nenhuma issue entregue por ${nome} nos últimos 7 dias.`
                      : periodo === 'hoje'
                        ? 'Nenhuma issue entregue hoje.'
                        : 'Nenhuma issue entregue nos últimos 7 dias.'
                  }
                />
              )}

              <JiraProjects
                groups={entreguesProjects}
                ramos={ramos}
                abertura={abertura}
                onAlternar={alternarRamo}
                pessoaNome={nome}
              />
            </div>
          )}

          {aba === 'aprovados' && (
            <div id="jira-panel-aprovados" role="tabpanel" aria-labelledby="jira-tab-aprovados">
              {approved.error && <PanelError>{approved.error}</PanelError>}

              {loading && aprovados.length === 0 && <SkeletonRows count={3} />}

              {filtrando && noPeriodoAprovados.length > 0 && aprovados.length === 0 && (
                <EmptyState title="Nenhuma issue com esses filtros." />
              )}

              {!loading && noPeriodoAprovados.length === 0 && !approved.error && (
                <EmptyState
                  title={
                    pessoaAtivaObj
                      ? periodo === 'hoje'
                        ? `Nenhuma issue aprovada por ${nome} hoje.`
                        : `Nenhuma issue aprovada por ${nome} nos últimos 7 dias.`
                      : periodo === 'hoje'
                        ? 'Nenhuma issue aprovada hoje.'
                        : 'Nenhuma issue aprovada nos últimos 7 dias.'
                  }
                />
              )}

              <JiraProjects
                groups={aprovadosProjects}
                ramos={ramos}
                abertura={abertura}
                onAlternar={alternarRamo}
                pessoaNome={nome}
              />
            </div>
          )}

          {aba === 'problemas' && (
            <div id="jira-panel-problemas" role="tabpanel" aria-labelledby="jira-tab-problemas">
              {problems.error && <PanelError>{problems.error}</PanelError>}

              {loading && problemas.length === 0 && <SkeletonRows count={3} />}

              {filtrando && (problems.data ?? []).length > 0 && problemas.length === 0 && (
                <EmptyState title="Nenhuma issue com esses filtros." />
              )}

              {!loading && (problems.data ?? []).length === 0 && !problems.error && (
                <EmptyState
                  title={
                    pessoaAtivaObj
                      ? `Nenhuma história ou épico de ${nome} com problema.`
                      : 'Nenhuma história ou épico com problema.'
                  }
                />
              )}

              <BulkStartDate problems={problemas} />

              <ul>
                {problemas.map((issue) => (
                  <JiraProblemRow key={issue.key} issue={issue} onFixed={onChanged} />
                ))}
              </ul>
            </div>
          )}

          {aba === 'abertas' && (
            <div id="jira-panel-abertas" role="tabpanel" aria-labelledby="jira-tab-abertas">
              {/* Acompanhar uma issue que não é sua: o Jira do time vizinho que trava
              o seu, ou o que você abriu para outra pessoa. */}
              {!pessoaAtiva && (
                <div className="mb-4 border-b border-line-soft pb-4">
                  <h3 className={groupLabel}>
                    Acompanhando
                    {acompanhadas.length > 0 && (
                      <span className={cn('font-normal text-ink-dim', tabular)}>
                        {' '}
                        {acompanhadas.length}
                      </span>
                    )}
                  </h3>

                  <div className="my-2 flex gap-2">
                    <Input
                      className="max-w-48"
                      aria-label="acompanhar issue do Jira"
                      placeholder="ABC-123"
                      value={novaChave}
                      onChange={(e) => setNovaChave(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') void acompanhar();
                      }}
                    />
                    <IconAction
                      variant="outline"
                      size="icon"
                      label={salvando ? 'Buscando…' : 'Acompanhar issue'}
                      disabled={salvando || novaChave.trim().length === 0}
                      onClick={() => void acompanhar()}
                      icon={<Plus className={cn('size-4', salvando && 'animate-pulse')} />}
                    />
                  </div>

                  {watchError && <PanelError>{watchError}</PanelError>}
                  {watched.error && <PanelError>{watched.error}</PanelError>}

                  {acompanhadas.length === 0 && !watchError && (
                    <p className={emptyNote}>Nenhuma issue acompanhada.</p>
                  )}

                  <ul>
                    {acompanhadas.map((issue) => (
                      <li key={issue.key} className={rowShell}>
                        <span className="shrink-0 type-caption leading-6 text-ink-dim">
                          {issueMarker(issue)}
                        </span>
                        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                          <div className="flex min-w-0 items-baseline gap-3">
                            <a
                              className={cn(
                                'shrink-0 font-mono text-sm text-brand hover:underline',
                                focusRing,
                              )}
                              href={issue.url}
                              target="_blank"
                              rel="noreferrer"
                            >
                              {issue.key}
                            </a>
                            <span
                              className={cn(
                                'min-w-0 flex-1 truncate',
                                origin === 'ancestor' ? 'text-ink-dim' : 'text-ink',
                              )}
                            >
                              {issue.summary}
                            </span>
                          </div>
                          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 type-caption text-ink-dim">
                            <JiraStatus issue={issue} />
                            {stalenessLabel(issue) && (
                              <span className="whitespace-nowrap text-warning">
                                {stalenessLabel(issue)}
                              </span>
                            )}
                            {issue.dueDate && dueLabel(issue.dueDate) && (
                              <span
                                className={cn(
                                  'whitespace-nowrap',
                                  isOverdue(issue.dueDate)
                                    ? 'is-overdue text-danger'
                                    : 'text-ink-dim',
                                )}
                              >
                                {dueLabel(issue.dueDate)}
                              </span>
                            )}
                          </div>
                        </div>
                        <IconAction
                          className="shrink-0 text-ink-dim hover:bg-danger-tint hover:text-danger"
                          label={`parar de acompanhar ${issue.key}`}
                          onClick={() => void parar(issue.key)}
                          icon={<X className="size-4" />}
                        />
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {jira.error && <PanelError>{jira.error}</PanelError>}

              {loading && all.length === 0 && <SkeletonRows count={5} />}

              {!loading && all.length === 0 && !jira.error && (
                <EmptyState
                  title={
                    pessoaAtivaObj
                      ? `Nenhuma issue atribuída a ${nome}.`
                      : 'Nenhuma issue atribuída.'
                  }
                />
              )}

              {all.length > 0 && visible.length === 0 && (
                <EmptyState title="Nenhuma issue com esses filtros." />
              )}

              {grouped &&
                visible.length > 0 &&
                situations.map((group) => (
                  <div key={group.category} className="mt-5 first:mt-0">
                    <h3 className={groupLabel}>
                      {group.label}
                      <span className={cn('font-normal text-ink-dim', tabular)}>
                        {' '}
                        {group.issues.length}
                      </span>
                    </h3>
                    <ul>
                      {group.issues.map((issue) => (
                        <JiraRow
                          key={issue.key}
                          issue={issue}
                          showRole={filter === 'both'}
                          depth={0}
                          pessoaNome={nome}
                        />
                      ))}
                    </ul>
                  </div>
                ))}

              {!grouped && visible.length > 0 && (
                <JiraProjects
                  groups={projects}
                  showRole={filter === 'both'}
                  ramos={ramos}
                  abertura={abertura}
                  onAlternar={alternarRamo}
                  pessoaNome={nome}
                />
              )}
            </div>
          )}
        </Section>
      </JiraPullsContext.Provider>
    </JiraActionsProvider>
  );
}

/** A bandeira vermelha do Jira: a issue está impedida. É a marca que mais pede
 *  atenção na linha, então fica colada à chave. */
function JiraFlagMark({ issue }: { issue: JiraItem }) {
  if (issue.flag !== 'impediment') return null;
  return (
    <span className="inline-flex shrink-0 self-center text-danger" title="impedimento">
      <Flag className="size-3.5 fill-current" aria-hidden />
      <span className="sr-only">impedimento</span>
    </span>
  );
}

// Só as duas mais altas ganham cor: pintar todas faria a "Média" de quase
// toda issue competir com a "Crítica" que importa.
const PRIORITY_TONE = ['text-danger', 'text-warning'];

function JiraPriorityLabel({ issue }: { issue: JiraItem }) {
  if (!issue.priority) return null;
  const tone = issue.priority.rank === null ? undefined : PRIORITY_TONE[issue.priority.rank];
  return (
    <span className={cn('whitespace-nowrap', tone ?? 'text-ink-dim')} title="prioridade">
      {issue.priority.name}
    </span>
  );
}

/** Uma issue da aba de problemas: o que ela é e tudo o que está faltando nela,
 *  para corrigir de uma vez ao abrir no Jira. */
function JiraProblemRow({ issue, onFixed }: { issue: JiraProblemItem; onFixed: () => void }) {
  return (
    <li className={rowShell}>
      <span className="shrink-0 type-caption leading-6 text-ink-dim">{issueMarker(issue)}</span>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex min-w-0 items-baseline gap-3">
          <a
            className={cn('shrink-0 font-mono text-sm text-brand hover:underline', focusRing)}
            href={issue.url}
            target="_blank"
            rel="noreferrer"
          >
            {issue.key}
          </a>
          <FlagIndicator issue={issue} />
          <span
            className={cn(
              'min-w-0 flex-1 truncate',
              origin === 'ancestor' ? 'text-ink-dim' : 'text-ink',
            )}
          >
            {issue.summary}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 type-caption text-ink-dim">
          <TransitionAction issue={issue}>
            <JiraStatus issue={issue} />
          </TransitionAction>
          <JiraPriorityLabel issue={issue} />
          <ul className="contents" aria-label={`problemas de ${issue.key}`}>
            {issue.problems.map((problem) => (
              <li
                key={problem}
                className={cn(roleBadge, 'border-warning/45 bg-warning-tint text-warning')}
              >
                {PROBLEM_LABEL[problem]}
              </li>
            ))}
          </ul>
        </div>
        <JiraPullLinks issueKey={issue.key} />
        <JiraProblemFix issue={issue} onFixed={onFixed} />
      </div>
      <IssueActions issue={issue} />
    </li>
  );
}

/** O que nasce aberto na árvore, até o usuário abrir ou fechar na mão: só o
 *  caminho até o objetivo, ou tudo, quando um filtro já escolheu o que ver. */
type Abertura = 'caminho' | 'tudo';

/** A hierarquia por projeto: um bloco por projeto, e dentro dele a árvore de
 *  pais e filhas. É o que as duas abas têm em comum. */
function JiraProjects({
  groups,
  showRole = false,
  ramos,
  abertura,
  onAlternar,
  pessoaNome,
}: {
  groups: JiraProjectGroup[];
  showRole?: boolean;
  ramos: Map<string, boolean>;
  abertura: Abertura;
  onAlternar: (chave: string, aberto: boolean) => void;
  pessoaNome?: string;
}) {
  return (
    <>
      {groups.map((group) => (
        <div key={group.project} className="mt-5 first:mt-0">
          <h3 className={groupLabel}>
            {group.project}
            <span className={cn('font-normal text-ink-dim', tabular)}> {group.count}</span>
          </h3>
          <ul>
            {group.roots.map((node) => (
              <JiraBranch
                key={node.issue.key}
                node={node}
                showRole={showRole}
                depth={0}
                ramos={ramos}
                abertura={abertura}
                onAlternar={onAlternar}
                pessoaNome={pessoaNome}
              />
            ))}
          </ul>
        </div>
      ))}
    </>
  );
}

function JiraBranch({
  node,
  showRole,
  depth,
  ramos,
  abertura,
  onAlternar,
  pessoaNome,
}: {
  node: JiraNode;
  showRole: boolean;
  depth: number;
  ramos: Map<string, boolean>;
  abertura: Abertura;
  onAlternar: (chave: string, aberto: boolean) => void;
  pessoaNome?: string;
}) {
  const temFilhos = node.children.length > 0;
  const aberto = ramos.get(node.issue.key) ?? (abertura === 'tudo' || node.origin === 'ancestor');

  return (
    <>
      <JiraRow
        issue={node.issue}
        showRole={showRole}
        depth={depth}
        filhos={node.children.length}
        aberto={aberto}
        origin={node.origin}
        onAlternar={() => onAlternar(node.issue.key, !aberto)}
        pessoaNome={pessoaNome}
      />
      {temFilhos &&
        aberto &&
        node.children.map((child) => (
          <JiraBranch
            key={child.issue.key}
            node={child}
            showRole={showRole}
            depth={depth + 1}
            ramos={ramos}
            abertura={abertura}
            onAlternar={onAlternar}
            pessoaNome={pessoaNome}
          />
        ))}
    </>
  );
}

function JiraRow({
  issue,
  showRole,
  depth,
  filhos = 0,
  aberto = false,
  origin = 'match',
  onAlternar,
  pessoaNome,
}: {
  issue: JiraItem;
  showRole: boolean;
  depth: number;
  /** Uma linha de caminho é lida como contexto, não como trabalho seu. */
  origin?: JiraNodeOrigin;
  /** Quantas issues estão logo abaixo desta. Zero fora da hierarquia. */
  filhos?: number;
  aberto?: boolean;
  onAlternar?: () => void;
  pessoaNome?: string;
}) {
  const focus = useFocusBlock();
  const source: FocusSource = {
    kind: 'jira',
    ref: issue.key,
    title: issue.summary,
    url: issue.url,
  };
  const parado = stalenessLabel(issue);
  const prazo = issue.dueDate ? dueLabel(issue.dueDate) : null;
  const atrasado = issue.dueDate ? isOverdue(issue.dueDate) : false;
  // O papel só é dito quando não é o padrão: em 15 de 19 issues ele era
  // "responsável", e um selo que repete não informa nada. Relator, sim, é
  // exceção e vale a marca.
  const eRelator = issue.role === 'reporter';

  return (
    <li
      className={rowShell}
      style={{ paddingLeft: depth > 0 ? `calc(${depth} * 1.5rem)` : undefined }}
      draggable={focus.enabled}
      onDragStart={(event) => {
        if (!focus.enabled) return;
        event.dataTransfer.setData(FOCUS_DRAG_TYPE, JSON.stringify(source));
        event.dataTransfer.effectAllowed = 'copy';
      }}
    >
      {/* A branch tick reads as hierarchy without drawing a full tree of guides. */}
      {depth > 0 && (
        <span
          className="-mr-2 size-2 shrink-0 -translate-y-0.5 rounded-bl-[3px] border-b border-l border-line-strong"
          aria-hidden="true"
        />
      )}
      {/* A seta só existe onde há o que revelar. Numa issue sem filha ela
          seria um controle que não faz nada — o espaçador mantém o
          alinhamento da coluna. */}
      {filhos > 0 && onAlternar ? (
        <button
          type="button"
          className={cn(caret, focusRing)}
          aria-label={`${aberto ? 'recolher' : 'expandir'} ${filhos === 1 ? 'a issue' : `as ${filhos} issues`} sob ${issue.key}`}
          aria-expanded={aberto}
          onClick={onAlternar}
        >
          <NavArrowRight width={14} height={14} />
        </button>
      ) : (
        <span className="inline-block size-[18px] shrink-0" aria-hidden="true" />
      )}
      <span className="shrink-0 type-caption leading-6 text-ink-dim">{issueMarker(issue)}</span>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex min-w-0 items-baseline gap-3">
          <a
            className={cn('shrink-0 font-mono text-sm text-brand hover:underline', focusRing)}
            href={issue.url}
            target="_blank"
            rel="noreferrer"
          >
            {issue.key}
          </a>
          {origin === 'ancestor' ? <JiraFlagMark issue={issue} /> : <FlagIndicator issue={issue} />}
          <span
            className={cn(
              'min-w-0 flex-1 truncate',
              origin === 'ancestor' ? 'text-ink-dim' : 'text-ink',
            )}
          >
            {issue.summary}
          </span>
          {showRole && eRelator && (
            <span className={cn(roleBadge, 'border-line-strong bg-neutral-tint text-ink-dim')}>
              REL
            </span>
          )}
          {/* A pending decision is the only mark that asks something of the reader,
              so it is the one that pulls more attention than the role badge. */}
          {issue.awaitingApproval && (
            <ApprovalBadge
              issue={issue}
              className={cn(
                roleBadge,
                'border-warning/45 bg-warning-tint font-semibold text-warning',
              )}
              title={
                pessoaNome
                  ? `aguardando a aprovação de ${pessoaNome}`
                  : 'aguardando a sua aprovação'
              }
            />
          )}
        </div>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 type-caption text-ink-dim">
          {origin === 'ancestor' ? (
            <JiraStatus issue={issue} />
          ) : (
            <TransitionAction issue={issue}>
              <JiraStatus issue={issue} />
            </TransitionAction>
          )}
          <JiraPriorityLabel issue={issue} />
          {parado && <span className="whitespace-nowrap text-warning">{parado}</span>}
          {prazo && (
            <span
              className={cn(
                'whitespace-nowrap',
                atrasado ? 'is-overdue text-danger' : 'text-ink-dim',
              )}
            >
              {prazo}
            </span>
          )}
        </div>
        <JiraPullLinks issueKey={issue.key} />
      </div>
      {focus.enabled && (
        <IconAction
          label={`agendar foco para ${issue.key}`}
          onClick={() => focus.schedule(source)}
          icon={<CalendarPlus className="size-4" />}
        />
      )}
      {origin !== 'ancestor' && <IssueActions issue={issue} />}
    </li>
  );
}
