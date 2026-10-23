import { getDb } from './db';
import { DEFAULT_AGENDA_DAYS, isAgendaRange } from './agendaWindow';
import {
  defaultLayout,
  parseLayout,
  parseSizedLayouts,
  serializeLayout,
  serializeSizedLayouts,
} from './dashboardLayout';
import type { PanelPlacement, SizedLayout } from './dashboardLayout';
import { isJiraAccountId } from './jiraAccount';
import type { JiraPerson, TasksView } from './types';
import { isJiraKey } from './jiraKey';

// Preferências de visualização por usuário. São escolhas de como olhar, não
// de credencial: por isso não passam pelo cofre e não são cifradas.

export const AGENDA_DAYS = 'agendaDays';
export const DASHBOARD_LAYOUT = 'dashboardLayout';
export const DASHBOARD_LAYOUTS = 'dashboardLayouts';
export const TASKS_VIEW = 'tasksView';

function read(userId: string, key: string): string | null {
  const row = getDb()
    .prepare('SELECT value FROM preferences WHERE user_id = ? AND key = ?')
    .get(userId, key) as { value: string } | undefined;
  return row?.value ?? null;
}

export function setPreference(userId: string, key: string, value: string): void {
  getDb()
    .prepare(
      `INSERT INTO preferences (user_id, key, value, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT (user_id, key)
       DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
    )
    .run(userId, key, value, new Date().toISOString());
}

/** Quantos dias a agenda cobre para este usuário. Um valor fora da lista
 *  conhecida — de uma versão antiga, ou escrito à mão no banco — vira o
 *  padrão em vez de virar uma janela absurda. */
export function agendaDays(userId: string): number {
  const stored = Number(read(userId, AGENDA_DAYS));
  return isAgendaRange(stored) ? stored : DEFAULT_AGENDA_DAYS;
}

export function setAgendaDays(userId: string, days: number): void {
  setPreference(userId, AGENDA_DAYS, String(days));
}

export function isTasksView(value: unknown): value is TasksView {
  return value === 'list' || value === 'board';
}

/** The board is opt-in: anyone who never picked keeps the list they had. */
export function tasksView(userId: string): TasksView {
  const stored = read(userId, TASKS_VIEW);
  return isTasksView(stored) ? stored : 'list';
}

export function setTasksView(userId: string, view: TasksView): void {
  setPreference(userId, TASKS_VIEW, view);
}

/** Disposição dos painéis na grade. Um JSON ilegível — de uma versão antiga
 *  ou de escrita manual — vira o padrão em vez de deixar a tela em branco. */
export function dashboardLayout(userId: string): PanelPlacement[] {
  const bruto = read(userId, DASHBOARD_LAYOUT);
  if (!bruto) return defaultLayout();
  try {
    return parseLayout(JSON.parse(bruto));
  } catch {
    return defaultLayout();
  }
}

export function setDashboardLayout(userId: string, layout: PanelPlacement[]): void {
  setPreference(userId, DASHBOARD_LAYOUT, serializeLayout(layout));
}

/**
 * As disposições gravadas por tamanho de tela.
 *
 * Enquanto não houver nenhuma, a disposição única que a pessoa já tinha
 * continua valendo: ela foi feita antes de existir tamanho de tela, e
 * descartá-la em silêncio seria apagar o trabalho de alguém. A primeira
 * gravação por tamanho toma o lugar dela.
 */
export function dashboardLayouts(userId: string): SizedLayout[] {
  const bruto = read(userId, DASHBOARD_LAYOUTS);
  if (!bruto) return [];
  try {
    return parseSizedLayouts(JSON.parse(bruto));
  } catch {
    return [];
  }
}

export function setDashboardLayouts(userId: string, entries: SizedLayout[]): void {
  setPreference(userId, DASHBOARD_LAYOUTS, serializeSizedLayouts(entries));
}

export function resetDashboardLayout(userId: string): void {
  const db = getDb();
  for (const key of [DASHBOARD_LAYOUT, DASHBOARD_LAYOUTS]) {
    db.prepare('DELETE FROM preferences WHERE user_id = ? AND key = ?').run(userId, key);
  }
}

export function deleteUserPreferences(userId: string): void {
  getDb().prepare('DELETE FROM preferences WHERE user_id = ?').run(userId);
}

export const JIRA_WATCHED = 'jiraWatchedKeys';

export { isJiraKey };

/** Issues que a pessoa quer acompanhar mesmo não sendo dela — o Jira do time
 *  vizinho que trava o seu, a issue que você abriu para outro alguém. */
export function jiraWatchedKeys(userId: string): string[] {
  const bruto = read(userId, JIRA_WATCHED);
  if (!bruto) return [];
  return bruto
    .split(',')
    .map((k) => k.trim().toUpperCase())
    .filter(isJiraKey);
}

export function setJiraWatchedKeys(userId: string, keys: string[]): void {
  // Sem duplicatas e sempre em caixa alta: o Jira não diferencia, e a lista
  // não deve mostrar TT-1 e tt-1 como duas coisas.
  const limpas = [...new Set(keys.map((k) => k.trim().toUpperCase()).filter(isJiraKey))];
  setPreference(userId, JIRA_WATCHED, limpas.join(','));
}

export const JIRA_PEOPLE = 'jiraFollowedPeople';
export const MAX_JIRA_PEOPLE = 10;
export { isJiraAccountId };

export function jiraFollowedPeople(userId: string): JiraPerson[] {
  const bruto = read(userId, JIRA_PEOPLE);
  if (!bruto) return [];
  try {
    const json = JSON.parse(bruto);
    if (!Array.isArray(json)) return [];
    return json
      .filter((p): p is Record<string, unknown> => typeof p === 'object' && p !== null)
      .map((p) => ({
        accountId: String(p.accountId),
        displayName: String(p.displayName || '').trim().slice(0, 100),
      }))
      .filter((p) => isJiraAccountId(p.accountId));
  } catch {
    return [];
  }
}

export function setJiraFollowedPeople(userId: string, people: JiraPerson[]): void {
  const map = new Map<string, JiraPerson>();
  for (const p of people) {
    if (!isJiraAccountId(p.accountId)) continue;
    if (map.has(p.accountId)) continue;
    map.set(p.accountId, {
      accountId: p.accountId,
      displayName: p.displayName.trim().slice(0, 100),
    });
    if (map.size >= MAX_JIRA_PEOPLE) break;
  }
  setPreference(userId, JIRA_PEOPLE, JSON.stringify([...map.values()]));
}
