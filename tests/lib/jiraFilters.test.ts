import { describe, expect, it } from 'vitest';
import {
  EMPTY_JIRA_FILTERS,
  hasJiraFilters,
  jiraFilterOptions,
  jiraFiltersToParams,
  lineageOf,
  matchesJiraFilters,
  parseJiraFilters,
  tierOf,
  type JiraFilterState,
} from '@/lib/jiraFilters';
import { toJiraItem } from '@/lib/integrations/jiraApi';
import type { JiraItem } from '@/lib/types';

// Os itens saem do mesmo conversor que trata a resposta do Jira, com os
// níveis que a API desta instância devolve (Iniciativa 2, Epic 1, História 0).
function raw(key: string, type: string, level: number, parent?: string, over: Record<string, unknown> = {}) {
  return toJiraItem(
    {
      key,
      fields: {
        summary: `Resumo ${key}`,
        status: { name: 'Em Andamento', statusCategory: { key: 'indeterminate' } },
        project: { key: key.split('-')[0] },
        issuetype: { name: type, subtask: level < 0, hierarchyLevel: level },
        parent: parent ? { key: parent, fields: { summary: `Resumo ${parent}` } } : null,
        ...over,
      },
    },
    'https://acme.atlassian.net',
    'assignee',
  );
}

const OBJ = raw('TT-1', 'Objective', 3);
const INI_A = raw('TT-10', 'Iniciativa', 2, 'TT-1', { summary: 'Programa de fidelidade' });
const INI_B = raw('TT-20', 'Iniciativa', 2, 'TT-1', { summary: 'Pagamentos' });
const EPIC_A = raw('TT-11', 'Epic', 1, 'TT-10', { summary: 'Pontos por aposta' });
const EPIC_B = raw('TT-21', 'Epic', 1, 'TT-20', { summary: 'Pix' });
const STORY_A1 = raw('TT-111', 'História', 0, 'TT-11', { summary: 'Tela de saldo' });
const STORY_A2 = raw('TT-112', 'História', 0, 'TT-11', {
  summary: 'API de extrato',
  status: { name: 'Backlog', statusCategory: { key: 'new' } },
});
const SUB_A1 = raw('TT-1111', 'Subtarefa', -1, 'TT-111', { summary: 'Ajustar layout' });
const STORY_B = raw('TT-211', 'História', 0, 'TT-21', { summary: 'QR code' });

const ALL: JiraItem[] = [OBJ, INI_A, INI_B, EPIC_A, EPIC_B, STORY_A1, STORY_A2, SUB_A1, STORY_B];
const BY_KEY = new Map(ALL.map((i) => [i.key, i]));
const MINE: JiraItem[] = [STORY_A1, STORY_A2, SUB_A1, STORY_B, EPIC_B];

const keys = (filters: Partial<JiraFilterState>) =>
  MINE.filter((i) => matchesJiraFilters(i, { ...EMPTY_JIRA_FILTERS, ...filters }, BY_KEY)).map(
    (i) => i.key,
  );

describe('tierOf', () => {
  it('lê o degrau pelo nível hierárquico, não pelo nome do tipo', () => {
    expect(tierOf(INI_A)).toBe('initiative');
    expect(tierOf(EPIC_A)).toBe('epic');
    expect(tierOf(STORY_A1)).toBe('story');
    expect(tierOf(raw('TT-9', 'Trilha', 2))).toBe('initiative');
    expect(tierOf(raw('TT-8', 'Bug', 0))).toBe('story');
  });

  it('não classifica objetivo, subtarefa nem tipo sem nível', () => {
    expect(tierOf(OBJ)).toBeNull();
    expect(tierOf(SUB_A1)).toBeNull();
    expect(tierOf({ ...STORY_A1, hierarchyLevel: null })).toBeNull();
  });
});

describe('lineageOf', () => {
  it('sobe do pai até o topo conhecido', () => {
    expect(lineageOf(SUB_A1, BY_KEY).map((i) => i.key)).toEqual(['TT-111', 'TT-11', 'TT-10', 'TT-1']);
  });

  it('para num pai que aponta de volta, sem laço', () => {
    const a = raw('X-1', 'Epic', 1, 'X-2');
    const b = raw('X-2', 'Epic', 1, 'X-1');
    expect(lineageOf(a, new Map([a, b].map((i) => [i.key, i]))).map((i) => i.key)).toEqual(['X-2']);
  });
});

function group<T = string>(values: T[], mode: 'include' | 'exclude' = 'include') {
  return { values, mode };
}

describe('matchesJiraFilters', () => {
  it('sem filtro, tudo passa', () => {
    expect(keys({})).toEqual(MINE.map((i) => i.key));
  });

  it('filtra pelo status, sem diferenciar caixa', () => {
    expect(keys({ status: group(['backlog']) })).toEqual(['TT-112']);
  });

  it('filtra por múltiplos status (composto / OU)', () => {
    expect(keys({ status: group(['Backlog', 'Em Andamento']) })).toEqual(
      MINE.map((i) => i.key),
    );
  });

  it('filtra por exclusão de status (≠ / NÃO)', () => {
    expect(keys({ status: group(['Backlog'], 'exclude') })).toEqual([
      'TT-111',
      'TT-1111',
      'TT-211',
      'TT-21',
    ]);
  });

  it('filtra pelo tipo', () => {
    expect(keys({ tier: group(['story']) })).toEqual(['TT-111', 'TT-112', 'TT-211']);
    expect(keys({ tier: group(['epic']) })).toEqual(['TT-21']);
    expect(keys({ tier: group(['story', 'epic']) })).toEqual(['TT-111', 'TT-112', 'TT-211', 'TT-21']);
  });

  it('filtra por exclusão de tipo', () => {
    expect(keys({ tier: group(['story'], 'exclude') })).toEqual(['TT-1111', 'TT-21']);
  });

  it('escolher uma iniciativa traz tudo o que está debaixo dela', () => {
    expect(keys({ initiative: group(['TT-10']) })).toEqual(['TT-111', 'TT-112', 'TT-1111']);
  });

  it('escolher múltiplas iniciativas traz tudo debaixo de qualquer uma delas', () => {
    expect(keys({ initiative: group(['TT-10', 'TT-20']) })).toEqual([
      'TT-111',
      'TT-112',
      'TT-1111',
      'TT-211',
      'TT-21',
    ]);
  });

  it('excluir uma iniciativa remove ela e toda a sua árvore', () => {
    expect(keys({ initiative: group(['TT-10'], 'exclude') })).toEqual(['TT-211', 'TT-21']);
  });

  it('escolher um épico inclui o próprio épico quando ele é da lista', () => {
    expect(keys({ epic: group(['TT-21']) })).toEqual(['TT-211', 'TT-21']);
  });

  it('excluir um épico remove ele e as filhas', () => {
    expect(keys({ epic: group(['TT-21'], 'exclude') })).toEqual(['TT-111', 'TT-112', 'TT-1111']);
  });

  it('escolher uma história traz ela e as subtarefas dela', () => {
    expect(keys({ story: group(['TT-111']) })).toEqual(['TT-111', 'TT-1111']);
  });

  it('excluir uma história remove ela e suas subtarefas', () => {
    expect(keys({ story: group(['TT-111'], 'exclude') })).toEqual(['TT-112', 'TT-211', 'TT-21']);
  });

  it('os filtros de hierarquia se somam', () => {
    expect(keys({ initiative: group(['TT-10']), epic: group(['TT-21']) })).toEqual([]);
    expect(
      keys({ initiative: group(['TT-10']), tier: group(['story']), status: group(['Em Andamento']) }),
    ).toEqual(['TT-111']);
  });

  it('a busca acha pelo título de um ancestral', () => {
    expect(keys({ query: 'fidelidade' })).toEqual(['TT-111', 'TT-112', 'TT-1111']);
  });

  it('a busca ainda acha pela chave e pelo título da própria issue, sem acento', () => {
    expect(keys({ query: 'tt-211' })).toEqual(['TT-211']);
    expect(keys({ query: 'qr CODE' })).toEqual(['TT-211']);
  });
});

describe('jiraFilterOptions', () => {
  it('oferece os status da lista, sem repetir por caixa', () => {
    const outro = { ...STORY_B, status: 'em andamento' };
    const opcoes = jiraFilterOptions([STORY_A1, STORY_A2, outro], BY_KEY, EMPTY_JIRA_FILTERS);
    expect(opcoes.statuses).toEqual(['Backlog', 'Em Andamento']);
  });

  it('oferece as iniciativas e épicos acima do que está na lista, mesmo que não sejam seus', () => {
    const opcoes = jiraFilterOptions(MINE, BY_KEY, EMPTY_JIRA_FILTERS);
    expect(opcoes.initiatives.map((i) => i.key)).toEqual(['TT-20', 'TT-10']);
    expect(opcoes.epics.map((i) => i.key)).toEqual(['TT-21', 'TT-11']);
  });

  it('desce em cascata a partir da iniciativa escolhida', () => {
    const opcoes = jiraFilterOptions(MINE, BY_KEY, {
      ...EMPTY_JIRA_FILTERS,
      initiative: group(['TT-10']),
    });
    expect(opcoes.epics.map((i) => i.key)).toEqual(['TT-11']);
    expect(opcoes.stories.map((i) => i.key)).toEqual(['TT-112', 'TT-111']);
  });

  it('desce em cascata com múltiplas iniciativas', () => {
    const opcoes = jiraFilterOptions(MINE, BY_KEY, {
      ...EMPTY_JIRA_FILTERS,
      initiative: group(['TT-10', 'TT-20']),
    });
    expect(opcoes.epics.map((i) => i.key)).toEqual(['TT-21', 'TT-11']);
    expect(opcoes.stories.map((i) => i.key)).toEqual(['TT-112', 'TT-211', 'TT-111']);
  });

  it('e a partir do épico escolhido', () => {
    const opcoes = jiraFilterOptions(MINE, BY_KEY, {
      ...EMPTY_JIRA_FILTERS,
      epic: group(['TT-21']),
    });
    expect(opcoes.stories.map((i) => i.key)).toEqual(['TT-211']);
  });

  it('não oferece a iniciativa que não tem nada da lista debaixo', () => {
    const opcoes = jiraFilterOptions([STORY_A1], BY_KEY, EMPTY_JIRA_FILTERS);
    expect(opcoes.initiatives.map((i) => i.key)).toEqual(['TT-10']);
  });
});

describe('filtros na URL', () => {
  it('lê e grava todos os campos, com nomes próprios do Jira e suporte a múltiplos valores', () => {
    const filtros: JiraFilterState = {
      query: 'saldo',
      status: group(['Code Review PR', 'Backlog']),
      tier: group(['story', 'epic'], 'exclude'),
      initiative: group(['TT-10']),
      epic: group(['TT-11']),
      story: group(['TT-111']),
    };
    const params = jiraFiltersToParams(new URLSearchParams('jira=entregues'), filtros);
    expect(params.get('jira')).toBe('entregues');
    expect(params.get('jiraStatus')).toBe('Code Review PR,Backlog');
    expect(params.get('jiraTipo')).toBe('story,epic');
    expect(params.get('jiraTipoModo')).toBe('exclude');
    expect(parseJiraFilters(params)).toEqual(filtros);
  });

  it('lê prefixo de negação ! diretamente nos valores', () => {
    const params = new URLSearchParams('jiraStatus=!Backlog,!Em Andamento');
    const parsed = parseJiraFilters(params);
    expect(parsed.status).toEqual(group(['Backlog', 'Em Andamento'], 'exclude'));
  });

  it('o vazio não vai para a URL', () => {
    const params = jiraFiltersToParams(
      new URLSearchParams('jiraStatus=Backlog&jiraTipo=epic&jiraStatusModo=exclude'),
      EMPTY_JIRA_FILTERS,
    );
    expect(params.toString()).toBe('');
  });

  it('valor que a tela não produz cai no padrão', () => {
    const filtros = parseJiraFilters(
      new URLSearchParams(
        `jiraTipo=objetivo&jiraIniciativa=DROP TABLE&jiraEpico=tt-11&jiraBusca=${'a'.repeat(500)}`,
      ),
    );
    expect(filtros.tier.values).toEqual([]);
    expect(filtros.initiative.values).toEqual([]);
    expect(filtros.epic.values).toEqual(['TT-11']);
    expect(filtros.query).toBe('');
  });

  it('hasJiraFilters só liga com algum filtro de verdade', () => {
    expect(hasJiraFilters(EMPTY_JIRA_FILTERS)).toBe(false);
    expect(hasJiraFilters({ ...EMPTY_JIRA_FILTERS, query: '   ' })).toBe(false);
    expect(hasJiraFilters({ ...EMPTY_JIRA_FILTERS, tier: group(['epic']) })).toBe(true);
    expect(hasJiraFilters({ ...EMPTY_JIRA_FILTERS, status: group(['Backlog'], 'exclude') })).toBe(true);
  });
});
