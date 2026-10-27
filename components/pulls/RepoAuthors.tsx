'use client';

import { useState } from 'react';
import { Plus } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { Input } from '@/components/ui/input';
import { isGithubLogin } from '@/lib/githubLogin';
import { AUTHORS_PER_REPO_MAX } from '@/lib/integrations/githubApi';
import { focusRing } from '@/lib/theme';
import { cn } from '@/lib/utils';

interface Props {
  repo: string;
  authors: string[];
  /** Resolves to an error message, or null when the server accepted the list. */
  onSave: (authors: string[]) => Promise<string | null>;
}

/** Who is followed in one tracked repo. No authors means everyone: the list
 *  only ever narrows, so an empty one never hides a repo's PRs. */
export function RepoAuthors({ repo, authors, onSave }: Props) {
  const [draft, setDraft] = useState('');
  const [error, setError] = useState<string | null>(null);

  const save = async (next: string[]): Promise<boolean> => {
    setError(null);
    const failure = await onSave(next);
    setError(failure);
    return failure === null;
  };

  const add = async () => {
    const login = draft.trim().replace(/^@/, '');
    if (!isGithubLogin(login)) {
      setError('login do GitHub inválido');
      return;
    }
    if (authors.some((author) => author.toLowerCase() === login.toLowerCase())) {
      setDraft('');
      return;
    }
    if (authors.length >= AUTHORS_PER_REPO_MAX) {
      setError(`limite de ${AUTHORS_PER_REPO_MAX} autores por repositório — remova um antes de adicionar outro`);
      return;
    }
    if (await save([...authors, login])) setDraft('');
  };

  return (
    <div className="ml-3 flex flex-col gap-1.5 self-stretch">
      <div className="flex flex-wrap items-center gap-1.5">
        {authors.length === 0 && <span className="text-xs text-ink-dim">todos os autores</span>}
        {authors.map((author) => (
          <span
            key={author}
            className="inline-flex items-center gap-0.5 rounded-full border border-line bg-surface-1 py-0 pr-0.5 pl-2 text-xs text-ink-mid"
          >
            {author}
            <button
              type="button"
              aria-label={`deixar de acompanhar ${author} em ${repo}`}
              onClick={() => void save(authors.filter((item) => item !== author))}
              className={cn(
                'rounded-full p-1 leading-none text-ink-dim transition-colors duration-100 ease-brand hover:text-danger motion-reduce:transition-none',
                focusRing,
              )}
            >
              ×
            </button>
          </span>
        ))}
      </div>
      <div className="flex gap-1.5">
        <Input
          className="h-7 min-w-0 flex-1 text-xs"
          aria-label={`novo autor em ${repo}`}
          placeholder="acompanhar só este autor"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') void add();
          }}
        />
        <IconAction
          variant="outline"
          size="icon-xs"
          label={`Acompanhar autor em ${repo}`}
          onClick={() => void add()}
          icon={<Plus className="size-3.5" />}
        />
      </div>
      {error && (
        <p role="alert" className="text-xs text-danger">
          {error}
        </p>
      )}
    </div>
  );
}
