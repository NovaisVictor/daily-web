'use client';

import { useState } from 'react';
import { ClipboardList } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { Chip } from '@/components/ui/Chip';
import {
  buildStandup,
  buildWeekly,
  standupText,
  weeklyText,
  type StandupSource,
} from '@/lib/standup';

type Copy = 'idle' | 'copied' | 'failed';

type Range = 'daily' | 'weekly';

const RANGE_LABEL: Record<Range, string> = {
  daily: 'Diário',
  weekly: 'Semanal',
};

const RANGE_DESCRIPTION: Record<Range, string> = {
  daily: 'O que você entregou desde o último dia útil, o que está em andamento e o que está travado.',
  weekly: 'O que você entregou e os PRs que abriu desde segunda-feira, e o que está travado agora.',
};

function summaryText(range: Range, source: StandupSource, now: Date): string {
  return range === 'daily'
    ? standupText(buildStandup(source, now))
    : weeklyText(buildWeekly(source, now));
}

const COPY_LABEL: Record<Copy, string> = {
  idle: 'Copiar',
  copied: 'Copiado',
  failed: 'Copiar',
};

export function StandupDialog({ source }: { source: StandupSource }) {
  const [text, setText] = useState<string | null>(null);
  const [copy, setCopy] = useState<Copy>('idle');
  // The weekly view lives in the same dialog rather than behind a second
  // button: the panel header already holds enough controls.
  const [range, setRange] = useState<Range>('daily');

  const show = (next: Range) => {
    setRange(next);
    setCopy('idle');
    setText(summaryText(next, source, new Date()));
  };

  const open = () => show('daily');

  const copyText = async () => {
    if (text === null) return;
    try {
      await navigator.clipboard.writeText(text);
      setCopy('copied');
    } catch {
      setCopy('failed');
    }
  };

  return (
    <>
      <IconAction
        variant="outline"
        label="Resumo para a daily"
        onClick={open}
        icon={<ClipboardList className="size-4" />}
      />
      <Dialog open={text !== null} onOpenChange={(next) => !next && setText(null)}>
        <DialogContent showCloseButton className="motion-reduce:animate-none">
          <DialogHeader>
            <DialogTitle>Resumo para a daily</DialogTitle>
            <DialogDescription className="text-ink-dim">{RANGE_DESCRIPTION[range]}</DialogDescription>
          </DialogHeader>
          <div role="group" aria-label="Período do resumo" className="flex gap-2">
            {(Object.keys(RANGE_LABEL) as Range[]).map((r) => (
              <Chip key={r} active={range === r} onClick={() => show(r)}>
                {RANGE_LABEL[r]}
              </Chip>
            ))}
          </div>
          <Textarea
            readOnly
            aria-label="texto do resumo"
            className="min-h-64 font-mono text-sm"
            value={text ?? ''}
          />
          {copy === 'failed' && (
            <p role="alert" className="text-sm text-danger">
              Não deu para copiar. Selecione o texto acima e copie com Ctrl+C.
            </p>
          )}
          <DialogFooter>
            <Button onClick={() => void copyText()} aria-live="polite">
              {COPY_LABEL[copy]}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
