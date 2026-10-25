export async function register() {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;

  // Semeia o operador vindo do env antes de qualquer request: sem isso, a
  // primeira subida depois do multiusuário deixaria a tabela vazia e ninguém
  // conseguiria logar.
  const { bootstrapFirstUser } = await import('@/lib/auth/users');
  bootstrapFirstUser();
  const { startAgentCleanup } = await import('@/lib/agents/retention');
  startAgentCleanup();
  const { startPushDispatcher } = await import('@/lib/push/dispatch');
  startPushDispatcher();

  const { startRefreshLoop, refreshIntervalSeconds } = await import('@/lib/refresher');
  const { getPomodoroState, onPhaseChange, activePomodoroUsers } = await import('@/lib/pomodoro');

  startRefreshLoop(refreshIntervalSeconds(process.env.REFRESH_SECONDS));

  // getPomodoroState() lazily detects phase transitions and fires onPhaseChange
  // listeners as a side effect — it only runs when something calls it. This
  // interval is independent of startRefreshLoop's data-refresh cadence and
  // exists solely to drive prompt phase detection for the ntfy fallback, so it
  // still fires even when no client has the dashboard open to poll /api/state.
  setInterval(() => {
    for (const userId of activePomodoroUsers()) getPomodoroState(userId);
  }, 10_000);

  onPhaseChange((phase) => {
    const topic = process.env.NTFY_TOPIC;
    if (!topic) return;
    const message = phase === 'focus' ? 'Hora de focar' : 'Hora de descansar';
    fetch(`https://ntfy.sh/${topic}`, { method: 'POST', body: message }).catch(() => {});
  });
}
