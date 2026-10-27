'use client';

import type { PomodoroState } from '@/lib/types';
import { WELCOME_LABELS, type WelcomeKind } from '@/lib/greeting';
import { Clock } from './Clock';
import { Pomodoro } from './Pomodoro';

interface Props {
  greetingName: string | null;
  welcome: WelcomeKind;
  pomodoro: PomodoroState | null;
  onChanged: () => void;
}

export function NowBand({ greetingName, welcome, pomodoro, onChanged }: Props) {
  return (
    <header className="mb-10 flex flex-wrap items-end justify-between gap-6 pb-2">
      <div className="flex flex-col gap-1.5">
        <h1 className="type-heading">{greetingName ? `Olá, ${greetingName}` : 'Olá'}</h1>
        <p className="text-sm text-ink-mid">{WELCOME_LABELS[welcome]}</p>
      </div>
      <div className="flex flex-wrap items-end gap-10">
        <Pomodoro pomodoro={pomodoro} onChanged={onChanged} />
        <Clock />
      </div>
    </header>
  );
}
