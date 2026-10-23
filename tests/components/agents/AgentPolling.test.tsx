import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useAgentPolling } from '@/components/agents/useAgentPolling';

const parse = (value: unknown) => value as { value: number };
let visibility: DocumentVisibilityState;
beforeEach(() => {
  vi.useFakeTimers();
  visibility = 'visible';
  vi.spyOn(document, 'visibilityState', 'get').mockImplementation(() => visibility);
  vi.stubGlobal('fetch', vi.fn());
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers(); });

describe('agent foreground polling', () => {
  it('does not overlap a pending request and cancels it on hide, then resumes immediately', async () => {
    vi.mocked(fetch).mockImplementation(() => new Promise(() => {}));
    renderHook(() => useAgentPolling('/api/agents', parse));
    expect(fetch).toHaveBeenCalledTimes(1);
    const signal = vi.mocked(fetch).mock.calls[0][1]?.signal;
    await act(async () => { await vi.advanceTimersByTimeAsync(4000); });
    expect(fetch).toHaveBeenCalledTimes(1);
    visibility = 'hidden';
    act(() => { document.dispatchEvent(new Event('visibilitychange')); });
    expect(signal?.aborted).toBe(true);
    await act(async () => { await vi.advanceTimersByTimeAsync(6000); });
    expect(fetch).toHaveBeenCalledTimes(1);
    visibility = 'visible';
    act(() => { document.dispatchEvent(new Event('visibilitychange')); });
    expect(fetch).toHaveBeenCalledTimes(2);
  });
  it('clears cached private data after authorization is revoked', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response(JSON.stringify({ value: 1 }), { status: 200 })).mockResolvedValueOnce(new Response('{}', { status: 403 }));
    const { result } = renderHook(() => useAgentPolling('/api/agents', parse));
    await act(async () => { await vi.advanceTimersByTimeAsync(1); });
    expect(result.current.data).toEqual({ value: 1 });
    await act(async () => { await vi.advanceTimersByTimeAsync(2000); });
    expect(result.current.phase).toBe('error');
    expect(result.current.data).toBeNull();
  });
});
