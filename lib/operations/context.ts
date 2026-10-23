import { z } from 'zod';
import { AccessError, requireScope, type Principal } from '@/lib/access/principal';
import { findConnection, isModuleEnabled, type Connection } from '@/lib/vault/connections';
import type { ModuleId } from '@/lib/modules';
import { externalMutation, ExternalNotSubmittedError, ExternalPartialOutcome } from '@/lib/access/receipts';
import { resultSchemaFor, mutationResultSchemaFor } from './results';
import { ProviderRefusal } from '@/lib/integrations/refusal';

export const mutationShape = {
  operationId: z.string().regex(/^[A-Za-z0-9_.:-]{8,160}$/),
  requestedAt: z.iso.datetime({ offset: true }),
};
export const connectionShape = { connectionId: z.string().min(1).max(100) };
export const pageShape = { cursor: z.string().max(300).optional(), limit: z.number().int().min(1).max(100).default(50) };
export type OperationMode = 'read' | 'write';
export interface Operation {
  name: string;
  description: string;
  scope: string;
  mode: OperationMode;
  schema: z.ZodObject;
  resultSchema: z.ZodType;
  run: (principal: Principal, input: unknown) => Promise<unknown>;
}
export function operation<S extends z.ZodRawShape>(name: string, description: string, scope: string, mode: OperationMode, shape: S, run: (principal: Principal, input: z.infer<z.ZodObject<S>>) => Promise<unknown>): Operation {
  const schema = z.object(shape).strict();
  const resultSchema=resultSchemaFor(name);
  return { name, description, scope, mode, schema, resultSchema, run: async (principal, raw) => {
    requireScope(principal, scope);
    const parsed = schema.safeParse(raw);
    if (!parsed.success) throw new AccessError(400, 'invalid_input', 'The operation inputs are invalid');
    try { const result=resultSchema.safeParse(await run(principal, parsed.data));if(!result.success)throw new AccessError(502,'invalid_result','The provider returned an unsupported response');return result.data; }
    catch (error) {
      if (error instanceof AccessError) throw error;
      if (error instanceof ExternalPartialOutcome) {
        const failure=new AccessError(409,'uncertain_outcome','Only part of the provider operation was confirmed; reconcile before retry');
        failure.cause=error;
        throw failure;
      }
      if (error instanceof ExternalNotSubmittedError || error instanceof ProviderRefusal) throw new AccessError(409, 'state_changed', 'The resource changed before the operation was submitted');
      throw new AccessError(502, 'upstream_failed', 'The provider operation failed; no success was confirmed');
    }
  } };
}
export function connection(principal: Principal, id: string, module: ModuleId, scope: string): Connection {
  requireScope(principal, scope);
  const conn = findConnection(principal.userId, id);
  if (!conn || conn.module !== module) throw new AccessError(404, 'not_found', 'Connection not found');
  if (!isModuleEnabled(principal.userId, module)) throw new AccessError(409, 'module_disabled', 'Enable this module in settings first');
  return conn;
}
export function page<T>(items: T[], input: {cursor?: string;limit: number}, key: (item:T)=>string) {
  const start = input.cursor ? items.findIndex(item=>key(item)===input.cursor)+1 : 0;
  if (input.cursor && start === 0) throw new AccessError(400,'invalid_cursor','Refresh this list before paging');
  const selected=items.slice(start,start+input.limit);
  return {items:selected,nextCursor:start+selected.length<items.length ? key(selected[selected.length-1]) : null,complete:true};
}
export function mutate<T extends Record<string,unknown>>(principal:Principal,name:string,resource:{id:string;connectionId?:string},input:{operationId:string;requestedAt:string},work:()=>Promise<T>) {
  return externalMutation(principal.userId,name,{...resource,input}, {key:input.operationId,requestedAt:input.requestedAt}, async()=>{
    const result=await work();
    if(!mutationResultSchemaFor(name).safeParse(result).success)throw new Error('Unconfirmed provider result');
    return result;
  });
}
