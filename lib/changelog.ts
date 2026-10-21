export interface ReleaseItem {
  title: string;
  detail: string;
}

export interface Release {
  id: string;
  date: string;
  title: string;
  items: ReleaseItem[];
}

/** Newest first. A new release is one more entry at the top. */
export const RELEASES: Release[] = [
  {
    id: '2026-10-21-daily',
    date: '2026-10-21',
    title: 'Resumo para a daily',
    items: [
      {
        title: 'Ontem, hoje e bloqueios num clique',
        detail:
          'O botão no topo do painel do Jira monta o resumo com o que você entregou desde o último dia útil, o que está em andamento e o que está travado, inclusive os seus PRs, pronto para copiar.',
      },
    ],
  },
  {
    id: '2026-10-21-github',
    date: '2026-10-21',
    title: 'GitHub: o que trava cada PR',
    items: [
      {
        title: 'Selos de CI, revisão e conflito',
        detail:
          'Cada PR mostra se o CI falhou, se pediram mudanças, se está aprovado e se tem conflito, além de há quanto tempo está aberto e parado.',
      },
      {
        title: 'Aba "Meus PRs"',
        detail:
          'Seus PRs agrupados em "Precisa de você", "Esperando os outros", "Pronto para merge" e "Rascunho".',
      },
      {
        title: 'Ações pela linha',
        detail:
          'Pelo menu "⋯": aprovar ou pedir mudanças, comentar, pedir revisão de novo, fazer o merge e rodar de novo o CI que falhou, sempre com confirmação.',
      },
      {
        title: 'Card do Jira junto com o PR',
        detail:
          'Quando o card citado no PR ficou para trás, o painel oferece movê-lo para revisão ou em andamento, e avisa quando o card já está concluído com o PR aberto.',
      },
      {
        title: 'Filtros e busca',
        detail: 'Por repositório, autor e situação, guardados no endereço da página.',
      },
      {
        title: 'CI vermelho na branch principal',
        detail: 'Um aviso no topo quando a branch principal de um repositório acompanhado está falhando.',
      },
      {
        title: 'Revisões paradas no sino',
        detail: 'Uma revisão pedida a você há mais de um dia vira aviso.',
      },
    ],
  },
  {
    id: '2026-10-20-jira-acoes',
    date: '2026-10-20',
    title: 'Ações do Jira direto no painel',
    items: [
      {
        title: 'Mudar o status pela linha',
        detail:
          'Clique no status da issue e escolha uma das transições que o fluxo permite. Quando a transição pede campos (resolução, comentário), o painel avisa e abre o Jira.',
      },
      {
        title: 'Aprovar ou recusar pelo selo APROV',
        detail: 'Com confirmação, sem abrir o Jira.',
      },
      {
        title: 'Marcar e desmarcar impedimento',
        detail:
          'Pelo menu "⋯", marque a issue como impedida com um motivo, que vira comentário. Para desmarcar, clique na bandeira vermelha da linha.',
      },
      {
        title: 'Corrigir Problemas em lote',
        detail:
          '"Preencher início em todas" sugere a data de cada história pela mesma regra do "Preencher início" da linha, para conferir e gravar tudo de uma vez.',
      },
      {
        title: 'Comentar e responder menções',
        detail: 'Comentário rápido pelo menu "⋯" da issue e resposta às menções do sino.',
      },
      {
        title: 'Edições pequenas',
        detail: 'Prazo, prioridade, "atribuir a mim" e criar uma história já dentro de um épico.',
      },
    ],
  },
];

const SEEN_KEY = 'daily-web:changelog-seen';

export function unseenReleases(lastSeenId: string | null, releases: Release[] = RELEASES): Release[] {
  if (lastSeenId === null) return releases;
  const index = releases.findIndex((release) => release.id === lastSeenId);
  // An id we no longer know means the user saw some release that was later
  // removed: they are not new here, so only the latest is news to them.
  if (index === -1) return releases.slice(0, 1);
  return releases.slice(0, index);
}

export function loadLastSeen(): string | null {
  try {
    return localStorage.getItem(SEEN_KEY);
  } catch {
    return null;
  }
}

export function markSeen(id: string): void {
  try {
    localStorage.setItem(SEEN_KEY, id);
  } catch {
    // Without storage the dialog still closes for this session and shows again next time.
  }
}
