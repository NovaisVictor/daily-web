'use client';

import type { PullRequestItem } from '@/lib/types';
import { Badge } from '@/components/ui/badge';
import { GLYPH } from '@/components/data/Status';
import { formatNumber } from '@/lib/format';
import { pullAge } from '@/lib/pullAge';
import { tabular } from '@/lib/theme';

function Glyph({ value }: { value: string }) {
  return <span aria-hidden>{value}</span>;
}

function CiBadge({ item }: { item: PullRequestItem }) {
  if (item.ci === 'running') {
    return (
      <Badge variant="info">
        <Glyph value={GLYPH.moving} />
        CI rodando
      </Badge>
    );
  }
  if (item.ci === 'passing') {
    return (
      <span className="inline-flex shrink-0 items-baseline gap-1 type-caption text-success">
        <Glyph value={GLYPH.live} />
        CI ok
      </span>
    );
  }
  if (item.ci !== 'failing') return null;

  const names = item.failedChecks.map((check) => check.name).join(', ');
  const title = names ? `Falharam: ${names}` : undefined;
  const link = item.failedChecks[0]?.url;
  const content = (
    <>
      <Glyph value={GLYPH.alert} />
      CI falhou
    </>
  );
  if (!link) {
    return (
      <Badge variant="danger" title={title}>
        {content}
      </Badge>
    );
  }
  const ref = `${item.repo}#${item.number}`;
  return (
    <Badge variant="danger" asChild>
      <a
        href={link}
        target="_blank"
        rel="noreferrer"
        title={title}
        aria-label={names ? `CI falhou em ${ref}: ${names}` : `CI falhou em ${ref}`}
        className="hover:underline"
      >
        {content}
      </a>
    </Badge>
  );
}

function ReviewBadge({ item }: { item: PullRequestItem }) {
  switch (item.review) {
    case 'changes-requested':
      return (
        <Badge variant="warning">
          <Glyph value={GLYPH.alert} />
          pediram mudanças
        </Badge>
      );
    case 'approved':
      return (
        <Badge variant="success">
          <Glyph value={GLYPH.live} />
          aprovado
        </Badge>
      );
    case 'pending':
      return (
        <Badge
          variant="secondary"
          title={item.pendingReviewers.length > 0 ? `Aguardando: ${item.pendingReviewers.join(', ')}` : undefined}
        >
          <Glyph value={GLYPH.idle} />
          aguardando revisão
        </Badge>
      );
    default:
      return null;
  }
}

function Size({ size }: { size: NonNullable<PullRequestItem['size']> }) {
  return (
    <span
      className={`shrink-0 type-caption text-ink-dim ${tabular}`}
      title={`${formatNumber(size.files)} arquivo(s) alterado(s)`}
    >
      +{formatNumber(size.additions)} −{formatNumber(size.deletions)}
    </span>
  );
}

function Age({ item }: { item: PullRequestItem }) {
  const age = pullAge(item);
  if (!age) return null;
  return (
    <span className="shrink-0 type-caption text-ink-dim">
      {age.opened}
      {age.stalled && (
        <>
          {' · '}
          <span className="text-warning">{age.stalled}</span>
        </>
      )}
    </span>
  );
}

/** Slot G1+G6: CI, review, conflict and age badges on a PR row. */
export function PullBadges({ item }: { item: PullRequestItem }) {
  if (!item.isPullRequest) return <Age item={item} />;
  return (
    <>
      <CiBadge item={item} />
      <ReviewBadge item={item} />
      {item.merge === 'conflict' && (
        <Badge variant="danger">
          <Glyph value={GLYPH.alert} />
          conflito
        </Badge>
      )}
      {item.size && <Size size={item.size} />}
      <Age item={item} />
    </>
  );
}
