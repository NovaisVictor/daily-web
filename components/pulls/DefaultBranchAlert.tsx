'use client';

import type { DefaultBranchStatus } from '@/lib/types';
import { repoUrl } from '@/lib/integrations/githubApi';

function actionsUrl({ repo, branch }: DefaultBranchStatus): string | null {
  const base = repoUrl(repo);
  if (!base) return null;
  return `${base}/actions?${new URLSearchParams({ query: `branch:${branch}` })}`;
}

export function DefaultBranchAlert({ branches }: { branches: DefaultBranchStatus[] }) {
  const failing = branches.filter((b) => b.ci === 'failing');
  if (failing.length === 0) return null;

  return (
    <div
      role="alert"
      className="rounded-sm border border-warning/40 border-l-2 border-l-warning bg-warning-tint px-4 py-3 text-sm leading-relaxed text-ink-mid [overflow-wrap:anywhere]"
    >
      <p className="font-medium text-ink">CI vermelho na branch principal</p>
      <ul>
        {failing.map((b) => {
          const label = `${b.repo} · ${b.branch}`;
          const url = actionsUrl(b);
          return (
            <li key={`${b.repo}#${b.branch}`}>
              {url ? (
                <a href={url} target="_blank" rel="noreferrer" className="underline">
                  {label}
                </a>
              ) : (
                label
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
