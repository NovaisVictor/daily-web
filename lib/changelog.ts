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
    id: '2026-10-23-agent-workspace',
    date: '2026-10-23',
    title: 'Seu trabalho com agentes, em um só lugar',
    items: [
      {
        title: 'Um cartão por tarefa',
        detail: 'A página inicial agora mostra o kanban do trabalho dos seus agentes. Abra um cartão para ver responsáveis, sessões e atividades. O painel com suas integrações continua disponível em Painel.',
      },
      {
        title: 'Conecte seus agentes',
        detail: 'Em Acesso dos agentes, gere um token pessoal e copie as instruções para Claude, Codex ou Gemini. O histórico dos agentes é mantido por 30 dias desde a última atividade; suas tarefas pessoais, issues e PRs continuam preservados.',
      },
      {
        title: 'Trabalhe pelo MCP',
        detail: 'Autorize seu cliente pelo navegador e use tarefas, Jira e GitHub com as suas permissões. Você pode revogar o acesso a qualquer momento. Senhas e tokens das integrações são cadastrados somente no navegador.',
      },
    ],
  },
  {
    id: '2026-10-23-modal-tarefa',
    date: '2026-10-23',
    title: 'Formulário de tarefa mais claro',
    items: [
      {
        title: 'Todos os campos à vista',
        detail:
          'Prioridade e repetição agora são listas de opções, e a data tem calendário, hora e atalhos: Hoje, Amanhã, Próx. semana e Sem data. Quem prefere digitar ainda pode usar "Digitar data", com prévia do resultado.',
      },
      {
        title: 'Salvar, apagar e não perder nada',
        detail:
          'Enter salva. Na edição, o botão "Apagar" pede confirmação antes. Se você clicar fora com alterações, o app pergunta antes de descartar. E editar uma tarefa mensal não apaga mais a repetição.',
      },
    ],
  },
  {
    id: '2026-10-23-quadro-completo',
    date: '2026-10-23',
    title: 'Quadro completo, e agora padrão',
    items: [
      {
        title: 'Tudo o que a lista faz, o quadro também faz',
        detail:
          'Cada nota tem o menu "⋯" com Editar, Adicionar subtarefa, Agendar foco, Mover para e Apagar, o mesmo das linhas da lista. Apagar sempre pede confirmação.',
      },
      {
        title: 'Subtarefas na própria nota',
        detail:
          'Clique no progresso "1/3" da nota para ver as subtarefas, marcar, apagar ou adicionar uma nova sem sair do quadro.',
      },
      {
        title: 'Adicione direto na coluna',
        detail:
          'Use "+ Adicionar" no fim de "A fazer" ou de "Fazendo". Enter cria a nota e deixa o campo aberto para a próxima; Esc cancela.',
      },
      {
        title: 'O quadro abre primeiro',
        detail:
          'O painel de tarefas agora abre no quadro. Quem já tinha escolhido a lista continua nela. No celular, as colunas viram abas, e a coluna Feito mostra as 10 primeiras notas, com "Mostrar todas" para o resto.',
      },
      {
        title: 'Atrasadas à vista',
        detail:
          'Uma data vencida aparece com ▲ e em destaque, na lista e no quadro. A lista também mostra quais tarefas estão em "Fazendo".',
      },
    ],
  },
  {
    id: '2026-10-23-kanban',
    date: '2026-10-23',
    title: 'Tarefas em quadro',
    items: [
      {
        title: 'Lista ou quadro, você escolhe',
        detail:
          'No painel de tarefas, o botão "Quadro" mostra as tarefas como post-its em três colunas: A fazer, Fazendo e Feito. A lista continua lá, e a escolha fica guardada para a próxima vez.',
      },
      {
        title: 'Arraste ou use os botões',
        detail:
          'Arraste a nota de uma coluna para outra, ou use os botões "A fazer", "Fazendo" e "Feito" na própria nota, que também funcionam pelo teclado. Levar para Feito conclui a tarefa; tirar de lá a reabre.',
      },
      {
        title: 'Alfinetes de verdade',
        detail:
          'As notas agora ficam presas por alfinetes coloridos vistos de lado, e algumas têm o canto descolando do quadro.',
      },
    ],
  },
  {
    id: '2026-10-23-jira-pessoa',
    date: '2026-10-23',
    title: 'Jira: troca de pessoa pelo título',
    items: [
      {
        title: 'De quem é o Jira, no próprio título',
        detail:
          'Clique em "Jira · Eu" no topo do painel para ver o Jira de outra pessoa, acompanhar alguém novo ou parar de acompanhar quem está na tela. As abas de pessoa saíram e as listas ganharam espaço.',
      },
    ],
  },
  {
    id: '2026-10-23-resumo-semanal',
    date: '2026-10-23',
    title: 'Resumo da semana',
    items: [
      {
        title: 'Diário ou Semanal no mesmo resumo',
        detail:
          'No resumo para a daily, a opção "Semanal" mostra o que você entregou desde segunda, os PRs abertos na semana e os bloqueios atuais, pronto para copiar na retro ou no 1:1. Ao reabrir, o resumo volta para o "Diário".',
      },
    ],
  },
  {
    id: '2026-10-23-dracula',
    date: '2026-10-23',
    title: 'Fundo Dracula',
    items: [
      {
        title: 'Uma terceira opção de fundo',
        detail:
          'No menu da conta, em Fundo, ao lado de Gradiente e Catppuccin: no tema escuro, a página, os cartões, o texto, as bordas, o destaque e os selos de situação seguem a paleta Dracula. No tema claro o gradiente continua.',
      },
    ],
  },
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
