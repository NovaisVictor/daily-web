import { z } from 'zod';
const identifier = z.string().min(1).max(200);
const agent = z.object({ id: identifier, externalId: identifier, provider: z.enum(['claude','codex','gemini']), displayName: z.string(), createdAt: z.iso.datetime(), lastActivityAt: z.iso.datetime() }).strict();
const session = z.object({ id: identifier, agentId: identifier, externalId: identifier, version: z.number().int().positive(), startedAt: z.iso.datetime(), lastActivityAt: z.iso.datetime(), agent, freshness: z.enum(['fresh','stale','disconnected']) }).strict();
const page = z.object({ items: z.array(session), nextCursor: z.string().nullable(), complete: z.literal(true) }).strict();
const envelope = z.object({ result: z.object({ isError: z.boolean().optional(), structuredContent: z.unknown().optional(), content: z.array(z.object({ type: z.literal('text'), text: z.string() })).optional() }).optional(), error: z.unknown().optional() });
export function sessionToolResult(message) {
  try {
    const response = envelope.parse(message);
    if (response.error !== undefined || response.result?.isError) return { result: 'error' };
    if (!response.result) return { result: 'invalid' };
    const structured = response.result.structuredContent;
    const value = structured !== undefined ? z.object({ result: page }).strict().parse(structured).result : page.parse(JSON.parse(response.result.content?.find(item => item.type === 'text')?.text ?? 'null'));
    return { result: 'success', itemCount: value.items.length };
  } catch { return { result: 'invalid' }; }
}
