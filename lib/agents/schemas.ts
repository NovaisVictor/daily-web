import { AccessError } from '@/lib/access/principal';
import { providers, statuses, type SourceLink, type Provider, type TaskStatus } from './model';
export function object(value: unknown, allowed: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new AccessError(400,'invalid_input','Expected an object');
  const result = value as Record<string, unknown>;
  if (Object.keys(result).some(key => !allowed.includes(key))) throw new AccessError(400,'invalid_input','Unknown or forbidden field');
  return result;
}
export function text(value: unknown, name: string, max=200, empty=false): string {
  if (typeof value !== 'string' || value.length>max || (!empty && !value.trim())) throw new AccessError(400,'invalid_input',`Invalid ${name}`);
  return value.trim();
}
export function id(value: unknown): string { const result=text(value,'id',160); if (!/^[A-Za-z0-9_.:@/-]+$/.test(result)) throw new AccessError(400,'invalid_input','Invalid identifier'); return result; }
export function provider(value: unknown): Provider { if (!providers.includes(value as Provider)) throw new AccessError(400,'invalid_provider','Unknown agent provider'); return value as Provider; }
export function status(value: unknown): TaskStatus { if (!statuses.includes(value as TaskStatus)) throw new AccessError(400,'invalid_status','Unknown task status'); return value as TaskStatus; }
export function version(value: unknown): number { if (!Number.isSafeInteger(value) || (value as number)<1) throw new AccessError(400,'invalid_version','Expected a positive version'); return value as number; }
export function source(value: unknown): SourceLink | null {
  if (value === null || value === undefined) return null;
  const s=object(value,['provider','connectionId','resource']);
  if (!['personal','jira','github'].includes(s.provider as string)) throw new AccessError(400,'invalid_source','Invalid source provider');
  const resource=text(s.resource,'resource',300);
  if (s.provider==='jira' && !/^[A-Z][A-Z0-9_]*-\d+$/.test(resource)) throw new AccessError(400,'invalid_source','Invalid Jira key');
  if (s.provider==='github' && !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#\d+$/.test(resource)) throw new AccessError(400,'invalid_source','Invalid GitHub reference');
  return {provider:s.provider as SourceLink['provider'],resource,...(s.connectionId!==undefined ? {connectionId:id(s.connectionId)} : {})};
}
