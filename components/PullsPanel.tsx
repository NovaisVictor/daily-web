'use client';

import { useEffect, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { CalendarPlus, Plus } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import type {
  PanelResult,
  PullRequestItem,
  PullsDigest,
  MyPullsDigest,
  ReviewRequestsDigest,
} from '@/lib/types';
import { PanelError } from '@/components/data/PanelError';
import { JiraStatus } from '@/components/data/JiraStatus';
import { groupByRepo, repoUrl, type RepoGroup } from '@/lib/integrations/githubApi';
import { Section } from './ui/Section';
import { cn } from '@/lib/utils';
import { EmptyState } from '@/components/data/EmptyState';
import { SkeletonRows } from './ui/legacy-skeleton';
import { Badge } from './ui/badge';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { EM_DASH, formatRelative } from '@/lib/format';
import { Tabs } from './ui/legacy-tabs';
import { focusRing, tabular } from '@/lib/theme';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';

// Os PRs vinham como linhas de texto de uma CLI, então a única coisa a fazer
// era achar a URL no meio da frase. Agora chegam estruturados da API do
// GitHub, agrupados pelo repositório de onde vêm.
function ItemRow({ item, withRepo = false }: { item: PullRequestItem; withRepo?: boolean }) {
  const focus = useFocusBlock();
  const repo = withRepo ? repoUrl(item.repo) : null;
  const source: FocusSource = {
    kind: 'pull',
    ref: `${item.repo}#${item.number}`,
    title: item.title,
    url: item.url,
  };
  return (
    <li
      className="flex items-baseline gap-3 border-b border-line-soft px-2 py-3 transition-colors duration-100 ease-brand even:bg-muted/25 last:border-b-0 hover:bg-brand-tint motion-reduce:transition-none"
      draggable={focus.enabled}
      onDragStart={(event) => {
        if (!focus.enabled) return;
        event.dataTransfer.setData(FOCUS_DRAG_TYPE, JSON.stringify(source));
        event.dataTransfer.effectAllowed = 'copy';
      }}
    >
      {/* Na lista global o repositório é a primeira coisa a saber: sem ele,
          "Arrumar o build" não diz de onde veio. */}
      {withRepo &&
        (repo ? (
          <a
            className="max-w-[40%] shrink-0 truncate text-ink-dim hover:underline"
            href={repo}
            target="_blank"
            rel="noreferrer"
          >
            {item.repo}
          </a>
        ) : (
          <span className="max-w-[40%] shrink-0 truncate text-ink-dim">{item.repo}</span>
        ))}
      <span className={`shrink-0 text-ink-dim ${tabular}`}>#{item.number}</span>
      <a
        className="min-w-0 flex-1 truncate text-ink hover:underline"
        href={item.url}
        target="_blank"
        rel="noreferrer"
      >
        {item.title || EM_DASH}
      </a>
      {item.jira?.map((ref) => (
        <a
          key={ref.key}
          className="inline-flex shrink-0 items-baseline gap-1.5 type-caption hover:underline"
          href={ref.url}
          target="_blank"
          rel="noreferrer"
          title={`${ref.key} no Jira`}
        >
          <span className="font-mono text-brand">{ref.key}</span>
          <JiraStatus issue={ref} />
        </a>
      ))}
      {/* O autor só importa quando não é você: num repo próprio é o que
          separa o seu PR do que o dependabot abriu. */}
      {!item.mine && item.author && <span className="shrink-0 text-ink-dim">{item.author}</span>}
      {item.draft && (
        <Badge variant="secondary" className="shrink-0">
          rascunho
        </Badge>
      )}
      {/* A idade só aparece onde ela é a informação: há quanto tempo este
          pedido de revisão está parado. */}
      {withRepo && item.createdAt && (
        <span className="shrink-0 text-ink-dim">{formatRelative(item.createdAt)}</span>
      )}
      {/* Na aba de revisões toda linha espera revisão: a etiqueta em todas
          elas não separaria nada. */}
      {item.awaitingYou && !withRepo && (
        <Badge variant="info" className="shrink-0">
          revisar
        </Badge>
      )}
      {focus.enabled && (
        <IconAction
          label={`agendar foco para ${source.ref}`}
          onClick={() => focus.schedule(source)}
          icon={<CalendarPlus className="size-4" />}
        />
      )}
    </li>
  );
}

function RepoBlock({ group }: { group: RepoGroup }) {
  const url = repoUrl(group.repo);
  return (
    <div className="mb-6 last:mb-0">
      <h3 className="type-subhead mb-2 border-b border-line pb-2 [&_a:hover]:underline">
        {url ? (
          <a href={url} target="_blank" rel="noreferrer">
            {group.repo}
          </a>
        ) : (
          group.repo
        )}
      </h3>

      {group.issues.length > 0 && (
        <div className="my-3 ml-4">
          <h4 className="type-caption mb-1 text-ink-dim">
            Issues{' '}
            <span className={`font-normal normal-case ${tabular}`}>{group.issues.length}</span>
          </h4>
          <ul className="text-sm">
            {group.issues.map((item) => (
              <ItemRow key={item.number} item={item} />
            ))}
          </ul>
        </div>
      )}

      {group.pulls.length > 0 && (
        <div className="my-3 ml-4">
          <h4 className="type-caption mb-1 text-ink-dim">
            Pull requests{' '}
            <span className={`font-normal normal-case ${tabular}`}>{group.pulls.length}</span>
          </h4>
          <ul className="text-sm">
            {group.pulls.map((item) => (
              <ItemRow key={item.number} item={item} />
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** As duas listas do painel. "Acompanhados" é o que você escolheu seguir;
 *  "Revisões" é o que pediram a você, em qualquer repositório que o token
 *  enxergue — não são recortes da mesma coleção. */
const ABAS = ['acompanhados', 'revisoes'] as const;
type Aba = (typeof ABAS)[number];

// A aba vive na URL para sobreviver ao recarregar e ir junto num link. A
// padrão fica fora dela, e o valor que não for uma aba conhecida cai na padrão.
const ABA_PARAM = 'pulls';
const ABA_PADRAO: Aba = 'acompanhados';

function parseAba(value: string | null): Aba {
  return ABAS.find((aba) => aba === value) ?? ABA_PADRAO;
}

interface Props {
  pulls: PanelResult<PullsDigest>;
  /** Opcional: o painel abre e funciona sem ela, mostrando a aba de revisões
   *  vazia enquanto o primeiro ciclo não voltou. */
  reviewRequests?: PanelResult<ReviewRequestsDigest>;
  myPulls?: PanelResult<MyPullsDigest>;
  className?: string;
  onChanged?: () => void;
  loading?: boolean;
}

export function PullsPanel({
  pulls,
  reviewRequests = { data: null, error: null },
  className,
  onChanged,
  loading = false,
}: Props) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const aba = parseAba(searchParams.get(ABA_PARAM));
  // Trocar de aba é navegação: entra no histórico, e o voltar desfaz.
  const setAba = (next: Aba) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === ABA_PADRAO) params.delete(ABA_PARAM);
    else params.set(ABA_PARAM, next);
    const query = params.toString();
    router.push(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };

  const [repos, setRepos] = useState<string[]>([]);
  const [newRepo, setNewRepo] = useState('');
  const [reposError, setReposError] = useState<string | null>(null);

  const loadRepos = async () => {
    const res = await fetch('/api/pulls/repos');
    if (!res.ok) return;
    const data = await res.json();
    setRepos(data.repos ?? []);
  };

  useEffect(() => {
    void loadRepos();
  }, []);

  const addRepo = async () => {
    setReposError(null);
    const res = await fetch('/api/pulls/repos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ repo: newRepo.trim() }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      setReposError(data.error ?? 'Falha ao adicionar repositório');
      return;
    }
    setRepos(data.repos ?? []);
    setNewRepo('');
    onChanged?.();
  };

  const removeRepo = async (repo: string) => {
    setReposError(null);
    const res = await fetch('/api/pulls/repos', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ repo }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      setReposError(data.error ?? 'Falha ao remover repositório');
      return;
    }
    setRepos(data.repos ?? []);
    onChanged?.();
  };

  const items = pulls.data?.items ?? [];
  const grupos = groupByRepo(items);
  // Um repositório renomeado falha sozinho; mostrar isso junto dos que deram
  // certo é mais útil do que substituir o painel inteiro por um erro.
  const repoErrors = pulls.data?.errors ?? [];

  const revisoes = reviewRequests.data?.items ?? [];

  const acompanhados = (
    <div id="pulls-panel-acompanhados" role="tabpanel" aria-labelledby="pulls-tab-acompanhados">
      {pulls.error && <PanelError>{pulls.error}</PanelError>}
      {repoErrors.length > 0 && <PanelError>{repoErrors.join('; ')}</PanelError>}

      {loading && items.length === 0 && <SkeletonRows count={4} />}

      {!loading && items.length === 0 && !pulls.error && (
        <EmptyState title="Nada aberto nos repositórios acompanhados." />
      )}

      {grupos.map((group) => (
        <RepoBlock key={group.repo} group={group} />
      ))}
    </div>
  );

  const digest = reviewRequests.data;
  const revisoesPanel = (
    <div id="pulls-panel-revisoes" role="tabpanel" aria-labelledby="pulls-tab-revisoes">
      {reviewRequests.error && <PanelError>{reviewRequests.error}</PanelError>}

      {loading && revisoes.length === 0 && !reviewRequests.error && <SkeletonRows count={4} />}

      {/* Lista vazia e lista que o token não alcança são coisas diferentes, e
          a segunda tem conserto: o aviso diz qual das duas é. */}
      {!loading && revisoes.length === 0 && !reviewRequests.error && digest?.scopeNote && (
        <EmptyState title="Nenhuma revisão pedida a você." description={digest.scopeNote} />
      )}
      {!loading && revisoes.length === 0 && !reviewRequests.error && !digest?.scopeNote && (
        <EmptyState title="Nenhuma revisão pedida a você." />
      )}

      {revisoes.length > 0 && (
        <ul className="text-sm">
          {revisoes.map((item) => (
            <ItemRow key={`${item.repo}#${item.number}`} item={item} withRepo />
          ))}
        </ul>
      )}

      {digest?.truncated && (
        <p className="type-caption mt-3 text-ink-dim">
          Mostrando {revisoes.length} de {digest.total}: a busca traz uma página por ciclo.
        </p>
      )}
    </div>
  );

  return (
    <Section
      className={cn('min-h-0', className)}
      eyebrow="GitHub"
      count={
        aba === 'revisoes'
          ? revisoes.length > 0
            ? String(revisoes.length)
            : undefined
          : items.length > 0
            ? String(items.length)
            : undefined
      }
    >
      {/* Altura de verdade para o corpo: o cartão do painel é um container
          que rola, e sem isto a lista cresce para fora dele em vez de rolar
          por dentro. As abas e a gaveta de repositórios ficam fora da área
          que rola, então continuam alcançáveis por mais longa que a lista
          seja. */}
      <div className="flex h-full min-h-0 flex-col">
        <div className="shrink-0">
          <Tabs
            id="pulls"
            label="listas do GitHub"
            active={aba}
            onChange={(id) => setAba(parseAba(id))}
            tabs={[
              { id: 'acompanhados', label: 'Acompanhados', count: items.length },
              { id: 'revisoes', label: 'Revisões', count: revisoes.length },
            ]}
          />
        </div>

        {/* A barra de rolagem tem faixa própria: sem ela, ela passa por cima
            do conteúdo quando aparece. */}
        <div
          data-slot="pulls-scroller"
          className="min-h-0 flex-1 overflow-y-auto pr-1 [scrollbar-gutter:stable]"
        >
          {aba === 'revisoes' ? revisoesPanel : acompanhados}
        </div>

        {aba === 'acompanhados' && (
          <details className="mt-4 shrink-0 border-t border-line pt-3">
            <summary className="cursor-pointer text-sm text-ink-dim transition-colors duration-100 ease-brand hover:text-ink-mid motion-reduce:transition-none">
              Repositórios acompanhados
            </summary>
            <div className="my-3 flex flex-wrap gap-2">
              {repos.map((repo) => (
                <span
                  key={repo}
                  className="inline-flex items-center gap-1 rounded-full border border-line-strong bg-surface-2 py-0.5 pr-1 pl-3 text-sm text-ink-mid shadow-e1"
                >
                  {repo}
                  <button
                    type="button"
                    aria-label={`remover ${repo}`}
                    onClick={() => void removeRepo(repo)}
                    className={cn(
                      'rounded-full p-1 leading-none text-ink-dim transition-colors duration-100 ease-brand hover:text-danger motion-reduce:transition-none',
                      focusRing,
                    )}
                  >
                    ×
                  </button>
                </span>
              ))}
              {repos.length === 0 && (
                <span className="py-2 text-sm text-ink-dim">
                  Nenhum repositório acompanhado ainda.
                </span>
              )}
            </div>
            <div className="flex gap-2">
              <Input
                className="h-8 min-w-0 flex-1"
                aria-label="novo repositório"
                placeholder="owner/repo"
                value={newRepo}
                onChange={(e) => setNewRepo(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') void addRepo();
                }}
              />
              <IconAction
                variant="outline"
                label="Adicionar repositório"
                onClick={() => void addRepo()}
                icon={<Plus className="size-4" />}
              />
            </div>
            {reposError && <PanelError>{reposError}</PanelError>}
          </details>
        )}
      </div>
    </Section>
  );
}

/**
 * A panel that cannot load is information, not an alarm: a contained block with a
 * warning rule, never loose red text competing with the sections that did load.
 */
