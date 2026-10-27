'use client';

import { useEffect, useMemo, useState } from 'react';
import { Pencil, Trash2 } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { CheckCircle, WarningCircle } from 'iconoir-react';
import {
  MODULES,
  applyMailPreset,
  defaultsFor,
  visibleFields,
  type FieldSpec,
  type ModuleId,
} from '@/lib/modules';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { useConfirm } from '@/components/data/ConfirmDialog';
import { PanelError } from '@/components/data/PanelError';
import { Input, inputClass } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';
import { Section } from './ui/Section';
import { ToolLogo } from './ToolLogo';

interface ConnectionSummary {
  id: string;
  module: ModuleId;
  label: string;
  visible: Record<string, string>;
  secretsSet: string[];
  updatedAt: string;
  unreadable: boolean;
}

interface ModuleState {
  module: ModuleId;
  label: string;
  summary: string;
  multi: boolean;
  enabled: boolean;
  configured: boolean;
  connections: ConnectionSummary[];
}

interface Payload {
  vaultReady: boolean;
  mstodoAvailable: boolean;
  googleConfigured: boolean;
  googleRedirectUri: string;
  slackConfigured: boolean;
  slackRedirectUri: string;
  modules: ModuleState[];
}

interface CalendarRef {
  id: string;
  label: string;
  primary: boolean;
}

type Editing = { module: ModuleId; id: string | null };

async function send(url: string, method: string, body?: unknown) {
  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error ?? 'Falha na operação');
  return data;
}

function Field({
  spec,
  value,
  alreadySet,
  onChange,
  mstodoAvailable,
}: {
  spec: FieldSpec;
  value: string;
  alreadySet: boolean;
  onChange: (value: string) => void;
  mstodoAvailable: boolean;
}) {
  const id = `field-${spec.name}`;
  const options = (spec.options ?? []).filter(
    // Oferecer um provedor que não está instalado é empurrar a pessoa para
    // um erro que ela não tem como resolver pela tela.
    (option) => option.value !== 'mstodo' || mstodoAvailable,
  );

  return (
    <div className="flex flex-col gap-1.5">
      <Label className="text-ink-mid" htmlFor={id}>
        {spec.label}
        {spec.required && <span aria-hidden="true"> *</span>}
      </Label>

      {spec.type === 'select' ? (
        <select
          id={id}
          className={cn(inputClass, 'cursor-pointer')}
          value={value}
          onChange={(e) => onChange(e.target.value)}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      ) : (
        <Input
          id={id}
          type={spec.type === 'password' ? 'password' : spec.type === 'number' ? 'number' : 'text'}
          value={value}
          placeholder={
            // Um segredo já gravado nunca volta para a tela. O placeholder é
            // o que diferencia "está vazio" de "está guardado e não mostro".
            alreadySet && spec.secret
              ? '•••••••• (guardado — deixe em branco para manter)'
              : spec.placeholder
          }
          onChange={(e) => onChange(e.target.value)}
          autoComplete={spec.secret ? 'new-password' : 'off'}
        />
      )}

      {spec.help && <p className="type-caption text-ink-dim">{spec.help}</p>}
    </div>
  );
}

/**
 * A superfície dos cartões internos — a conexão listada e o formulário. Vidro
 * sobre o fundo em degradê, e não uma cor sólida: no tema escuro `surface-1`
 * é quase preto e transformava cada cartão num retângulo cego dentro do
 * painel. O mesmo recorte serve a todos os módulos, então E-mail, Agenda,
 * Jira e o resto ficam iguais entre si.
 */
const innerSurface =
  'rounded-lg border border-line-soft bg-glass shadow-e1 backdrop-blur-sm backdrop-saturate-150 transition-[background-color,border-color] duration-100 ease-brand motion-reduce:transition-none';

/** O cartão reage ao cursor e ao foco de qualquer controle dentro dele — sem
 *  isso, a borda de foco do botão era a única pista de onde se está. */
const innerSurfaceInteractive =
  'hover:border-line-strong hover:bg-glass-strong focus-within:border-ring focus-within:ring-[3px] focus-within:ring-ring/40';

export function IntegrationsPanel() {
  const { confirm, dialog } = useConfirm();
  const [payload, setPayload] = useState<Payload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [values, setValues] = useState<Record<string, string>>({});
  const [label, setLabel] = useState('');
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<Record<string, { ok: boolean; message: string }>>(
    {},
  );
  const [openHelp, setOpenHelp] = useState<ModuleId | null>(null);
  // The module whose dialog is open. The card only shows the headline; the form,
  // the connections and the help do not fit in a quarter of the row.
  const [activeModule, setActiveModule] = useState<ModuleId | null>(null);
  const [flash, setFlash] = useState<{ ok: boolean; message: string } | null>(null);
  const [calendars, setCalendars] = useState<Record<string, CalendarRef[]>>({});
  const [chosenCalendars, setChosenCalendars] = useState<Record<string, string[]>>({});

  const load = async () => {
    try {
      const res = await fetch('/api/integrations');
      if (!res.ok) throw new Error('Falha ao carregar as integrações');
      setPayload(await res.json());
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  useEffect(() => {
    void load();
    // O retorno do Google volta para /tools com o resultado na query; ler e
    // limpar evita que a mensagem reapareça a cada recarga.
    const params = new URLSearchParams(window.location.search);
    const conectado = params.get('conectado');
    const erro = params.get('erro');
    if (conectado || erro) {
      setFlash({ ok: Boolean(conectado), message: conectado ?? erro ?? '' });
      window.history.replaceState({}, '', window.location.pathname);
    }
  }, []);

  // Depois de conectar pelo Google, a pessoa escolhe quais agendas entram.
  const loadCalendars = async (connId: string) => {
    try {
      const res = await fetch(`/api/integrations/agenda/google/calendars?id=${connId}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Falha ao listar as agendas');
      setCalendars((prev) => ({ ...prev, [connId]: data.calendars }));
      setChosenCalendars((prev) => ({
        ...prev,
        [connId]:
          data.selected.length > 0
            ? data.selected
            : data.calendars.filter((c: CalendarRef) => c.primary).map((c: CalendarRef) => c.id),
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const saveCalendars = async (connId: string) => {
    try {
      const data = await send('/api/integrations/agenda/google/calendars', 'PATCH', {
        id: connId,
        calendarIds: chosenCalendars[connId] ?? [],
      });
      setPayload((prev) => (prev ? { ...prev, modules: data.modules } : prev));
      setCalendars((prev) => {
        const next = { ...prev };
        delete next[connId];
        return next;
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const startNew = (moduleId: ModuleId) => {
    setEditing({ module: moduleId, id: null });
    setValues(defaultsFor(moduleId));
    setLabel(MODULES[moduleId].multi ? '' : MODULES[moduleId].label);
    setError(null);
  };

  const startEdit = (conn: ConnectionSummary) => {
    setEditing({ module: conn.module, id: conn.id });
    setValues({ ...defaultsFor(conn.module), ...conn.visible });
    setLabel(conn.label);
    setError(null);
  };

  const cancel = () => {
    setEditing(null);
    setValues({});
    setLabel('');
  };

  const save = async () => {
    if (!editing) return;
    setSaving(true);
    setError(null);
    try {
      // Só o que o formulário mostra vai no corpo. Campos ocultos (o token do
      // OAuth, a origem da agenda) são do servidor — ele os descarta de
      // qualquer forma, e mandá-los sugeriria que o cliente os controla.
      const allowed = new Set(visibleFields(editing.module, values).map((f) => f.name));
      const body = {
        label,
        values: Object.fromEntries(Object.entries(values).filter(([name]) => allowed.has(name))),
      };
      const url = editing.id
        ? `/api/integrations/${editing.module}/connections/${editing.id}`
        : `/api/integrations/${editing.module}/connections`;
      const data = await send(url, editing.id ? 'PUT' : 'POST', body);
      setPayload((prev) => (prev ? { ...prev, modules: data.modules } : prev));
      cancel();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const remove = async (conn: ConnectionSummary) => {
    const ok = await confirm({
      title: 'Remover a conexão?',
      description: `A credencial de "${conn.label}" é apagada junto e precisa ser cadastrada de novo.`,
      confirmLabel: 'Remover',
      destructive: true,
    });
    if (!ok) return;
    try {
      const data = await send(`/api/integrations/${conn.module}/connections/${conn.id}`, 'DELETE');
      setPayload((prev) => (prev ? { ...prev, modules: data.modules } : prev));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const test = async (conn: ConnectionSummary) => {
    setTesting(conn.id);
    try {
      const data = await send(`/api/integrations/${conn.module}/test`, 'POST', { id: conn.id });
      setTestResult((prev) => ({ ...prev, [conn.id]: { ok: data.ok, message: data.message } }));
    } catch (err) {
      setTestResult((prev) => ({
        ...prev,
        [conn.id]: { ok: false, message: err instanceof Error ? err.message : String(err) },
      }));
    } finally {
      setTesting(null);
    }
  };

  const fields = useMemo(() => {
    if (!editing) return [];
    // O preset de e-mail preenche host e porta; mostrar os campos já
    // resolvidos evitaria a pergunta, mas também esconderia o que foi
    // escolhido — então eles só reaparecem no modo manual.
    return visibleFields(editing.module, values);
  }, [editing, values]);

  if (!payload) {
    return (
      <Section eyebrow="Integrações">
        {error ? (
          <PanelError>{error}</PanelError>
        ) : (
          <p className="type-caption py-6 text-ink-dim">Carregando…</p>
        )}
      </Section>
    );
  }

  const closeDetails = () => {
    setActiveModule(null);
    setOpenHelp(null);
    cancel();
  };

  const openDetails = (mod: ModuleState, intent: 'connect' | 'help') => {
    setActiveModule(mod.module);
    setOpenHelp(intent === 'help' ? mod.module : null);
    // A module with nothing connected yet and a form to fill opens straight on it — unless Google
    // can do the job: the iCal form hides the "Conectar com Google" button, the safer path.
    const hasForm = MODULES[mod.module].fields.some((field) => !field.hidden);
    const googleCanConnect = mod.module === 'agenda' && payload.googleConfigured;
    if (intent === 'connect' && mod.connections.length === 0 && hasForm && !googleCanConnect) {
      startNew(mod.module);
    }
  };

  const renderDetails = (mod: ModuleState) => {
    const spec = MODULES[mod.module];
    const isEditing = editing?.module === mod.module;
    const connected = mod.connections.length > 0;

    // Uma só ação de conectar, no topo do popup, e a certa para cada módulo. O Google é o
    // caminho confiável para contas Google: o link iCal quebra quando o administrador
    // bloqueia compartilhamento externo, e é fácil colar o link errado.
    const connectAction = () => {
      if (isEditing) return null;
      if (mod.module === 'slack' && payload.slackConfigured) {
        return (
          <Button asChild size="sm">
            <a href="/api/integrations/slack/start">{connected ? 'Reconectar' : 'Conectar'}</a>
          </Button>
        );
      }
      if (mod.module === 'agenda' && payload.googleConfigured) {
        return (
          <Button asChild size="sm">
            <a href="/api/integrations/agenda/google/start">
              {connected ? 'Adicionar outra' : 'Conectar'}
            </a>
          </Button>
        );
      }
      // A cópia das notas no Drive só nasce pelo Google: não há o que preencher. Uma conexão
      // por pessoa; trocar de conta é remover e conectar de novo.
      if (mod.module === 'notes' && payload.googleConfigured && !connected) {
        return (
          <Button asChild size="sm">
            <a href="/api/integrations/agenda/google/start?purpose=notes">Conectar</a>
          </Button>
        );
      }
      // Um módulo sem campo visível não tem o que conectar pelo formulário: o botão abriria
      // um formulário vazio.
      if (spec.fields.some((field) => !field.hidden) && (spec.multi || !connected)) {
        return (
          <Button type="button" size="sm" onClick={() => startNew(mod.module)}>
            {connected ? 'Adicionar outra' : 'Conectar'}
          </Button>
        );
      }
      return null;
    };

    return (
      <div className="flex flex-col gap-3">
        <header className="flex flex-wrap items-start justify-between gap-4 pr-8">
          <div className="flex min-w-0 items-center gap-3">
            <ToolLogo moduleId={mod.module} />
            <div className="min-w-0">
              <DialogTitle className="type-subhead">{mod.label}</DialogTitle>
              <DialogDescription className="text-sm text-ink-mid">{mod.summary}</DialogDescription>
            </div>
          </div>
          {connectAction()}
        </header>

        {openHelp === mod.module && (
          <ul className="type-caption flex max-w-[70ch] flex-col gap-2 border-l border-line-soft pl-4 text-ink-mid">
            {spec.instructions.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        )}

        {/* Sem client no servidor, quem administra a instância precisa
                saber o que falta — e principalmente qual URI registrar, que é
                onde o setup costuma falhar. */}
        {mod.module === 'agenda' && !payload.googleConfigured && (
          <p className="type-caption max-w-[70ch] rounded-md border border-dashed border-line-strong p-3 text-ink-mid">
            Para conectar contas Google, quem administra este servidor precisa definir{' '}
            <code className="font-mono text-ink">GOOGLE_CLIENT_ID</code> e{' '}
            <code className="font-mono text-ink">GOOGLE_CLIENT_SECRET</code>. Criar o client é
            gratuito; registre esta URI de redirecionamento:{' '}
            <code className="mt-1 inline-block font-mono text-ink [overflow-wrap:anywhere]">
              {payload.googleRedirectUri}
            </code>
          </p>
        )}

        {mod.module === 'slack' && !payload.slackConfigured && (
          <p className="type-caption max-w-[70ch] rounded-md border border-dashed border-line-strong p-3 text-ink-mid">
            Para conectar o Slack, quem administra este servidor precisa definir{' '}
            <code className="font-mono text-ink">SLACK_CLIENT_ID</code> e{' '}
            <code className="font-mono text-ink">SLACK_CLIENT_SECRET</code>. Registre esta URI de
            redirecionamento:{' '}
            <code className="mt-1 inline-block font-mono text-ink [overflow-wrap:anywhere]">
              {payload.slackRedirectUri}
            </code>
          </p>
        )}

        {mod.connections.length > 0 && (
          <ul className="flex flex-col gap-3">
            {mod.connections.map((conn) => {
              const result = testResult[conn.id];
              return (
                <li
                  key={conn.id}
                  className={cn(
                    'flex flex-wrap items-center gap-3 p-3',
                    innerSurface,
                    innerSurfaceInteractive,
                  )}
                >
                  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-sm font-medium text-ink">{conn.label}</span>
                    {conn.unreadable ? (
                      <span className="type-caption text-warning">
                        ilegível com a chave atual — grave de novo
                      </span>
                    ) : (
                      <span className="type-caption truncate text-ink-dim">
                        {Object.values(conn.visible)[0] ?? 'configurado'}
                      </span>
                    )}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={testing === conn.id}
                      onClick={() => void test(conn)}
                    >
                      {testing === conn.id ? 'Testando…' : 'Testar'}
                    </Button>
                    {conn.visible.provider !== 'google' && (
                      <IconAction
                        variant="outline"
                        label="Editar"
                        onClick={() => startEdit(conn)}
                        icon={<Pencil className="size-4" />}
                      />
                    )}
                    {conn.visible.provider === 'google' && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => void loadCalendars(conn.id)}
                      >
                        Escolher agendas
                      </Button>
                    )}
                    <IconAction
                      variant="outline"
                      label="Remover"
                      className="text-danger hover:border-danger/40 hover:text-danger"
                      onClick={() => void remove(conn)}
                      icon={<Trash2 className="size-4" />}
                    />
                  </div>

                  {calendars[conn.id] && (
                    <fieldset className="flex basis-full flex-col gap-2 rounded-md border p-3">
                      <legend className="type-caption px-2 text-ink-mid">
                        Quais agendas mostrar
                      </legend>
                      {calendars[conn.id].map((cal) => (
                        <label
                          key={cal.id}
                          className="type-caption flex cursor-pointer items-center gap-2"
                        >
                          <input
                            type="checkbox"
                            className="size-4 shrink-0 cursor-pointer accent-brand"
                            checked={(chosenCalendars[conn.id] ?? []).includes(cal.id)}
                            onChange={(e) =>
                              setChosenCalendars((prev) => {
                                const current = prev[conn.id] ?? [];
                                return {
                                  ...prev,
                                  [conn.id]: e.target.checked
                                    ? [...current, cal.id]
                                    : current.filter((id) => id !== cal.id),
                                };
                              })
                            }
                          />
                          <span>{cal.label}</span>
                        </label>
                      ))}
                      <Button
                        type="button"
                        size="sm"
                        className="mt-2 self-start"
                        onClick={() => void saveCalendars(conn.id)}
                      >
                        Salvar seleção
                      </Button>
                    </fieldset>
                  )}
                  {result && (
                    <p
                      className={cn(
                        'type-caption flex basis-full items-center gap-2',
                        result.ok ? 'text-success' : 'text-danger',
                      )}
                      role="status"
                    >
                      {result.ok ? (
                        <CheckCircle width={14} height={14} />
                      ) : (
                        <WarningCircle width={14} height={14} />
                      )}
                      {result.message}
                    </p>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        {isEditing ? (
          <form
            className={cn('flex max-w-3xl flex-col gap-3 p-4', innerSurface)}
            onSubmit={(e) => {
              e.preventDefault();
              void save();
            }}
          >
            {spec.multi && (
              <div className="flex flex-col gap-1.5">
                <Label className="text-ink-mid" htmlFor="conn-label-input">
                  Nome desta conexão
                </Label>
                <Input
                  id="conn-label-input"
                  value={label}
                  placeholder="Trabalho, Pessoal…"
                  onChange={(e) => setLabel(e.target.value)}
                />
              </div>
            )}

            {fields.map((field) => (
              <Field
                key={field.name}
                spec={field}
                value={values[field.name] ?? ''}
                alreadySet={
                  editing.id
                    ? (mod.connections
                        .find((c) => c.id === editing.id)
                        ?.secretsSet.includes(field.name) ?? false)
                    : false
                }
                mstodoAvailable={payload.mstodoAvailable}
                onChange={(value) =>
                  setValues((prev) => {
                    const next = { ...prev, [field.name]: value };
                    // Trocar de provedor preenche host e porta na hora, em
                    // vez de deixar a pessoa procurar isso na internet.
                    return field.name === 'preset' ? applyMailPreset(next) : next;
                  })
                }
              />
            ))}

            <div className="mt-2 flex gap-2">
              <Button type="submit" size="sm" disabled={saving}>
                {saving ? 'Salvando…' : 'Salvar'}
              </Button>
              <Button type="button" variant="outline" size="sm" onClick={cancel}>
                Cancelar
              </Button>
            </div>
          </form>
        ) : (
          mod.module === 'agenda' &&
          payload.googleConfigured && (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="w-fit"
              onClick={() => startNew(mod.module)}
            >
              Usar link iCal
            </Button>
          )
        )}
      </div>
    );
  };

  const activeMod = payload.modules.find((mod) => mod.module === activeModule) ?? null;

  return (
    <div className="flex flex-col gap-4">
      {!payload.vaultReady && (
        <PanelError>
          DAILY_WEB_SECRET_KEY não está configurada no servidor. Sem ela nenhuma credencial pode ser
          guardada. Gere com <code className="font-mono text-ink">openssl rand -base64 32</code>.
        </PanelError>
      )}
      {error && <PanelError>{error}</PanelError>}
      {flash && (
        <p
          role="status"
          className={cn(
            'type-caption flex basis-full items-center gap-2',
            flash.ok ? 'text-success' : 'text-danger',
          )}
        >
          {flash.ok ? (
            <CheckCircle width={14} height={14} />
          ) : (
            <WarningCircle width={14} height={14} />
          )}
          {flash.message}
        </p>
      )}

      {/* 12 columns, three each: four cards to a row, narrowing on smaller screens. */}
      <div className="grid grid-cols-12 gap-4">
        {payload.modules.map((mod) => {
          const connected = mod.connections.length > 0;

          return (
            <article
              key={mod.module}
              className={cn(
                'col-span-12 flex flex-col gap-4 p-4 sm:col-span-6 lg:col-span-3',
                innerSurface,
                innerSurfaceInteractive,
              )}
            >
              <div className="flex items-start justify-between gap-2">
                <ToolLogo moduleId={mod.module} />
                {connected && (
                  <span className="rounded-full bg-brand-tint px-2.5 py-0.5 text-xs font-medium text-brand">
                    Conectado
                  </span>
                )}
              </div>
              <h3 className="type-subhead">{mod.label}</h3>
              <div className="mt-auto flex flex-wrap items-center gap-2">
                <Button type="button" size="sm" onClick={() => openDetails(mod, 'connect')}>
                  {connected ? 'Gerenciar' : 'Conectar'}
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="text-ink-mid"
                  disabled={connected}
                  onClick={() => openDetails(mod, 'help')}
                >
                  Como conectar
                </Button>
              </div>
            </article>
          );
        })}
      </div>

      <Dialog open={activeMod !== null} onOpenChange={(open) => !open && closeDetails()}>
        <DialogContent showCloseButton className="max-h-[85vh] overflow-y-auto sm:max-w-2xl">
          {activeMod && renderDetails(activeMod)}
        </DialogContent>
      </Dialog>
      {dialog}
    </div>
  );
}
