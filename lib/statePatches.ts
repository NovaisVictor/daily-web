import type { DashboardState, EmailEnvelope, NotePaper, NotificationItem, PinColor, TodoTask } from './types';

// Depois de uma ação, o painel não pode continuar mostrando o estado
// anterior. Refazer o `refreshAll` inteiro custa uma ida ao IMAP, ao Jira e ao
// GitHub por causa de um clique; estas funções corrigem só a fatia que a ação
// mudou, e são puras para poderem ser testadas sem banco nem rede.

export interface EmailTarget {
  account: string;
  id: string;
}

// O id sozinho não identifica: o mesmo uid existe na entrada e nos enviados.
// Os alvos das ações são sempre da entrada, então é ali que eles casam.
function sameEmail(envelope: EmailEnvelope, target: EmailTarget): boolean {
  return (
    envelope.account === target.account &&
    envelope.id === target.id &&
    envelope.mailbox === 'inbox'
  );
}

function mapEmails(
  state: DashboardState,
  fn: (list: EmailEnvelope[]) => EmailEnvelope[],
): DashboardState {
  if (!state.email.data) return state;
  return { ...state, email: { ...state.email, data: fn(state.email.data) } };
}

export function markEmailsSeen(
  state: DashboardState,
  targets: EmailTarget[],
  seen: boolean,
): DashboardState {
  return mapEmails(state, (list) =>
    list.map((envelope) =>
      targets.some((t) => sameEmail(envelope, t)) ? { ...envelope, unread: !seen } : envelope,
    ),
  );
}

/** Apagado ou movido para outra pasta, some da caixa de entrada. */
export function removeEmails(state: DashboardState, targets: EmailTarget[]): DashboardState {
  return mapEmails(state, (list) =>
    list.filter((envelope) => !targets.some((t) => sameEmail(envelope, t))),
  );
}

export function markNotificationsRead(state: DashboardState, ids: string[]): DashboardState {
  if (!state.notifications.data || ids.length === 0) return state;
  // Conjunto, não `includes`: dispensar o sino inteiro passa aqui com todos
  // os avisos de uma vez, e uma busca linear por item viraria quadrática.
  const alvos = new Set(ids);
  const data: NotificationItem[] = state.notifications.data.map((item) =>
    alvos.has(item.id) ? { ...item, read: true } : item,
  );
  return { ...state, notifications: { ...state.notifications, data } };
}

export function markNotificationRead(state: DashboardState, id: string): DashboardState {
  return markNotificationsRead(state, [id]);
}

export function countUnreadNotifications(state: DashboardState): number {
  return (state.notifications.data ?? []).filter((item) => !item.read).length;
}

function mapTasks(
  state: DashboardState,
  fn: (list: TodoTask[]) => TodoTask[],
): DashboardState {
  if (!state.tasks.data) return state;
  return { ...state, tasks: { ...state.tasks, data: fn(state.tasks.data) } };
}

export function setTaskCompleted(
  state: DashboardState,
  id: string,
  completed: boolean,
): DashboardState {
  // Completing ends "Fazendo" on the server too; mirroring it keeps the card
  // from flashing back into that column before the reload lands.
  return mapTasks(state, (list) =>
    list.map((task) =>
      task.id === id ? { ...task, completed, doing: completed ? false : task.doing } : task,
    ),
  );
}

export function setTaskDoing(state: DashboardState, id: string, doing: boolean): DashboardState {
  return mapTasks(state, (list) =>
    list.map((task) => (task.id === id ? { ...task, doing } : task)),
  );
}

/** A colour left out keeps what the task has; null goes back to automatic.
 *  The panel uses it ahead of the server, and the board route on the cache. */
export function setTaskStyle(
  state: DashboardState,
  id: string,
  style: { paper?: NotePaper | null; pin?: PinColor | null },
): DashboardState {
  return mapTasks(state, (list) =>
    list.map((task) =>
      task.id === id
        ? {
            ...task,
            paper: style.paper === undefined ? task.paper : style.paper,
            pin: style.pin === undefined ? task.pin : style.pin,
          }
        : task,
    ),
  );
}

export function removeTask(state: DashboardState, id: string): DashboardState {
  return mapTasks(state, (list) => list.filter((task) => task.id !== id));
}

export function setSubtaskCompleted(
  state: DashboardState,
  taskId: string,
  itemId: string,
  completed: boolean,
): DashboardState {
  return mapTasks(state, (list) =>
    list.map((task) =>
      task.id === taskId
        ? {
            ...task,
            subtasks: task.subtasks.map((sub) =>
              sub.id === itemId ? { ...sub, completed } : sub,
            ),
          }
        : task,
    ),
  );
}
