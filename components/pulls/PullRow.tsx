'use client';

import { CalendarPlus } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import type { PullRequestItem } from '@/lib/types';
import { JiraStatus } from '@/components/data/JiraStatus';
import { repoUrl } from '@/lib/integrations/githubApi';
import { Badge } from '@/components/ui/badge';
import { EM_DASH, formatRelative } from '@/lib/format';
import { tabular } from '@/lib/theme';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import { PullBadges } from './PullBadges';
import { PullJiraSync } from './PullJiraSync';
import { PullActions } from './PullActions';

// Os PRs vinham como linhas de texto de uma CLI, então a única coisa a fazer
// era achar a URL no meio da frase. Agora chegam estruturados da API do
// GitHub, agrupados pelo repositório de onde vêm.
export function PullRow({ item, withRepo = false }: { item: PullRequestItem; withRepo?: boolean }) {
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
      <PullJiraSync item={item} />
      <PullBadges item={item} />
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
      <PullActions item={item} />
    </li>
  );
}
