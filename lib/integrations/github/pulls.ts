import type {
  DefaultBranchStatus,
  PullCi,
  PullFailedCheck,
  PullMerge,
  PullRequestItem,
  PullReview,
  PullReviewer,
  PullReviewerState,
  PullsTruncation,
} from '@/lib/types';
import { isRecord, unexpected, type GraphqlError } from './client';

export const PER_REPO_LIMIT = 50;
export const SEARCH_LIMIT = 50;
export const FAILED_CHECKS_LIMIT = 5;
/** Repos per GraphQL request: one query for dozens of repos gets slow and
 *  costly, and a failure there would take every repo down at once. */
export const REPOS_PER_QUERY = 10;

export const REVIEW_REQUESTS_QUERY = 'is:open is:pr review-requested:@me';
export const MY_PULLS_QUERY = 'is:open is:pr author:@me';

function pullFields(withRequestedAt: boolean): string {
  const requestedAt = withRequestedAt
    ? `
  timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 1) { nodes { ... on ReviewRequestedEvent { createdAt } } }`
    : '';
  return `
fragment PullFields on PullRequest {
  id number title url isDraft createdAt updatedAt
  author { login }
  additions deletions changedFiles
  mergeable mergeStateStatus reviewDecision
  headRefName baseRefName
  reviewRequests(first: 20) {
    nodes { requestedReviewer { __typename ... on User { login } ... on Bot { login } ... on Mannequin { login } ... on Team { slug } } }
  }
  latestReviews(first: 20) { nodes { author { __typename login } state } }${requestedAt}
  commits(last: 1) {
    nodes { commit { oid statusCheckRollup { state contexts(first: 50) { nodes {
      __typename
      ... on CheckRun { name conclusion status detailsUrl }
      ... on StatusContext { context state targetUrl }
    } } } } }
  }
}`;
}

const REPO_PULLS = `
fragment RepoPulls on Repository {
  pullRequests(states: OPEN, first: ${PER_REPO_LIMIT}, orderBy: { field: UPDATED_AT, direction: DESC }) {
    totalCount
    nodes { ...PullFields }
  }
}`;

const REPO_FIELDS = `
fragment RepoFields on Repository {
  nameWithOwner
  issues(states: OPEN, first: ${PER_REPO_LIMIT}, orderBy: { field: UPDATED_AT, direction: DESC }) {
    totalCount
    nodes { id number title url createdAt updatedAt author { login } }
  }
  defaultBranchRef { name target { ... on Commit { statusCheckRollup { state } } } }
}`;

export function repoAlias(index: number): string {
  return `repo${index}`;
}

/** One query for every tracked repo, one alias each. Owner and name travel as
 *  variables, never spliced into the query text. A repo in `withoutPulls` has
 *  its PRs fetched by author search instead, so it skips its pull list. */
export function reposQuery(
  repos: string[],
  withoutPulls: ReadonlySet<string> = new Set(),
): { query: string; variables: Record<string, string> } {
  const variables: Record<string, string> = {};
  const declarations: string[] = [];
  const selections: string[] = [];
  repos.forEach((repo, index) => {
    const [owner, name] = repo.split('/');
    variables[`owner${index}`] = owner;
    variables[`name${index}`] = name;
    declarations.push(`$owner${index}: String!`, `$name${index}: String!`);
    const fragments = withoutPulls.has(repo) ? '...RepoFields' : '...RepoFields ...RepoPulls';
    selections.push(`${repoAlias(index)}: repository(owner: $owner${index}, name: $name${index}) { ${fragments} }`);
  });
  const args = declarations.length > 0 ? `(${declarations.join(', ')})` : '';
  // GraphQL rejects a query that declares a fragment it never spreads.
  const pulls = repos.some((repo) => !withoutPulls.has(repo)) ? `\n${REPO_PULLS}\n${pullFields(false)}` : '';
  const query = `query TrackedRepos${args} {\n  viewer { login }\n  ${selections.join('\n  ')}\n}\n${REPO_FIELDS}${pulls}`;
  return { query, variables };
}

/** Authors per GraphQL request, for the same reason as REPOS_PER_QUERY. */
export const AUTHORS_PER_QUERY = 10;

/** One followed author and every tracked repo that follows them. */
export interface AuthorGroup {
  author: string;
  repos: string[];
}

export function authorAlias(index: number): string {
  return `author${index}`;
}

const BOT_SUFFIX = '[bot]';

/** One search per author, not per (repo, author) pair: several `repo:`
 *  qualifiers combine as OR, so the author's PRs in all their repos come back
 *  in one page. Apps are `app/name` in search, not the `name[bot]` login. */
export function authorSearch(group: AuthorGroup): string {
  const author = group.author.endsWith(BOT_SUFFIX)
    ? `app/${group.author.slice(0, -BOT_SUFFIX.length)}`
    : group.author;
  return ['is:open is:pr', `author:${author}`, ...group.repos.map((repo) => `repo:${repo}`)].join(' ');
}

export function authorsQuery(groups: AuthorGroup[]): { query: string; variables: Record<string, string> } {
  const variables: Record<string, string> = {};
  const declarations: string[] = [];
  const selections: string[] = [];
  groups.forEach((group, index) => {
    variables[`q${index}`] = authorSearch(group);
    declarations.push(`$q${index}: String!`);
    selections.push(
      `${authorAlias(index)}: search(query: $q${index}, type: ISSUE, first: ${SEARCH_LIMIT}) { issueCount nodes { ... on PullRequest { ...PullFields repository { nameWithOwner } } } }`,
    );
  });
  const query = `query TrackedAuthors(${declarations.join(', ')}) {\n  viewer { login }\n  ${selections.join('\n  ')}\n}\n${pullFields(false)}`;
  return { query, variables };
}

function searchPullsQuery(withRequestedAt: boolean): string {
  return `query SearchPulls($q: String!) {
  search(query: $q, type: ISSUE, first: ${SEARCH_LIMIT}) {
    issueCount
    nodes { ... on PullRequest { ...PullFields repository { nameWithOwner } } }
  }
}
${pullFields(withRequestedAt)}`;
}

/** Only this search asks when the review was requested: the timeline is
 *  costly, and the stale-review notice is the one place that needs it. */
export const REVIEW_REQUESTS_SEARCH = searchPullsQuery(true);
export const MY_PULLS_SEARCH = searchPullsQuery(false);

// --- Enum mappings: an unknown value is `unknown`, never a thrown error -----

export function ciFromState(state: unknown): PullCi {
  if (state === null || state === undefined) return 'none';
  switch (state) {
    case 'SUCCESS':
      return 'passing';
    case 'FAILURE':
    case 'ERROR':
      return 'failing';
    case 'PENDING':
    case 'EXPECTED':
      return 'running';
    default:
      return 'unknown';
  }
}

export function reviewFromDecision(decision: unknown): PullReview {
  if (decision === null || decision === undefined) return 'none';
  switch (decision) {
    case 'APPROVED':
      return 'approved';
    case 'CHANGES_REQUESTED':
      return 'changes-requested';
    case 'REVIEW_REQUIRED':
      return 'pending';
    default:
      return 'unknown';
  }
}

const BLOCKED_STATES = new Set(['BLOCKED', 'BEHIND', 'UNSTABLE', 'HAS_HOOKS', 'DRAFT']);

export function mergeFromState(mergeable: unknown, mergeStateStatus: unknown): PullMerge {
  if (mergeable === 'CONFLICTING') return 'conflict';
  if (mergeable !== 'MERGEABLE') return 'unknown';
  if (mergeStateStatus === 'CLEAN') return 'clean';
  if (mergeStateStatus === 'DIRTY') return 'conflict';
  if (typeof mergeStateStatus === 'string' && BLOCKED_STATES.has(mergeStateStatus)) return 'blocked';
  return 'unknown';
}

const FAILED_CONCLUSIONS = new Set<unknown>(['FAILURE', 'TIMED_OUT', 'CANCELLED', 'STARTUP_FAILURE', 'ACTION_REQUIRED']);

export function failedChecksOf(contexts: unknown[]): PullFailedCheck[] {
  const failed: PullFailedCheck[] = [];
  for (const context of contexts) {
    if (!isRecord(context)) continue;
    if (context.__typename === 'CheckRun' && FAILED_CONCLUSIONS.has(context.conclusion)) {
      failed.push({ name: textOr(context.name, 'check'), url: textOrNull(context.detailsUrl) });
    } else if (context.__typename === 'StatusContext' && (context.state === 'FAILURE' || context.state === 'ERROR')) {
      failed.push({ name: textOr(context.context, 'status'), url: textOrNull(context.targetUrl) });
    }
  }
  return failed.slice(0, FAILED_CHECKS_LIMIT);
}

export function pendingReviewersOf(requests: unknown[]): string[] {
  const reviewers: string[] = [];
  for (const request of requests) {
    const reviewer = isRecord(request) ? request.requestedReviewer : null;
    if (!isRecord(reviewer)) continue;
    if (reviewer.__typename === 'Team' && typeof reviewer.slug === 'string') reviewers.push(`team:${reviewer.slug}`);
    else if (typeof reviewer.login === 'string' && reviewer.login !== '') reviewers.push(reviewer.login);
  }
  return reviewers;
}

export function reviewerStateOf(state: unknown): PullReviewerState {
  switch (state) {
    case 'APPROVED':
      return 'approved';
    case 'CHANGES_REQUESTED':
      return 'changes-requested';
    case 'COMMENTED':
      return 'commented';
    case 'DISMISSED':
      return 'dismissed';
    case 'PENDING':
      return 'pending';
    default:
      return 'unknown';
  }
}

/** Who reviewed and how, for asking them again: a deleted author has no login
 *  and a bot (an app) cannot be requested, so both are skipped. */
export function reviewersOf(reviews: unknown[]): PullReviewer[] {
  const reviewers: PullReviewer[] = [];
  for (const review of reviews) {
    if (!isRecord(review) || !isRecord(review.author) || review.author.__typename === 'Bot') continue;
    const login = review.author.login;
    if (typeof login !== 'string' || login === '') continue;
    reviewers.push({ login, state: reviewerStateOf(review.state) });
  }
  return reviewers;
}

function requestedAtOf(timeline: unknown): string | null {
  if (!isRecord(timeline) || !Array.isArray(timeline.nodes)) return null;
  const last = timeline.nodes.at(-1);
  return isRecord(last) ? textOrNull(last.createdAt) : null;
}

// --- Shape readers: a missing structural field fails visibly ---------------

function textOr(value: unknown, fallback: string): string {
  return typeof value === 'string' && value !== '' ? value : fallback;
}

function textOrNull(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null;
}

function text(node: Record<string, unknown>, key: string, where: string): string {
  const value = node[key];
  if (typeof value !== 'string') throw unexpected(where, `${key} ausente`);
  return value;
}

function count(node: Record<string, unknown>, key: string, where: string): number {
  const value = node[key];
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) throw unexpected(where, `${key} ausente`);
  return value;
}

function record(value: unknown, where: string, what: string): Record<string, unknown> {
  if (!isRecord(value)) throw unexpected(where, `${what} ausente`);
  return value;
}

function nodesOf(connection: unknown, where: string, what: string): unknown[] {
  const nodes = record(connection, where, what).nodes;
  if (!Array.isArray(nodes)) throw unexpected(where, `${what}.nodes ausente`);
  return nodes;
}

function authorOf(node: Record<string, unknown>): string {
  return isRecord(node.author) && typeof node.author.login === 'string' ? node.author.login : '';
}

function identity(raw: unknown, repo: string, kind: string) {
  const node = record(raw, `em ${repo}`, kind);
  const number = count(node, 'number', `em ${repo}`);
  const where = `em ${repo}#${number}`;
  return {
    node,
    where,
    fields: {
      id: text(node, 'id', where),
      repo,
      number,
      title: text(node, 'title', where),
      url: text(node, 'url', where),
      author: authorOf(node),
      createdAt: text(node, 'createdAt', where),
      updatedAt: text(node, 'updatedAt', where),
    },
  };
}

export function parsePullNode(raw: unknown, repo: string, login: string): PullRequestItem {
  const { node, where, fields } = identity(raw, repo, 'pull request');
  if (typeof node.isDraft !== 'boolean') throw unexpected(where, 'isDraft ausente');
  const requests = nodesOf(node.reviewRequests, where, 'reviewRequests');
  const commit = nodesOf(node.commits, where, 'commits')
    .map((entry) => (isRecord(entry) && isRecord(entry.commit) ? entry.commit : null))
    .at(-1);
  const rollup = commit && isRecord(commit.statusCheckRollup) ? commit.statusCheckRollup : null;
  const contexts = rollup && isRecord(rollup.contexts) && Array.isArray(rollup.contexts.nodes) ? rollup.contexts.nodes : [];
  const reviews = isRecord(node.latestReviews) && Array.isArray(node.latestReviews.nodes) ? node.latestReviews.nodes : [];

  return {
    ...fields,
    draft: node.isDraft,
    awaitingYou:
      login !== '' &&
      requests.some(
        (request) =>
          isRecord(request) &&
          isRecord(request.requestedReviewer) &&
          request.requestedReviewer.__typename === 'User' &&
          request.requestedReviewer.login === login,
      ),
    mine: login !== '' && fields.author === login,
    isPullRequest: true,
    ci: rollup ? ciFromState(rollup.state) : 'none',
    failedChecks: failedChecksOf(contexts),
    review: reviewFromDecision(node.reviewDecision),
    pendingReviewers: pendingReviewersOf(requests),
    reviewers: reviewersOf(reviews),
    reviewRequestedAt: requestedAtOf(node.timelineItems),
    merge: mergeFromState(node.mergeable, node.mergeStateStatus),
    size: {
      additions: count(node, 'additions', where),
      deletions: count(node, 'deletions', where),
      files: count(node, 'changedFiles', where),
    },
    headRef: text(node, 'headRefName', where),
    baseRef: text(node, 'baseRefName', where),
    headSha: commit ? textOrNull(commit.oid) : null,
  };
}

export function parseIssueNode(raw: unknown, repo: string, login: string): PullRequestItem {
  const { fields } = identity(raw, repo, 'issue');
  return {
    ...fields,
    draft: false,
    awaitingYou: false,
    mine: login !== '' && fields.author === login,
    isPullRequest: false,
    ci: 'none',
    failedChecks: [],
    review: 'none',
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'none',
    size: null,
    headRef: null,
    baseRef: null,
    headSha: null,
  };
}

export function viewerLogin(data: Record<string, unknown>): string {
  const viewer = record(data.viewer, 'no GraphQL', 'viewer');
  return text(viewer, 'login', 'no GraphQL');
}

export interface ParsedRepos {
  items: PullRequestItem[];
  errors: string[];
  defaultBranches: DefaultBranchStatus[];
  truncated: PullsTruncation[];
}

function parseRepo(raw: unknown, repo: string, login: string, withPulls: boolean): Omit<ParsedRepos, 'errors'> {
  const node = record(raw, `em ${repo}`, 'repositório');
  const where = `em ${repo}`;
  const pulls = withPulls ? record(node.pullRequests, where, 'pullRequests') : null;
  const issues = record(node.issues, where, 'issues');
  const pullNodes = pulls ? nodesOf(pulls, where, 'pullRequests') : [];
  const issueNodes = nodesOf(issues, where, 'issues');
  const answered = (node: unknown) => node !== null;

  const truncated: PullsTruncation[] = [];
  const pullTotal = pulls ? count(pulls, 'totalCount', where) : 0;
  const issueTotal = count(issues, 'totalCount', where);
  if (pullTotal > pullNodes.length) truncated.push({ repo, kind: 'pulls', shown: pullNodes.length, total: pullTotal });
  if (issueTotal > issueNodes.length) truncated.push({ repo, kind: 'issues', shown: issueNodes.length, total: issueTotal });

  const defaultBranches: DefaultBranchStatus[] = [];
  if (isRecord(node.defaultBranchRef)) {
    const target = isRecord(node.defaultBranchRef.target) ? node.defaultBranchRef.target : null;
    const rollup = target && isRecord(target.statusCheckRollup) ? target.statusCheckRollup : null;
    defaultBranches.push({
      repo,
      branch: text(node.defaultBranchRef, 'name', where),
      ci: rollup ? ciFromState(rollup.state) : 'none',
    });
  }

  return {
    items: [
      ...pullNodes.filter(answered).map((pull) => parsePullNode(pull, repo, login)),
      ...issueNodes.filter(answered).map((issue) => parseIssueNode(issue, repo, login)),
    ],
    defaultBranches,
    truncated,
  };
}

/** One note per place for errors GitHub raised inside the data (a field it
 *  refused, a node it nulled): the rest of what it returned still counts. */
export function partialNote(subject: string, errors: GraphqlError[]): string | null {
  if (errors.length === 0) return null;
  const kinds = [...new Set(errors.map((error) => error.type ?? error.message))];
  return `${subject}: parte dos dados não veio (${kinds.join(', ')})`;
}

/** `repos[i]` answered under alias `repo{i}`. A repo that failed alone (renamed,
 *  no access, odd shape) lands in `errors` and the others still load. Only an
 *  error on the alias itself fails the repo; a nested one keeps its data. */
export function parseReposData(
  data: Record<string, unknown>,
  repos: string[],
  graphqlErrors: GraphqlError[],
  withoutPulls: ReadonlySet<string> = new Set(),
): ParsedRepos {
  const login = viewerLogin(data);
  const result: ParsedRepos = { items: [], errors: [], defaultBranches: [], truncated: [] };
  repos.forEach((repo, index) => {
    const alias = repoAlias(index);
    const own = graphqlErrors.filter((error) => error.path[0] === alias);
    const failure = own.find((error) => error.path.length === 1);
    if (failure) {
      result.errors.push(`${repo}: ${failure.message}`);
      return;
    }
    if (data[alias] === null || data[alias] === undefined) {
      result.errors.push(`${repo}: repositório não encontrado ou sem acesso`);
      return;
    }
    try {
      const parsed = parseRepo(data[alias], repo, login, !withoutPulls.has(repo));
      result.items.push(...parsed.items);
      result.defaultBranches.push(...parsed.defaultBranches);
      result.truncated.push(...parsed.truncated);
      const note = partialNote(repo, own);
      if (note) result.errors.push(note);
    } catch (error) {
      result.errors.push(`${repo}: ${error instanceof Error ? error.message : String(error)}`);
    }
  });
  return result;
}

export interface ParsedSearch {
  items: PullRequestItem[];
  total: number;
}

function parseSearch(raw: unknown, where: string, what: string, login: string): ParsedSearch {
  const search = record(raw, where, what);
  const total = count(search, 'issueCount', where);
  const nodes = nodesOf(search, where, what);
  const items = nodes
    .filter((node) => node !== null)
    .map((node) => {
      const repository = record(isRecord(node) ? node.repository : null, where, 'repository');
      return parsePullNode(node, text(repository, 'nameWithOwner', where), login);
    });
  return { items, total };
}

/** Search results span repos outside the tracked list: each node names its own. */
export function parseSearchData(data: Record<string, unknown>): ParsedSearch {
  return parseSearch(data.search, 'na busca', 'search', '');
}

/** `groups[i]` answered under alias `author{i}`, isolated like the repos: one
 *  author GitHub refused (a deleted account) does not hide the others. A
 *  search that holds more than one page says so instead of cutting silently. */
export function parseAuthorsData(
  data: Record<string, unknown>,
  groups: AuthorGroup[],
  graphqlErrors: GraphqlError[],
): ParsedRepos {
  const login = viewerLogin(data);
  const result: ParsedRepos = { items: [], errors: [], defaultBranches: [], truncated: [] };
  groups.forEach((group, index) => {
    const alias = authorAlias(index);
    const subject = `autor ${group.author}`;
    const own = graphqlErrors.filter((error) => error.path[0] === alias);
    const failure = own.find((error) => error.path.length === 1);
    if (failure) {
      result.errors.push(`${subject}: ${failure.message}`);
      return;
    }
    try {
      const { items, total } = parseSearch(data[alias], `na busca de ${group.author}`, 'search', login);
      result.items.push(...items);
      if (total > items.length) {
        result.errors.push(`${subject}: mostrando ${items.length} de ${total} pull requests abertos`);
      }
      const note = partialNote(subject, own);
      if (note) result.errors.push(note);
    } catch (error) {
      result.errors.push(`${subject}: ${error instanceof Error ? error.message : String(error)}`);
    }
  });
  return result;
}
