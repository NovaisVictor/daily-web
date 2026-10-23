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
import { buildStandup, standupText, type StandupSource } from '@/lib/standup';

type Copy = 'idle' | 'copied' | 'failed';

const COPY_LABEL: Record<Copy, string> = {
  idle: 'Copiar',
  copied: 'Copiado',
  failed: 'Copiar',
};

export function StandupDialog({ source }: { source: StandupSource }) {
  const [text, setText] = useState<string | null>(null);
  const [copy, setCopy] = useState<Copy>('idle');

  const open = () => {
    setCopy('idle');
    setText(standupText(buildStandup(source, new Date())));
  };

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
            <DialogDescription className="text-ink-dim">
              O que você entregou desde o último dia útil, o que está em andamento e o que está travado.
            </DialogDescription>
          </DialogHeader>
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
