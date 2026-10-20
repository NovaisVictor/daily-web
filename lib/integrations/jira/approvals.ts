import { jiraRequest, type JiraAuth } from '@/lib/integrations/jiraApi';
import { isRecord, unexpected as unexpectedIn } from '@/lib/integrations/jira/parse';

export type ApprovalDecision = 'approve' | 'decline';

export type FinalDecision = 'approved' | 'declined' | 'pending';

export interface Approval {
  id: string;
  name: string;
  finalDecision: FinalDecision;
  canAnswerApproval: boolean;
}

export interface PendingApproval {
  id: string;
  name: string;
}

export interface ApprovalPage {
  values: Approval[];
  isLastPage: boolean;
}

const PAGE_SIZE = 50;
const MAX_PAGES = 10;
const FINAL_DECISIONS: readonly FinalDecision[] = ['approved', 'declined', 'pending'];

const unexpected = (detail: string) => unexpectedIn('para aprovações', detail);

export function parseApproval(raw: unknown): Approval {
  if (!isRecord(raw)) throw unexpected('aprovação não é um objeto');
  const { id, name, finalDecision, canAnswerApproval } = raw;
  if (typeof id !== 'string' || !/^\d+$/.test(id)) throw unexpected('id da aprovação ausente ou inválido');
  if (typeof name !== 'string') throw unexpected(`aprovação ${id} sem nome`);
  if (typeof finalDecision !== 'string' || !FINAL_DECISIONS.includes(finalDecision as FinalDecision)) {
    throw unexpected(`decisão desconhecida "${String(finalDecision)}" na aprovação ${id}`);
  }
  if (typeof canAnswerApproval !== 'boolean') throw unexpected(`aprovação ${id} sem canAnswerApproval`);
  return { id, name, finalDecision: finalDecision as FinalDecision, canAnswerApproval };
}

export function parseApprovalPage(raw: unknown): ApprovalPage {
  if (!isRecord(raw)) throw unexpected('a página não é um objeto');
  if (!Array.isArray(raw.values)) throw unexpected('a página não tem "values"');
  if (typeof raw.isLastPage !== 'boolean') throw unexpected('a página não tem "isLastPage"');
  return { values: raw.values.map(parseApproval), isLastPage: raw.isLastPage };
}

export function answerable(approvals: Approval[]): PendingApproval[] {
  return approvals
    .filter((a) => a.canAnswerApproval && a.finalDecision === 'pending')
    .map(({ id, name }) => ({ id, name }));
}

function approvalsPath(key: string): string {
  return `/rest/servicedeskapi/request/${encodeURIComponent(key)}/approval`;
}

/** Only what the logged-in user can still decide. A non-service-desk issue
 *  answers 200 with an empty list, so "none" is a normal answer, not an error. */
export async function fetchPendingApprovals(auth: JiraAuth, key: string): Promise<PendingApproval[]> {
  const all: Approval[] = [];
  for (let page = 0; page < MAX_PAGES; page++) {
    const start = page * PAGE_SIZE;
    const raw = await jiraRequest(auth, `${approvalsPath(key)}?start=${start}&limit=${PAGE_SIZE}`, {
      method: 'GET',
      notFound: `issue ${key} não encontrada no Jira`,
    });
    const parsed = parseApprovalPage(raw);
    all.push(...parsed.values);
    if (parsed.isLastPage || parsed.values.length === 0) break;
  }
  return answerable(all);
}

export async function answerApproval(
  auth: JiraAuth,
  key: string,
  approvalId: string,
  decision: ApprovalDecision,
): Promise<void> {
  await jiraRequest(auth, `${approvalsPath(key)}/${encodeURIComponent(approvalId)}`, {
    method: 'POST',
    body: { decision },
    notFound: `aprovação ${approvalId} não encontrada em ${key}`,
  });
}
