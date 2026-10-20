import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  fetchAncestors,
  fetchApproved,
  fetchDelivered,
  fetchIssues,
  fetchProblems,
  fetchByKeys,
  fetchOpenEpics,
  instanceMeta,
  isCalendarDate,
  jiraAuth,
  jiraBaseUrl,
  setEpic,
  setInstanceMetaForTests,
  setStartDate,
  suggestStartDate,
  toJiraItem,
} from '@/lib/integrations/jiraApi';
import changelogFixture from '../../fixtures/jira-changelog.json';
import statusesFixture from '../../fixtures/jira-statuses.json';
import flaggedFixture from '../../fixtures/jira-flagged-search.json';
import backlogToDoneChangelog from '../../fixtures/jira-changelog-backlog-to-done.json';
import backlogToDoneIssue from '../../fixtures/jira-issue-backlog-to-done.json';
import type { Connection } from '@/lib/vault/connections';

const CONN = {
  id: 'c1',
  module: 'jira',
  label: 'Jira',
  values: { cloud: 'acme', email: 'eu@acme.com', token: 'segredo' },
} as unknown as Connection;

/** Devolve o corpo da última chamada, que é onde a JQL viaja. */
function stubSearch(issues: unknown[]) {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => ({ issues }),
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function jqlOf(fetchMock: ReturnType<typeof vi.fn>, call = 0): string {
  return JSON.parse(fetchMock.mock.calls[call][1].body).jql;
}

/** Uma resposta diferente por chamada, na ordem em que `fetchIssues` pergunta:
 *  responsável, relator e aprovação. */
function stubSearchSequence(respostas: unknown[][]) {
  const fetchMock = vi.fn();
  for (const issues of respostas) {
    fetchMock.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ issues }) });
  }
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function issue(key: string, over: Record<string, unknown> = {}) {
  return {
    key,
    fields: {
      summary: `Resumo de ${key}`,
      status: { name: 'Aprovação', statusCategory: { key: 'indeterminate' } },
      project: { key: key.split('-')[0] },
      issuetype: { name: '[System] Service request', subtask: false },
      updated: '2026-09-08T18:00:00.000-0300',
      ...over,
    },
  };
}

const BASE_URL = 'https://acme.atlassian.net';
const EMPTY_META = { startField: null, flaggedField: null, priorityRank: new Map<string, number>() };

// Os metadados da instância ficam em cache no processo. Cada teste começa com
// eles já resolvidos e vazios, para a sequência de respostas falsas ser só a
// das buscas; quem testa a descoberta limpa o cache.
beforeEach(() => setInstanceMetaForTests(BASE_URL, EMPTY_META));
afterEach(() => {
  vi.unstubAllGlobals();
  setInstanceMetaForTests(BASE_URL, null);
});

describe('jiraBaseUrl', () => {
  it('aceita o nome, o domínio e a URL inteira', () => {
    expect(jiraBaseUrl('acme')).toBe('https://acme.atlassian.net');
    expect(jiraBaseUrl('acme.atlassian.net')).toBe('https://acme.atlassian.net');
    expect(jiraBaseUrl('https://acme.atlassian.net/')).toBe('https://acme.atlassian.net');
  });
});

describe('fetchDelivered', () => {
  // O nome do status final é livre por workflow — aqui é "Resolvido" e
  // "Fechado", em outra instância é "Done". Depender do nome quebraria fora
  // desta instância; a categoria e o histórico de transição, não.
  it('pergunta pelo que você encerrou hoje sem citar nome de status', async () => {
    const fetchMock = stubSearch([]);
    await fetchDelivered(CONN);

    const jql = jqlOf(fetchMock, 1);
    expect(jql).toContain('statusCategory = Done');
    expect(jql).toContain('status CHANGED BY currentUser() DURING (startOfDay(), now())');
    expect(jql).toContain('assignee = currentUser() AND resolved >= startOfDay()');
    expect(jql).not.toMatch(/Resolvido|Fechado|Done"/);
  });

  // Duas janelas numa passada: a lista é a dos sete dias, e a segunda busca
  // diz quais dessas caem em hoje. Assim trocar o período no painel não custa
  // uma ida ao Jira, e o corte do dia continua sendo o do Jira.
  it('pergunta pelas duas janelas, sete dias e hoje', async () => {
    const fetchMock = stubSearch([]);
    await fetchDelivered(CONN);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(jqlOf(fetchMock, 0)).toContain('startOfDay(-7d)');
    expect(jqlOf(fetchMock, 1)).toContain('DURING (startOfDay(), now())');
    expect(jqlOf(fetchMock, 1)).not.toContain('-7d');
  });

  it('traz a issue com a situação e o link de abrir', async () => {
    stubSearch([
      {
        key: 'PDS-10',
        fields: {
          summary: 'Ajuste do cashback',
          status: { name: 'Resolvido', statusCategory: { key: 'done' } },
          project: { key: 'PDS' },
          issuetype: { name: 'História', subtask: false },
          updated: '2026-08-31T18:00:00.000-0300',
        },
      },
    ]);

    const [item] = await fetchDelivered(CONN);
    expect(item.key).toBe('PDS-10');
    expect(item.statusCategory).toBe('done');
    expect(item.status).toBe('Resolvido');
    expect(item.url).toBe('https://acme.atlassian.net/browse/PDS-10');
  });
});

describe('fetchIssues: aguardando a minha aprovação', () => {
  // `approvals = myPending()` é a única forma que a instância aceita
  // (`pendingBy(currentUser())` devolve erro de sintaxe), e é ela que
  // distingue o que espera por você do que apenas está num status chamado
  // "Aprovação" — que pode estar esperando outra pessoa.
  it('pergunta pelas aprovações pendentes sem citar nome de status', async () => {
    const fetchMock = stubSearchSequence([[], [], []]);
    await fetchIssues(CONN, 'both');

    const jql = jqlOf(fetchMock, 2);
    expect(jql).toContain('approvals = myPending()');
    expect(jql).not.toMatch(/status\s*=/);
  });

  it('marca a issue que espera pela sua aprovação', async () => {
    stubSearchSequence([[], [], [issue('PDS-2138')]]);

    const items = await fetchIssues(CONN, 'both');

    expect(items).toHaveLength(1);
    expect(items[0].key).toBe('PDS-2138');
    expect(items[0].awaitingApproval).toBe(true);
  });

  it('não marca aprovação em issue que veio por responsável ou relator', async () => {
    stubSearchSequence([[issue('TT-1')], [issue('TT-2')], []]);

    const items = await fetchIssues(CONN, 'both');

    expect(items.map((i) => i.awaitingApproval)).toEqual([false, false]);
  });

  // Ser o responsável e o aprovador ao mesmo tempo é comum em mudança: a
  // issue é uma só, e sumir com o papel dela ao ganhar o selo seria perder
  // informação que a lista já mostrava.
  it('mantém uma linha só quando a issue também é sua, somando os dois papéis', async () => {
    stubSearchSequence([[issue('PDS-2130')], [], [issue('PDS-2130')]]);

    const items = await fetchIssues(CONN, 'both');

    expect(items).toHaveLength(1);
    expect(items[0].role).toBe('assignee');
    expect(items[0].awaitingApproval).toBe(true);
  });

  // O filtro por papel recorta o que é seu; a aprovação não é um papel seu na
  // issue, e ainda assim precisa aparecer. Buscá-la sempre é o que permite ao
  // painel mostrá-la independentemente do filtro escolhido.
  it('busca as aprovações mesmo quando o filtro é só responsável', async () => {
    const fetchMock = stubSearchSequence([[], []]);
    await fetchIssues(CONN, 'assignee');

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(jqlOf(fetchMock, 1)).toContain('approvals = myPending()');
  });
});

describe('recorte por período', () => {
  // A lista devolvida é a dos sete dias; `today` é o que o painel usa para
  // mostrar só o dia sem voltar ao servidor.
  it('marca como de hoje só o que veio na janela do dia', async () => {
    const fetchMock = vi.fn();
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ issues: [issue('PDS-1'), issue('PDS-2')] }),
    });
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ issues: [issue('PDS-2')] }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const items = await fetchDelivered(CONN);

    expect(items.map((i) => [i.key, i.today])).toEqual([
      ['PDS-1', false],
      ['PDS-2', true],
    ]);
  });
});

describe('fetchApproved', () => {
  // Não existe função JQL para "aprovadas por mim": `myApproved()` e
  // `approvedBy(currentUser())` são recusadas, e `approved()` sozinho traz o
  // que qualquer pessoa aprovou. O que restringe a você é a transição de
  // saída do status de aprovação ter sido sua.
  it('cruza a aprovação com a transição feita por você', async () => {
    const fetchMock = stubSearch([]);
    await fetchApproved(CONN);

    const jql = jqlOf(fetchMock);
    expect(jql).toContain('approvals = approved()');
    expect(jql).toContain('status CHANGED FROM "Aprovação" BY currentUser()');
  });

  it('pergunta pelas duas janelas, sete dias e hoje', async () => {
    const fetchMock = stubSearch([]);
    await fetchApproved(CONN);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(jqlOf(fetchMock, 0)).toContain('startOfDay(-7d)');
    expect(jqlOf(fetchMock, 1)).toContain('DURING (startOfDay(), now())');
  });

  it('traz a issue com o link de abrir', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ issues: [issue('PDS-2147')] }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const [item] = await fetchApproved(CONN);
    expect(item.key).toBe('PDS-2147');
    expect(item.url).toBe('https://acme.atlassian.net/browse/PDS-2147');
    expect(item.today).toBe(true);
  });
});

describe('fetchProblems', () => {
  const FIELDS_RESPONSE = [
    { id: 'summary', name: 'Summary' },
    { id: 'customfield_10015', name: 'Start date' },
  ];

  /** Responde pela rota: a lista de campos numa, as buscas em sequência na
   *  outra. Devolve o mock para conferir o que foi perguntado. */
  function stubJira(searches: unknown[], fields: unknown = FIELDS_RESPONSE) {
    setInstanceMetaForTests(BASE_URL, null);
    const pending = [...searches];
    const fetchMock = vi.fn(async (url: string) => {
      const body = url.endsWith('/rest/api/3/field')
        ? fields
        : url.endsWith('/rest/api/3/priority')
          ? []
          : pending.shift();
      return { ok: true, status: 200, json: async () => body };
    });
    vi.stubGlobal('fetch', fetchMock);
    return fetchMock;
  }

  const searchBodies = (fetchMock: ReturnType<typeof vi.fn>) =>
    fetchMock.mock.calls
      .filter(([url]) => String(url).endsWith('/search/jql'))
      .map(([, init]) => JSON.parse(init.body));

  const story = (key: string, over: Record<string, unknown> = {}) =>
    issue(key, {
      issuetype: { name: 'História', subtask: false },
      status: { name: 'Em andamento', statusCategory: { key: 'indeterminate' } },
      parent: { key: 'DAD-1', fields: { summary: 'Épico' } },
      customfield_10015: '2026-09-01',
      ...over,
    });

  const epic = (key: string, over: Record<string, unknown> = {}) =>
    issue(key, { issuetype: { name: 'Epic', subtask: false }, ...over });

  it('deixa de fora a história arquivada', async () => {
    const arquivada = { name: 'Arquivado', statusCategory: { key: 'done' } };
    const fetchMock = stubJira([
      {
        issues: [
          story('DAD-2', { status: arquivada, customfield_10015: null }),
          story('DAD-3', { customfield_10015: null }),
        ],
      },
    ]);
    const found = await fetchProblems(CONN);

    // A exclusão não vai para a JQL: o status pode não existir na instância.
    expect(searchBodies(fetchMock)[0].jql).not.toContain('Arquivado');
    expect(found.map((i) => i.key)).toEqual(['DAD-3']);
  });

  it('lê a data de início pelo campo descoberto', async () => {
    const fetchMock = stubJira([
      { issues: [story('DAD-2', { customfield_10015: null }), story('DAD-3')] },
    ]);
    const found = await fetchProblems(CONN);

    const [scope] = searchBodies(fetchMock);
    expect(scope.fields).toEqual(expect.arrayContaining(['customfield_10015']));
    expect(scope.jql).toContain('assignee = currentUser() AND');
    expect(scope.jql).not.toContain('reporter');
    expect(found.map((i) => [i.key, i.problems])).toEqual([
      ['DAD-2', ['story-in-progress-without-start']],
    ]);
    expect(found[0].url).toBe('https://acme.atlassian.net/browse/DAD-2');
  });

  it('busca as filhas de todos os épicos numa consulta só', async () => {
    const fetchMock = stubJira([
      { issues: [epic('DAD-1'), epic('DAD-9'), epic('DAD-20')] },
      { issues: [story('DAD-5')] },
    ]);
    const found = await fetchProblems(CONN);

    const bodies = searchBodies(fetchMock);
    expect(bodies).toHaveLength(2);
    expect(bodies[1].jql).toBe('parent in ("DAD-1", "DAD-9", "DAD-20")');
    expect(found.map((i) => i.key)).toEqual(['DAD-9', 'DAD-20']);
  });

  it('não busca filhas quando não há épico', async () => {
    const fetchMock = stubJira([{ issues: [story('DAD-3')] }]);
    await fetchProblems(CONN);
    expect(searchBodies(fetchMock)).toHaveLength(1);
  });

  // Uma filha na segunda página que ficasse de fora faria o épico parecer
  // sem histórias.
  it('segue as páginas até a última', async () => {
    const fetchMock = stubJira([
      { issues: [epic('DAD-1')], nextPageToken: 'p2', isLast: false },
      { issues: [epic('DAD-7')], isLast: true },
      { issues: [story('DAD-5', { parent: { key: 'DAD-7', fields: { summary: 'x' } } })] },
    ]);
    const found = await fetchProblems(CONN);

    const bodies = searchBodies(fetchMock);
    expect(bodies[1].nextPageToken).toBe('p2');
    expect(bodies[2].jql).toBe('parent in ("DAD-1", "DAD-7")');
    expect(found.map((i) => i.key)).toEqual(['DAD-1']);
  });

  it('para com erro em vez de cortar a lista em silêncio', async () => {
    const page = { issues: [], nextPageToken: 'mais', isLast: false };
    stubJira(Array.from({ length: 20 }, () => page));
    await expect(fetchProblems(CONN)).rejects.toThrow('passou de 1000 issues');
  });

  it('diz que não dá para checar quando o campo de início não existe', async () => {
    const fetchMock = stubJira([], [{ id: 'summary', name: 'Summary' }]);
    await expect(fetchProblems(CONN)).rejects.toThrow('campo "Start date" não encontrado');
    expect(searchBodies(fetchMock)).toHaveLength(0);
  });

  it('reconhece o campo pelo nome em português', async () => {
    const fetchMock = stubJira([{ issues: [] }], [{ id: 'customfield_1', name: 'Data de início' }]);
    await fetchProblems(CONN);
    expect(searchBodies(fetchMock)[0].fields).toContain('customfield_1');
  });
});

import { searchPeople, fetchPerson, ME } from '@/lib/integrations/jiraApi';

describe('JiraSubject (fetch by person)', () => {
  const PERSON = { kind: 'person' as const, accountId: '123:abc' };

  it('fetchIssues usa conta específica e não currentUser', async () => {
    const fetchMock = stubSearchSequence([[], [], []]);
    await fetchIssues(CONN, 'both', PERSON);

    expect(jqlOf(fetchMock, 0)).toContain('assignee = "123:abc"');
    expect(jqlOf(fetchMock, 1)).toContain('reporter = "123:abc"');
    expect(jqlOf(fetchMock, 2)).toContain('approvals = pendingBy("123:abc")');
    expect(jqlOf(fetchMock, 0)).not.toContain('currentUser()');
  });

  it('fetchDelivered usa conta específica e não currentUser', async () => {
    const fetchMock = stubSearchSequence([[], []]);
    await fetchDelivered(CONN, PERSON);

    expect(jqlOf(fetchMock, 0)).toContain('CHANGED BY "123:abc"');
    expect(jqlOf(fetchMock, 0)).toContain('assignee = "123:abc"');
    expect(jqlOf(fetchMock, 0)).not.toContain('currentUser()');
  });

  it('fetchApproved usa conta específica e não currentUser', async () => {
    const fetchMock = stubSearchSequence([[], []]);
    await fetchApproved(CONN, PERSON);

    expect(jqlOf(fetchMock, 0)).toContain('CHANGED FROM "Aprovação" BY "123:abc"');
    expect(jqlOf(fetchMock, 0)).not.toContain('currentUser()');
  });

  it('fetchProblems usa conta específica e não currentUser', async () => {
    setInstanceMetaForTests(BASE_URL, { ...EMPTY_META, startField: 'customfield_10015' });
    const fetchMock = vi.fn();
    fetchMock.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ issues: [] }) });
    vi.stubGlobal('fetch', fetchMock);

    await fetchProblems(CONN, PERSON);

    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body.jql).toContain('assignee = "123:abc" AND');
    expect(body.jql).not.toContain('reporter');
    expect(body.jql).not.toContain('currentUser()');
  });

  it('rejeita accountId inválido antes de qualquer requisição', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    await expect(fetchIssues(CONN, 'both', { kind: 'person', accountId: '" OR 1=1' })).rejects.toThrow('conta do Jira inválida');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('searchPeople & fetchPerson', () => {
  it('searchPeople filtra não-atlassian e inativos e encoda url', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ([
        { accountId: '123:abc', accountType: 'atlassian', active: true, displayName: 'Ana', emailAddress: 'a@a.com' },
        { accountId: '456:def', accountType: 'app', active: true, displayName: 'Bot' },
        { accountId: '789:ghi', accountType: 'atlassian', active: false, displayName: 'Inativo' },
      ])
    });
    vi.stubGlobal('fetch', fetchMock);

    const people = await searchPeople(CONN, 'Ana S');
    expect(fetchMock.mock.calls[0][0]).toContain('query=Ana%20S');
    expect(people).toEqual([{ accountId: '123:abc', displayName: 'Ana' }]);
  });

  it('fetchPerson retorna null no 404 e throw no 401', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: false, status: 404, text: async () => '' });
    vi.stubGlobal('fetch', fetchMock);
    expect(await fetchPerson(CONN, '123')).toBeNull();

    fetchMock.mockResolvedValue({ ok: false, status: 401, text: async () => '' });
    await expect(fetchPerson(CONN, '123')).rejects.toThrow('Jira recusou o e-mail');
  });
});

describe('fetchAncestors', () => {
  // A entrada da subida é o que as buscas do painel produzem, então o item
  // vem do mesmo conversor que elas usam, e não de um objeto montado à mão.
  const item = (key: string, parent?: string) =>
    toJiraItem(
      issue(key, parent ? { parent: { key: parent, fields: { summary: `pai ${parent}` } } } : {}),
      'https://acme.atlassian.net',
      'assignee',
    );

  it('sobe de pai em pai até o topo, uma ida por nível', async () => {
    const fetchMock = stubSearchSequence([
      [issue('TT-5', { parent: { key: 'TT-2', fields: { summary: 'iniciativa' } } })],
      [issue('TT-2', { parent: { key: 'TT-1', fields: { summary: 'objetivo' } } })],
      [issue('TT-1')],
    ]);

    const ancestors = await fetchAncestors(CONN, [item('TT-9', 'TT-5')]);

    expect(ancestors.map((i) => i.key)).toEqual(['TT-5', 'TT-2', 'TT-1']);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(jqlOf(fetchMock, 0)).toBe('key in ("TT-5")');
    expect(jqlOf(fetchMock, 2)).toBe('key in ("TT-1")');
  });

  it('pergunta pelas chaves do nível de uma vez, sem repetir a que se repete', async () => {
    const fetchMock = stubSearchSequence([[issue('TT-5'), issue('TT-6')]]);

    await fetchAncestors(CONN, [item('TT-9', 'TT-5'), item('TT-8', 'TT-5'), item('TT-7', 'TT-6')]);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(jqlOf(fetchMock, 0)).toBe('key in ("TT-5", "TT-6")');
  });

  it('não busca o pai que já está na lista', async () => {
    const fetchMock = stubSearchSequence([[]]);
    const ancestors = await fetchAncestors(CONN, [item('TT-5'), item('TT-9', 'TT-5')]);
    expect(ancestors).toEqual([]);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('não volta para a filha quando o pai aponta de volta para ela', async () => {
    const fetchMock = stubSearchSequence([
      [issue('TT-5', { parent: { key: 'TT-9', fields: { summary: 'volta' } } })],
    ]);

    const ancestors = await fetchAncestors(CONN, [item('TT-9', 'TT-5')]);

    expect(ancestors.map((i) => i.key)).toEqual(['TT-5']);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // Uma corrente mais longa que o teto é defeito de dado, e a subida precisa
  // terminar mesmo assim.
  it('para no teto de níveis numa corrente sem fim', async () => {
    const fetchMock = vi.fn();
    let n = 100;
    fetchMock.mockImplementation(async () => {
      const key = `TT-${n}`;
      n += 1;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          issues: [issue(key, { parent: { key: `TT-${n}`, fields: { summary: 'acima' } } })],
        }),
      };
    });
    vi.stubGlobal('fetch', fetchMock);

    const ancestors = await fetchAncestors(CONN, [item('TT-9', 'TT-100')]);

    expect(fetchMock).toHaveBeenCalledTimes(6);
    expect(ancestors).toHaveLength(6);
  });

  it('não vai ao Jira quando não há issue nenhuma', async () => {
    const fetchMock = stubSearch([]);
    expect(await fetchAncestors(CONN, [])).toEqual([]);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

/** Responde pelo caminho da URL; o que não tem rota é um erro do teste. */
function stubRoutes(routes: Record<string, unknown | ((init: RequestInit | undefined) => unknown)>) {
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    const { pathname } = new URL(url);
    if (!(pathname in routes)) throw new Error(`rota não esperada: ${pathname}`);
    const route = routes[pathname];
    const body = typeof route === 'function' ? route(init) : route;
    if (body === 204) return { ok: true, status: 204, json: async () => null };
    return { ok: true, status: 200, json: async () => body };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const META = {
  startField: 'customfield_10015',
  flaggedField: 'customfield_10021',
  priorityRank: new Map([['1', 0], ['2', 1], ['3', 2], ['4', 3], ['5', 4]]),
};

describe('metadados da instância', () => {
  it('descobre a bandeira, a data de início e a ordem das prioridades uma vez só', async () => {
    setInstanceMetaForTests(BASE_URL, null);
    const fetchMock = stubRoutes({
      '/rest/api/3/field': [
        { id: 'customfield_10021', name: 'Flagged' },
        { id: 'customfield_10015', name: 'Data de início' },
      ],
      '/rest/api/3/priority': [{ id: '1' }, { id: '5' }],
    });
    const auth = jiraAuth(CONN);

    const [primeira, segunda] = await Promise.all([instanceMeta(auth), instanceMeta(auth)]);
    await instanceMeta(auth);

    expect(primeira).toBe(segunda);
    expect(primeira.startField).toBe('customfield_10015');
    expect(primeira.flaggedField).toBe('customfield_10021');
    expect([...primeira.priorityRank]).toEqual([['1', 0], ['5', 1]]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('sem metadados a busca segue, e a falha não fica guardada', async () => {
    setInstanceMetaForTests(BASE_URL, null);
    const fetchMock = vi.fn(async (url: string) => {
      if (url.endsWith('/search/jql')) return { ok: true, status: 200, json: async () => ({ issues: [issue('TT-1')] }) };
      return { ok: false, status: 500, text: async () => 'fora do ar' };
    });
    vi.stubGlobal('fetch', fetchMock);

    const items = await fetchByKeys(CONN, ['TT-1']);
    expect(items[0].flag).toBe('none');
    expect(items[0].priority).toBeNull();

    await fetchByKeys(CONN, ['TT-1']);
    const metaCalls = fetchMock.mock.calls.filter(([url]) => String(url).endsWith('/rest/api/3/field'));
    expect(metaCalls).toHaveLength(2);
  });
});

describe('prioridade e impedimento', () => {
  // A resposta é a de uma issue impedida de verdade, capturada do Jira.
  it('lê a bandeira e a prioridade pelo campo descoberto', async () => {
    setInstanceMetaForTests(BASE_URL, META);
    const fetchMock = stubSearch(flaggedFixture.issues.map((i) => issue(i.key, i.fields)));

    const [item] = await fetchByKeys(CONN, ['TT-2343']);

    expect(item.flag).toBe('impediment');
    expect(item.priority).toEqual({ name: 'Trivial', rank: 4 });
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).fields).toEqual(
      expect.arrayContaining(['priority', 'customfield_10021']),
    );
  });

  it('bandeira vazia ou nula não é impedimento', async () => {
    setInstanceMetaForTests(BASE_URL, META);
    stubSearch([issue('TT-1', { customfield_10021: null }), issue('TT-2', { customfield_10021: [] })]);
    const items = await fetchByKeys(CONN, ['TT-1', 'TT-2']);
    expect(items.map((i) => i.flag)).toEqual(['none', 'none']);
  });

  it('prioridade fora da ordem conhecida aparece sem posição', async () => {
    setInstanceMetaForTests(BASE_URL, META);
    stubSearch([issue('TT-1', { priority: { id: '99', name: 'Nova' } })]);
    const [item] = await fetchByKeys(CONN, ['TT-1']);
    expect(item.priority).toEqual({ name: 'Nova', rank: null });
  });

  it('toJiraItem sem a busca não inventa bandeira nem posição', () => {
    const item = toJiraItem(issue('TT-1', { priority: { id: '1', name: 'Crítica' } }), BASE_URL, 'assignee');
    expect(item.flag).toBe('none');
    expect(item.priority).toEqual({ name: 'Crítica', rank: null });
  });
});

describe('suggestStartDate', () => {
  /** A issue em si: quando foi criada e em que situação está agora. */
  const issueNow = (created: string, category: 'new' | 'indeterminate' | 'done') => ({
    fields: { created, status: { statusCategory: { key: category } } },
  });

  // O histórico real: o card foi criado, ganhou data de início à mão e só
  // depois entrou em "Em Andamento". O que vale é a passagem pelo status.
  it('usa o dia da primeira passagem por um status em andamento', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-5016': issueNow('2026-10-20T15:46:00.000-0300', 'indeterminate'),
      '/rest/api/3/issue/TT-5016/changelog': changelogFixture,
    });
    expect(await suggestStartDate(CONN, 'TT-5016')).toEqual({ date: '2026-10-20', basis: 'started' });
  });

  // O caso que o painel deixava em branco: a história foi de Backlog direto
  // para Concluído. Histórico real, de TT-4898.
  it('sem passagem por andamento, usa o dia em que saiu do Backlog', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-4898': backlogToDoneIssue,
      '/rest/api/3/issue/TT-4898/changelog': backlogToDoneChangelog,
    });
    expect(await suggestStartDate(CONN, 'TT-4898')).toEqual({ date: '2026-10-19', basis: 'finished' });
  });

  it('prefere a passagem por andamento mesmo depois de uma conclusão anterior', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-1': issueNow('2026-10-01T10:00:00.000-0300', 'indeterminate'),
      '/rest/api/3/issue/TT-1/changelog': {
        isLast: true,
        values: [
          { created: '2026-10-02T10:00:00.000-0300', items: [{ fieldId: 'status', to: '10104' }] },
          { created: '2026-10-05T10:00:00.000-0300', items: [{ fieldId: 'status', to: '11540' }] },
        ],
      },
    });
    expect(await suggestStartDate(CONN, 'TT-1')).toEqual({ date: '2026-10-05', basis: 'started' });
  });

  it('pega a mais antiga mesmo quando o histórico vem fora de ordem', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-1': issueNow('2026-10-01T10:00:00.000-0300', 'indeterminate'),
      '/rest/api/3/issue/TT-1/changelog': {
        isLast: true,
        values: [
          { created: '2026-10-12T09:00:00.000-0300', items: [{ fieldId: 'status', to: '11298' }] },
          { created: '2026-10-05T23:30:00.000-0300', items: [{ fieldId: 'status', to: '11540' }] },
        ],
      },
    });
    expect(await suggestStartDate(CONN, 'TT-1')).toEqual({ date: '2026-10-05', basis: 'started' });
  });

  it('criada já fora do Backlog e sem transição, usa o dia da criação', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-1': issueNow('2026-10-07T22:10:00.000-0300', 'indeterminate'),
      '/rest/api/3/issue/TT-1/changelog': { isLast: true, values: [] },
    });
    expect(await suggestStartDate(CONN, 'TT-1')).toEqual({ date: '2026-10-07', basis: 'created' });
  });

  it('nulo quando a issue nunca saiu do Backlog', async () => {
    stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-1': issueNow('2026-10-07T22:10:00.000-0300', 'new'),
      '/rest/api/3/issue/TT-1/changelog': {
        isLast: true,
        values: [{ created: '2026-10-08T10:00:00.000-0300', items: [{ fieldId: 'status', to: '10175' }] }],
      },
    });
    expect(await suggestStartDate(CONN, 'TT-1')).toBeNull();
  });

  it('segue as páginas do histórico', async () => {
    let pagina = 0;
    const fetchMock = stubRoutes({
      '/rest/api/3/status': statusesFixture,
      '/rest/api/3/issue/TT-1': issueNow('2026-09-01T10:00:00.000-0300', 'indeterminate'),
      '/rest/api/3/issue/TT-1/changelog': () =>
        pagina++ === 0
          ? { isLast: false, values: [] }
          : { isLast: true, values: [{ created: '2026-09-30T10:00:00.000-0300', items: [{ fieldId: 'status', to: '3' }] }] },
    });
    expect(await suggestStartDate(CONN, 'TT-1')).toEqual({ date: '2026-09-30', basis: 'started' });
    const urls = fetchMock.mock.calls.map(([url]) => String(url)).filter((u) => u.includes('changelog'));
    expect(urls[1]).toContain('startAt=100');
  });

  it('recusa chave inválida antes de ir ao Jira', async () => {
    const fetchMock = stubRoutes({});
    await expect(suggestStartDate(CONN, 'TT-1/../x')).rejects.toThrow('chave inválida');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('setStartDate', () => {
  it('grava a data no campo descoberto', async () => {
    setInstanceMetaForTests(BASE_URL, META);
    const fetchMock = stubRoutes({ '/rest/api/3/issue/TT-1': 204 });
    await setStartDate(CONN, 'TT-1', '2026-10-20');
    const [, init] = fetchMock.mock.calls[0];
    expect(init?.method).toBe('PUT');
    expect(JSON.parse(String(init?.body))).toEqual({ fields: { customfield_10015: '2026-10-20' } });
  });

  it.each(['2026-02-30', '20/10/2026', '', '2026-10-20T00:00'])('recusa a data %s', async (date) => {
    const fetchMock = stubRoutes({});
    await expect(setStartDate(CONN, 'TT-1', date)).rejects.toThrow('data inválida');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('erro claro quando a instância não tem o campo', async () => {
    stubRoutes({});
    await expect(setStartDate(CONN, 'TT-1', '2026-10-20')).rejects.toThrow('campo "Start date" não encontrado');
  });
});

describe('isCalendarDate', () => {
  it('aceita só dia que existe', () => {
    expect(isCalendarDate('2024-02-29')).toBe(true);
    expect(isCalendarDate('2026-02-29')).toBe(false);
    expect(isCalendarDate(20261020)).toBe(false);
  });
});

describe('épicos', () => {
  const epic = (key: string, project = key.split('-')[0]) =>
    issue(key, { project: { key: project }, issuetype: { name: 'Epic', subtask: false, hierarchyLevel: 1 } });

  it('lista só os épicos abertos do projeto, pelo degrau da hierarquia', async () => {
    const fetchMock = stubSearch([epic('TT-10'), issue('TT-11', { issuetype: { name: 'Epic', hierarchyLevel: 0 } })]);
    const epicos = await fetchOpenEpics(CONN, 'TT');
    expect(epicos.map((e) => e.key)).toEqual(['TT-10']);
    expect(jqlOf(fetchMock)).toBe('project = "TT" AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC');
  });

  it('recusa projeto fora do formato', async () => {
    const fetchMock = stubSearch([]);
    await expect(fetchOpenEpics(CONN, 'TT" OR 1=1')).rejects.toThrow('projeto inválido');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('põe a história sob o épico depois de conferir que ele é épico do mesmo projeto', async () => {
    const calls: { method?: string; body?: unknown }[] = [];
    vi.stubGlobal('fetch', vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ method: init?.method, body: init?.body ? JSON.parse(String(init.body)) : undefined });
      if (url.endsWith('/search/jql')) return { ok: true, status: 200, json: async () => ({ issues: [epic('TT-10')] }) };
      return { ok: true, status: 204, json: async () => null };
    }));

    await setEpic(CONN, 'TT-5', 'TT-10');

    expect((calls[0].body as { jql: string }).jql).toBe('key = "TT-10"');
    expect(calls[1]).toEqual({ method: 'PUT', body: { fields: { parent: { key: 'TT-10' } } } });
  });

  it('não grava quando o pai não é épico', async () => {
    const fetchMock = stubSearch([issue('TT-10', { issuetype: { name: 'História', hierarchyLevel: 0 } })]);
    await expect(setEpic(CONN, 'TT-5', 'TT-10')).rejects.toThrow('TT-10 não é um épico');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('não grava quando o épico não existe', async () => {
    stubSearch([]);
    await expect(setEpic(CONN, 'TT-5', 'TT-10')).rejects.toThrow('não é um épico');
  });

  it('não grava épico de outro projeto', async () => {
    const fetchMock = stubSearch([epic('CYB-10')]);
    await expect(setEpic(CONN, 'TT-5', 'CYB-10')).rejects.toThrow('CYB-10 é de outro projeto');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('o erro de permissão do Jira chega à tela', async () => {
    vi.stubGlobal('fetch', vi.fn(async (url: string) => {
      if (url.endsWith('/search/jql')) return { ok: true, status: 200, json: async () => ({ issues: [epic('TT-10')] }) };
      return { ok: false, status: 403, text: async () => '' };
    }));
    await expect(setEpic(CONN, 'TT-5', 'TT-10')).rejects.toThrow('não tem permissão');
  });
});
