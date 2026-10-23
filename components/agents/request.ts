export async function accessRequest(url: string, init?: RequestInit): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal, cache: 'no-store' });
    if (!response.ok) {
      if (response.status === 409) {
        const detail:unknown=await response.json().catch(()=>null);
        if(detail&&typeof detail==='object'&&'error' in detail){
          const error=detail.error;
          if(error&&typeof error==='object'&&'code' in error&&error.code==='task_has_subtasks')throw new Error('Exclua as subtarefas antes de excluir a tarefa principal.');
        }
        throw new Error('O item mudou. Atualize os dados antes de tentar novamente.');
      }
      if (response.status === 401) throw new Error('Sua sessão expirou. Entre novamente.');
      if (response.status === 404) throw new Error('Este item não está mais disponível.');
      if (response.status === 503) throw new Error('O acesso dos agentes ainda não está configurado neste servidor.');
      throw new Error('Não foi possível concluir a operação. Tente novamente.');
    }
    return response.status === 204 ? null : await response.json();
  } finally { clearTimeout(timeout); }
}
export function mutationHeaders() {
  return { 'Content-Type': 'application/json', 'Idempotency-Key': crypto.randomUUID(), 'X-Request-Timestamp': new Date().toISOString() };
}
