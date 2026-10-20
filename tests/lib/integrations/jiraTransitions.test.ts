import { afterEach, describe, expect, it, vi } from 'vitest';
import story from '../../fixtures/jira-write/transitions-story.json';
import {
  applyTransition,
  fetchTransitions,
  parseCurrentStatusId,
  parseTransitions,
  TransitionUnavailable,
} from '@/lib/integrations/jira/transitions';
import type { Connection } from '@/lib/vault/connections';

const CONN = {
  id: 'c1',
  module: 'jira',
  label: 'Jira',
  values: { cloud: 'acme', email: 'eu@acme.com', token: 'segredo' },
} as unknown as Connection;

const IN_PROGRESS = '11540';
const ISSUE_STATUS = { fields: { status: { id: IN_PROGRESS, name: 'Em Andamento' } } };

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function ok(body: unknown) {
  return { ok: true, status: 200, json: async () => body };
}

/** Answers the two reads by URL; any write gets `write`. */
function stubJira(transitions: unknown, write: unknown = { ok: true, status: 204, json: async () => null }) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
    if (init.method === 'POST') return write;
    if (url.includes('/transitions')) return ok(transitions);
    return ok(ISSUE_STATUS);
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

afterEach(() => vi.unstubAllGlobals());

describe('parseTransitions', () => {
  it('maps the captured workflow and leaves out the transition into the current status', () => {
    const result = parseTransitions(story, IN_PROGRESS);
    expect(result).toHaveLength(10);
    expect(result.map((t) => t.id)).not.toContain('31');
    expect(result.find((t) => t.id === '41')).toEqual({
      id: '41',
      name: 'Itens concluídos',
      to: { name: 'Concluído', category: 'done' },
      requires: 'nothing',
    });
  });

  it('marks a transition with a screen as requiring the screen', () => {
    const data = clone(story);
    data.transitions[0].hasScreen = true;
    expect(parseTransitions(data, IN_PROGRESS)[0].requires).toBe('screen');
  });

  it('marks a required field without default as requiring the screen', () => {
    const data = clone(story) as { transitions: Array<Record<string, unknown>> };
    data.transitions[0].fields = { resolution: { required: true, hasDefaultValue: false } };
    expect(parseTransitions(data, IN_PROGRESS)[0].requires).toBe('screen');
  });

  it('does not ask for the screen when the required field has a default', () => {
    const data = clone(story) as { transitions: Array<Record<string, unknown>> };
    data.transitions[0].fields = { resolution: { required: true, hasDefaultValue: true } };
    expect(parseTransitions(data, IN_PROGRESS)[0].requires).toBe('nothing');
  });

  it('drops unavailable and looped transitions', () => {
    const data = clone(story);
    data.transitions[0].isAvailable = false;
    data.transitions[1].isLooped = true;
    const ids = parseTransitions(data, IN_PROGRESS).map((t) => t.id);
    expect(ids).not.toContain('2');
    expect(ids).not.toContain('3');
  });

  it('rejects an unknown status category', () => {
    const data = clone(story);
    data.transitions[0].to.statusCategory.key = 'undefined';
    expect(() => parseTransitions(data, IN_PROGRESS)).toThrow(/categoria de status desconhecida/);
  });

  it('rejects a response without the transitions list', () => {
    expect(() => parseTransitions({ expand: 'transitions' }, IN_PROGRESS)).toThrow(/lista de transições ausente/);
  });

  it('rejects an issue response without a status id', () => {
    expect(() => parseCurrentStatusId({ fields: {} })).toThrow(/status atual/);
  });
});

describe('fetchTransitions', () => {
  it('reads the transitions with fields expanded and the current status', async () => {
    const fetchMock = stubJira(story);
    const result = await fetchTransitions(CONN, 'TT-5019');
    expect(result).toHaveLength(10);
    const urls = fetchMock.mock.calls.map(([url]) => url);
    expect(urls).toContain('https://acme.atlassian.net/rest/api/3/issue/TT-5019/transitions?expand=transitions.fields');
    expect(urls).toContain('https://acme.atlassian.net/rest/api/3/issue/TT-5019?fields=status');
  });
});

describe('applyTransition', () => {
  it('posts the transition id to Jira after checking it is still available', async () => {
    const fetchMock = stubJira(story);
    await applyTransition(CONN, 'TT-5019', '41');
    const post = fetchMock.mock.calls.find(([, init]) => init.method === 'POST');
    expect(post?.[0]).toBe('https://acme.atlassian.net/rest/api/3/issue/TT-5019/transitions');
    expect(JSON.parse(String(post?.[1].body))).toEqual({ transition: { id: '41' } });
  });

  it('refuses a transition that is no longer offered, without writing', async () => {
    const fetchMock = stubJira(story);
    await expect(applyTransition(CONN, 'TT-5019', '999')).rejects.toBeInstanceOf(TransitionUnavailable);
    expect(fetchMock.mock.calls.some(([, init]) => init.method === 'POST')).toBe(false);
  });

  it('refuses a transition that now requires a screen, without writing', async () => {
    const data = clone(story);
    data.transitions.find((t) => t.id === '41')!.hasScreen = true;
    const fetchMock = stubJira(data);
    await expect(applyTransition(CONN, 'TT-5019', '41')).rejects.toBeInstanceOf(TransitionUnavailable);
    expect(fetchMock.mock.calls.some(([, init]) => init.method === 'POST')).toBe(false);
  });

  it("surfaces Jira's refusal message", async () => {
    stubJira(story, {
      ok: false,
      status: 400,
      text: async () => JSON.stringify({ errorMessages: [], errors: { resolution: 'Resolução é obrigatória' } }),
    });
    await expect(applyTransition(CONN, 'TT-5019', '41')).rejects.toThrow('resolution: Resolução é obrigatória');
  });
});
