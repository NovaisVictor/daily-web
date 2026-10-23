import { findUserById } from '@/lib/auth/users';

export interface Principal {
  userId: string;
  scopes: readonly string[];
  kind: 'browser' | 'api' | 'oauth';
}
export class AccessError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
    this.name = 'AccessError';
  }
}
export function requireScope(principal: Principal, scope: string): void {
  if (!findUserById(principal.userId)) throw new AccessError(401, 'invalid_identity', 'Authentication required');
  if (!principal.scopes.includes(scope)) throw new AccessError(403, 'insufficient_scope', 'Permission required');
}
