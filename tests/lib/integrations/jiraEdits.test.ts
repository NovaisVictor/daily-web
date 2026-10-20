import { describe, expect, it } from 'vitest';
import priorities from '../../fixtures/jira-write/priorities.json';
import myself from '../../fixtures/jira-write/myself.json';
import issueTypes from '../../fixtures/jira-write/createmeta-issuetypes.json';
import flagged from '../../fixtures/jira-write/issue-flagged.json';
import {
  isCalendarDate,
  parseCreatedKey,
  parseEditChange,
  parseEpicInfo,
  parseIssuePriority,
  parseMyself,
  parseNewStory,
  parsePriorities,
  pickStoryTypeId,
  toAdf,
} from '@/lib/integrations/jira/edits';

describe('parsePriorities', () => {
  it('reads the five captured priorities in order', () => {
    expect(parsePriorities(priorities)).toEqual([
      { id: '1', name: 'Crítica' },
      { id: '2', name: 'Alta' },
      { id: '3', name: 'Média' },
      { id: '4', name: 'Baixa' },
      { id: '5', name: 'Trivial' },
    ]);
  });

  it('fails visibly on an unexpected shape', () => {
    expect(() => parsePriorities({ values: priorities })).toThrow(/resposta inesperada do Jira/);
    expect(() => parsePriorities([{ id: 'x', name: 'Alta' }])).toThrow(/id da prioridade inválido/);
  });
});

describe('parseIssuePriority', () => {
  it('reads the current priority of the captured issue', () => {
    expect(parseIssuePriority(flagged)).toEqual({ id: '5', name: 'Trivial' });
  });

  it('is null when the issue has no priority', () => {
    expect(parseIssuePriority({ fields: { priority: null } })).toBeNull();
  });

  it('fails visibly without fields', () => {
    expect(() => parseIssuePriority({ key: 'TT-1' })).toThrow(/campos da issue/);
  });
});

describe('parseMyself', () => {
  it('reads the captured account id', () => {
    expect(parseMyself(myself)).toBe('557058:00000000-0000-0000-0000-000000000001');
  });

  it('refuses an account id that would not pass the account check', () => {
    expect(() => parseMyself({ accountId: 'a b|c' })).toThrow(/conta de quem está logado/);
  });
});

describe('pickStoryTypeId', () => {
  it('picks História, not Bug, among the level-0 types', () => {
    expect(pickStoryTypeId(issueTypes)).toBe('10005');
  });

  it('accepts the English name', () => {
    const types = { issueTypes: [{ id: '7', name: 'Story', subtask: false, hierarchyLevel: 0 }] };
    expect(pickStoryTypeId(types)).toBe('7');
  });

  it('says so clearly when the project has no story type', () => {
    const onlyBug = { issueTypes: issueTypes.issueTypes.filter((t) => t.name !== 'História') };
    expect(() => pickStoryTypeId(onlyBug)).toThrow(/não tem um tipo História/);
  });

  it('fails visibly on an unexpected shape', () => {
    expect(() => pickStoryTypeId({ values: [] })).toThrow(/resposta inesperada do Jira/);
    expect(() => pickStoryTypeId({ issueTypes: [{ id: '1', name: 'História' }] })).toThrow(/nível do tipo/);
  });
});

describe('parseEpicInfo', () => {
  it('reads project and hierarchy level', () => {
    const epic = { key: 'TT-2376', fields: { project: { key: 'TT' }, issuetype: { id: '10000', hierarchyLevel: 1 } } };
    expect(parseEpicInfo(epic)).toEqual({ project: 'TT', hierarchyLevel: 1 });
  });

  it('fails visibly without the issue type level', () => {
    expect(() => parseEpicInfo({ fields: { project: { key: 'TT' }, issuetype: {} } })).toThrow(/tipo da issue/);
  });
});

describe('parseCreatedKey', () => {
  it('reads the key of the created issue', () => {
    expect(parseCreatedKey({ id: '90001', key: 'TT-9999', self: 'x' })).toBe('TT-9999');
  });

  it('fails visibly without a key', () => {
    expect(() => parseCreatedKey({ id: '90001' })).toThrow(/chave da issue criada/);
  });
});

describe('parseEditChange', () => {
  it('accepts each change', () => {
    expect(parseEditChange({ change: 'due', dueDate: '2026-10-31' })).toEqual({ change: 'due', dueDate: '2026-10-31' });
    expect(parseEditChange({ change: 'due', dueDate: null })).toEqual({ change: 'due', dueDate: null });
    expect(parseEditChange({ change: 'priority', priorityId: '2' })).toEqual({ change: 'priority', priorityId: '2' });
    expect(parseEditChange({ change: 'assign-self' })).toEqual({ change: 'assign-self' });
  });

  it('refuses unknown changes and malformed values', () => {
    expect(parseEditChange({ change: 'summary', summary: 'x' })).toBeNull();
    expect(parseEditChange({ change: 'due', dueDate: '2026-02-30' })).toBeNull();
    expect(parseEditChange({ change: 'due' })).toBeNull();
    expect(parseEditChange({ change: 'priority', priorityId: 'Alta' })).toBeNull();
    expect(parseEditChange(null)).toBeNull();
  });
});

describe('isCalendarDate', () => {
  it('accepts real dates only', () => {
    expect(isCalendarDate('2028-02-29')).toBe(true);
    expect(isCalendarDate('2026-02-29')).toBe(false);
    expect(isCalendarDate('2026-1-01')).toBe(false);
  });
});

describe('parseNewStory', () => {
  it('trims summary and drops a blank description', () => {
    expect(parseNewStory({ summary: '  Nova  ', description: '  ' })).toEqual({ summary: 'Nova', description: null });
  });

  it('refuses an empty or too long summary', () => {
    expect(parseNewStory({ summary: '   ' })).toBeNull();
    expect(parseNewStory({ summary: 'x'.repeat(256) })).toBeNull();
    expect(parseNewStory({ summary: 'ok', description: 3 })).toBeNull();
  });
});

describe('toAdf', () => {
  it('makes one paragraph per non-empty line', () => {
    expect(toAdf('a\n\n b ')).toEqual({
      type: 'doc',
      version: 1,
      content: [
        { type: 'paragraph', content: [{ type: 'text', text: 'a' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'b' }] },
      ],
    });
  });
});
