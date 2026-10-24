export const providers = ['claude', 'codex', 'gemini'] as const;
export type Provider = typeof providers[number];
export const statuses = ['queued', 'working', 'blocked', 'completed', 'failed', 'cancelled'] as const;
export type TaskStatus = typeof statuses[number];
export const transitions: Record<TaskStatus, readonly TaskStatus[]> = {
  queued: ['working', 'blocked', 'completed', 'cancelled'], working: ['blocked', 'completed', 'failed', 'cancelled'],
  blocked: ['queued', 'working', 'completed', 'failed', 'cancelled'], completed: ['queued'], failed: ['queued', 'completed'], cancelled: ['queued', 'completed'],
};
export type Freshness = 'fresh' | 'stale' | 'disconnected';
export interface Agent { id: string; externalId: string; provider: Provider; displayName: string; createdAt: string; lastActivityAt: string }
export interface AgentSession { id: string; agentId: string; externalId: string; version: number; startedAt: string; lastActivityAt: string; agent: Agent; freshness: Freshness }
export interface SourceLink { provider: 'personal' | 'jira' | 'github'; connectionId?: string; resource: string }
export interface Assignment { sessionId: string; agentId: string; provider: Provider; displayName: string; freshness: Freshness }
export interface AgentTask { id: string; parentTaskId: string | null; externalId: string; title: string; description: string; status: TaskStatus; assignment: Assignment | null; source: SourceLink | null; version: number; createdAt: string; lastActivityAt: string }
export interface SubtaskProgress { total: number; completed: number; active: { id: string; title: string; status: TaskStatus }[] }
export interface Activity { id: string; taskId: string; kind: 'progress' | 'transition' | 'created' | 'updated'; summary: string; receivedAt: string; occurredAt: string | null }
export interface Page<T> { items: T[]; nextCursor: string | null; complete: true }
export interface ListQuery { status?: TaskStatus; agentId?: string; sessionId?: string; q?: string; cursor?: string; limit?: number; sort?: 'newest' | 'oldest'; parentTaskId?: string; scope?: 'all' | 'roots' }
export interface Mutation { key: string; requestedAt: string }
export interface CreateTask { externalId: string; title: string; description?: string; assignment?: {sessionId: string} | null; source?: SourceLink | null; parentTaskId?: string }
export interface UpdateTask { expectedVersion: number; title?: string; description?: string; assignment?: {sessionId: string} | null; source?: SourceLink | null }
export const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
export function freshness(at: string, now = Date.now()): Freshness { const age = now - Date.parse(at); return age <= 120_000 ? 'fresh' : age <= 600_000 ? 'stale' : 'disconnected'; }
