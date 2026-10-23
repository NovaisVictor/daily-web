import { ProviderRefusal } from '@/lib/integrations/refusal';
import { githubRequest, isRecord, unexpected } from './client';

export interface PullRef {
  owner: string;
  repo: string;
  number: number;
}

export type ReviewEvent = 'APPROVE' | 'REQUEST_CHANGES';
export const REVIEW_EVENTS: readonly ReviewEvent[] = ['APPROVE', 'REQUEST_CHANGES'];

export type MergeMethod = 'merge' | 'squash' | 'rebase';
export const MERGE_METHODS: readonly MergeMethod[] = ['merge', 'squash', 'rebase'];

export const RERUN_LIMIT = 5;
export const TEXT_MAX = 10_000;
export const REVIEWERS_MAX = 15;

const TEAM_PATTERN = /^team:([A-Za-z0-9][A-Za-z0-9_-]{0,99})$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;

/** The team slug of a `team:<slug>` entry, or `null`. */
export function teamSlug(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  return TEAM_PATTERN.exec(value)?.[1] ?? null;
}

export function isCommitSha(value: unknown): value is string {
  return typeof value === 'string' && SHA_PATTERN.test(value);
}
const RUNS_PAGE = 20;

const REVIEW_STATES = ['APPROVED', 'CHANGES_REQUESTED'] as const;
type SubmittedReviewState = (typeof REVIEW_STATES)[number];

const RUN_CONCLUSIONS = [
  'success',
  'failure',
  'neutral',
  'cancelled',
  'skipped',
  'timed_out',
  'action_required',
  'stale',
  'startup_failure',
] as const;
type RunConclusion = (typeof RUN_CONCLUSIONS)[number];
const RERUNNABLE: readonly RunConclusion[] = ['failure', 'timed_out', 'cancelled', 'startup_failure', 'action_required'];

/** GitHub said no for a reason the app checked itself before writing (the PR
 *  changed since the user looked). The route answers 409, not 502. */
export class PullStateRefusal extends ProviderRefusal {}

function repoPath({ owner, repo }: PullRef): string {
  return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}`;
}

function pullPath(ref: PullRef): string {
  return `${repoPath(ref)}/pulls/${ref.number}`;
}

function requiredId(value: unknown, where: string): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value <= 0) throw unexpected(where, 'id ausente');
  return value;
}

function requiredString(value: unknown, where: string, what: string): string {
  if (typeof value !== 'string' || value === '') throw unexpected(where, `${what} ausente`);
  return value;
}

export interface SubmittedReview {
  id: number;
  state: SubmittedReviewState;
}

export async function submitReview(
  token: string,
  ref: PullRef,
  event: ReviewEvent,
  body: string | null,
): Promise<SubmittedReview> {
  const data = await githubRequest(token, `${pullPath(ref)}/reviews`, {
    method: 'POST',
    body: body === null ? { event } : { event, body },
  });
  const where = 'na revisão';
  if (!isRecord(data)) throw unexpected(where, 'o corpo não é um objeto');
  const state = data.state;
  if (!REVIEW_STATES.includes(state as SubmittedReviewState)) {
    throw unexpected(where, `estado desconhecido ${JSON.stringify(state)}`);
  }
  return { id: requiredId(data.id, where), state: state as SubmittedReviewState };
}

export interface PostedComment {
  id: number;
  url: string;
}

/** Issues and pull requests share the issue comments endpoint. */
export async function addComment(token: string, ref: PullRef, body: string): Promise<PostedComment> {
  const data = await githubRequest(token, `${repoPath(ref)}/issues/${ref.number}/comments`, {
    method: 'POST',
    body: { body },
  });
  const where = 'no comentário';
  if (!isRecord(data)) throw unexpected(where, 'o corpo não é um objeto');
  return { id: requiredId(data.id, where), url: requiredString(data.html_url, where, 'html_url') };
}

function loginsOf(value: unknown, field: 'login' | 'slug', where: string): string[] {
  if (!Array.isArray(value)) throw unexpected(where, 'lista de revisores ausente');
  return value.map((entry) => {
    if (!isRecord(entry)) throw unexpected(where, 'revisor sem forma de objeto');
    return requiredString(entry[field], where, field);
  });
}

/** Who is requested after the call, users as login and teams as `team:<slug>`. */
export async function requestReviewers(
  token: string,
  ref: PullRef,
  reviewers: string[],
  teams: string[],
): Promise<string[]> {
  const data = await githubRequest(token, `${pullPath(ref)}/requested_reviewers`, {
    method: 'POST',
    body: { reviewers, team_reviewers: teams },
  });
  const where = 'ao pedir revisão';
  if (!isRecord(data)) throw unexpected(where, 'o corpo não é um objeto');
  return [
    ...loginsOf(data.requested_reviewers, 'login', where),
    ...loginsOf(data.requested_teams, 'slug', where).map((slug) => `team:${slug}`),
  ];
}

interface PullSnapshot {
  state: 'open' | 'closed';
  publication: 'draft' | 'ready';
  /** `null` while GitHub has not computed it yet. */
  mergeable: boolean | null;
  headSha: string;
}

function parsePullSnapshot(data: unknown): PullSnapshot {
  const where = 'ao ler o PR';
  if (!isRecord(data)) throw unexpected(where, 'o corpo não é um objeto');
  if (data.state !== 'open' && data.state !== 'closed') {
    throw unexpected(where, `estado desconhecido ${JSON.stringify(data.state)}`);
  }
  if (typeof data.draft !== 'boolean') throw unexpected(where, '`draft` com forma inesperada');
  if (data.mergeable !== null && typeof data.mergeable !== 'boolean') {
    throw unexpected(where, '`mergeable` com forma inesperada');
  }
  if (!isRecord(data.head)) throw unexpected(where, '`head` ausente');
  return { state: data.state, publication: data.draft ? 'draft' : 'ready', mergeable: data.mergeable, headSha: requiredString(data.head.sha, where, 'head.sha') };
}

const HEAD_MOVED = 'o PR recebeu commits novos desde que você olhou — atualize o painel e confira';

function refusalOf(pull: PullSnapshot, headSha: string): string | null {
  if (pull.publication === 'draft') return 'o PR ainda é um rascunho';
  if (pull.state !== 'open') return 'o PR não está mais aberto';
  if (pull.headSha !== headSha) return HEAD_MOVED;
  if (pull.mergeable === null) return 'o GitHub ainda está calculando se o PR pode entrar — tente de novo em instantes';
  if (!pull.mergeable) return 'o GitHub diz que o PR não pode entrar (conflito ou regra da branch)';
  return null;
}

/** Re-reads the PR first so the merge only happens on the exact commit the
 *  user saw, then merges pinned to that sha. */
export async function mergePull(token: string, ref: PullRef, method: MergeMethod, headSha: string): Promise<string> {
  const pull = parsePullSnapshot(await githubRequest(token, pullPath(ref)));
  const refusal = refusalOf(pull, headSha);
  if (refusal) throw new PullStateRefusal(refusal);

  const data = await githubRequest(token, `${pullPath(ref)}/merge`, {
    method: 'PUT',
    body: { merge_method: method, sha: headSha },
  });
  const where = 'no merge';
  if (!isRecord(data)) throw unexpected(where, 'o corpo não é um objeto');
  if (data.merged !== true) {
    throw new Error(typeof data.message === 'string' && data.message ? data.message : 'o GitHub não fez o merge');
  }
  return requiredString(data.sha, where, 'sha');
}

function failedRunIds(data: unknown): number[] {
  const where = 'nas execuções do Actions';
  if (!isRecord(data) || !Array.isArray(data.workflow_runs)) throw unexpected(where, '`workflow_runs` ausente');
  return data.workflow_runs.flatMap((run) => {
    if (!isRecord(run)) throw unexpected(where, 'execução sem forma de objeto');
    const id = requiredId(run.id, where);
    if (run.conclusion === null) return [];
    if (!RUN_CONCLUSIONS.includes(run.conclusion as RunConclusion)) {
      throw unexpected(where, `conclusão desconhecida ${JSON.stringify(run.conclusion)}`);
    }
    return RERUNNABLE.includes(run.conclusion as RunConclusion) ? [id] : [];
  });
}

export interface RerunFailure {
  id: number;
  error: string;
}

export interface RerunOutcome {
  /** Runs GitHub accepted to re-run: 0 with no failures means the failing
   *  check is not from Actions. */
  rerun: number;
  failed: RerunFailure[];
}

/** Re-reads the PR first so only the commit the user saw is re-run, then asks
 *  each failed GitHub Actions run of that commit to re-run its failed jobs. */
export async function rerunFailedRuns(token: string, ref: PullRef, headSha: string): Promise<RerunOutcome> {
  const pull = parsePullSnapshot(await githubRequest(token, pullPath(ref)));
  if (pull.headSha !== headSha) throw new PullStateRefusal(HEAD_MOVED);

  const runs = await githubRequest(
    token,
    `${repoPath(ref)}/actions/runs?head_sha=${encodeURIComponent(headSha)}&per_page=${RUNS_PAGE}`,
  );
  const ids = failedRunIds(runs).slice(0, RERUN_LIMIT);
  const settled = await Promise.allSettled(
    ids.map((id) => githubRequest(token, `${repoPath(ref)}/actions/runs/${id}/rerun-failed-jobs`, { method: 'POST' })),
  );
  const failed = settled.flatMap((outcome, index) =>
    outcome.status === 'rejected'
      ? [{ id: ids[index], error: outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason) }]
      : [],
  );
  return { rerun: ids.length - failed.length, failed };
}
