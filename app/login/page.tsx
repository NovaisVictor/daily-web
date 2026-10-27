'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

export default function LoginPage() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? 'Falha ao entrar');
        return;
      }
      // A full load, not a client navigation: the root layout paints the person's saved
      // appearance on <html>, and it only runs again on a load. A soft navigation would leave
      // the login screen's defaults in place until the next reload.
      window.location.assign('/');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="flex min-h-dvh items-center justify-center p-6">
      <form
        className="flex w-full max-w-sm flex-col gap-4 rounded-xl border bg-card p-8 shadow-e3 backdrop-blur-xl backdrop-saturate-150"
        onSubmit={(e) => void submit(e)}
      >
        <div className="flex items-center gap-3">
          <span
            aria-hidden="true"
            className="flex size-10 shrink-0 items-center justify-center rounded-full border bg-glass-strong shadow-e1"
          >
            <span className="size-2 rounded-full bg-brand" />
          </span>
          <h1 className="type-title">daily-web</h1>
        </div>
        <p className="text-sm text-ink-mid">Seu dia, num relance.</p>

        <div className="grid gap-2">
          <Label htmlFor="login-username">Usuário</Label>
          <Input
            id="login-username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoComplete="username"
            autoFocus
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="login-password">Senha</Label>
          <Input
            id="login-password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
          />
        </div>

        {error && (
          <p role="alert" className="text-sm text-danger">
            {error}
          </p>
        )}

        {/* The one action on the screen, so it gets the single glow budget. */}
        <Button type="submit" variant="glow" disabled={submitting}>
          {submitting ? 'Entrando' : 'Entrar'}
        </Button>
      </form>
    </main>
  );
}
