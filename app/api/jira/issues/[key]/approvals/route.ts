import { ExternalNotSubmittedError } from '@/lib/access/receipts';
import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { type ApprovalDecision } from '@/lib/integrations/jira/approvals';

type Params = { params: Promise<{ key: string }> };

const DECISIONS: readonly ApprovalDecision[] = ['approve', 'decline'];

function badRequest(error: string): NextResponse {
  return NextResponse.json({ error }, { status: 400 });
}

export async function GET(_request: NextRequest, { params }: Params) {
  const guard = await requireJira();
  if (!guard.ok) return guard.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  try {
    const approvals = await jiraActions.approvals(guard.value.connection, key);
    return NextResponse.json({ approvals });
  } catch (err) {
    if (err instanceof ExternalNotSubmittedError) return NextResponse.json({error: err.message}, {status:409});
    return upstreamError(err);
  }
}

export async function POST(request: NextRequest, { params }: Params) {
  const guard = await requireJira();
  if (!guard.ok) return guard.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const body: unknown = await request.json().catch(() => null);
  if (typeof body !== 'object' || body === null) return badRequest('corpo inválido');
  const { approvalId, decision } = body as Record<string, unknown>;
  if (typeof approvalId !== 'string' || !/^\d{1,18}$/.test(approvalId)) {
    return badRequest('approvalId inválido');
  }
  if (typeof decision !== 'string' || !DECISIONS.includes(decision as ApprovalDecision)) {
    return badRequest('decision deve ser approve ou decline');
  }

  try {
    await jiraActions.answerApproval({userId: guard.value.user.id, connection: guard.value.connection}, key, approvalId, decision as ApprovalDecision);
    return writeDone(guard.value.user.id);
  } catch (err) {
    if (err instanceof ExternalNotSubmittedError) return NextResponse.json({error: err.message}, {status:409});
    return upstreamError(err);
  }
}
