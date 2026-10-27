'use client';

import { useEffect, useRef, useState } from 'react';
import { Broom, Pause, Play } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import type { PomodoroPhase, PomodoroState } from '@/lib/types';
import { Button } from '@/components/ui/button';
import { tabular } from '@/lib/theme';
import { cn } from '@/lib/utils';

interface Props {
  pomodoro: PomodoroState | null;
  onChanged: () => void;
}

function formatRemaining(seconds: number): string {
  const m = Math.floor(seconds / 60)
    .toString()
    .padStart(2, '0');
  const s = Math.floor(seconds % 60)
    .toString()
    .padStart(2, '0');
  return `${m}:${s}`;
}

// instrumentation.ts já dispara o push do ntfy a cada transição real de
// fase, mesmo sem nenhuma aba aberta. Aqui só existe o caminho PRIMÁRIO: a
// Notification API do navegador quando a aba está aberta com permissão.
function notifyPhaseChange(phase: PomodoroPhase): void {
  const message = phase === 'focus' ? 'Hora de focar' : 'Hora de descansar';
  if (typeof Notification === 'undefined') return;
  if (Notification.permission === 'granted') {
    new Notification('daily-web', { body: message });
    return;
  }
  if (Notification.permission === 'default') {
    void Notification.requestPermission();
  }
}

export function Pomodoro({ pomodoro, onChanged }: Props) {
  const lastPhase = useRef<PomodoroPhase | null>(null);
  const [error, setError] = useState<string | null>(null);

  // O servidor só é consultado a cada 20s: sem um tique local o contador
  // ficaria parado e depois saltaria 20 segundos de uma vez. Aqui ele corre
  // de segundo em segundo e cada resposta do servidor reancora o valor.
  const [ticked, setTicked] = useState(0);
  const anchor = useRef({ seconds: 0, at: Date.now() });

  useEffect(() => {
    if (!pomodoro) return;
    anchor.current = { seconds: pomodoro.remainingSeconds, at: Date.now() };
    setTicked(pomodoro.remainingSeconds);
  }, [pomodoro?.remainingSeconds, pomodoro?.phase, pomodoro?.running]);

  useEffect(() => {
    if (!pomodoro?.running) return;
    const timer = setInterval(() => {
      const elapsed = Math.floor((Date.now() - anchor.current.at) / 1000);
      setTicked(Math.max(anchor.current.seconds - elapsed, 0));
    }, 1000);
    return () => clearInterval(timer);
  }, [pomodoro?.running]);

  useEffect(() => {
    if (!pomodoro) return;
    if (lastPhase.current !== null && lastPhase.current !== pomodoro.phase) {
      notifyPhaseChange(pomodoro.phase);
    }
    lastPhase.current = pomodoro.phase;
  }, [pomodoro?.phase]);

  // Alimenta o fundo ambiente: a tela inteira esquenta durante o foco.
  useEffect(() => {
    const focusing = Boolean(pomodoro?.running && pomodoro.phase === 'focus');
    window.dispatchEvent(new CustomEvent('daily-web:focus', { detail: focusing }));
  }, [pomodoro?.running, pomodoro?.phase]);

  if (!pomodoro || !pomodoro.enabled) return null;

  const post = async (url: string, fallback: string) => {
    const res = await fetch(url, { method: 'POST' });
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      setError(data.error ?? fallback);
      return;
    }
    setError(null);
    onChanged();
  };

  const isFocus = pomodoro.phase === 'focus';
  const remaining = pomodoro.running ? ticked : pomodoro.remainingSeconds;

  return (
    <div className="flex flex-col gap-2 pb-2" data-testid="pomodoro">
      <div className="flex items-center gap-4">
        <div className="flex flex-col gap-0.5">
          <span className="type-caption text-ink-dim">{isFocus ? 'foco' : 'descanso'}</span>
          <span className={cn('type-caption text-ink-dim', tabular)} title="focos concluídos">
            {pomodoro.completedFocusCount} focos
          </span>
        </div>
        <span className={cn('type-subhead text-ink', tabular)}>{formatRemaining(remaining)}</span>
        <div className="flex gap-2">
          <IconAction
            variant="default"
            label={pomodoro.running ? 'pausar foco' : 'iniciar foco'}
            onClick={() =>
              void post(
                pomodoro.running ? '/api/pomodoro/pause' : '/api/pomodoro/start',
                'Falha ao atualizar pomodoro',
              )
            }
            icon={pomodoro.running ? <Pause className="size-4" /> : <Play className="size-4" />}
          />
          <IconAction
            label="zerar pomodoro"
            onClick={() => void post('/api/pomodoro/reset', 'Falha ao zerar pomodoro')}
            icon={<Broom className="size-4" />}
          />
        </div>
      </div>
      {error && (
        <span role="alert" className="type-caption text-danger">
          {error}
        </span>
      )}
    </div>
  );
}
