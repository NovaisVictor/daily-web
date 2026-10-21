import type { PullRequestItem } from '@/lib/types';

/** Slot G7: the filter state parsed from the URL. */
export type PullFilterState = Record<string, never>;

export function parsePullFilters(_params: URLSearchParams): PullFilterState {
  return {};
}

export function matchesPullFilters(_item: PullRequestItem, _filters: PullFilterState): boolean {
  return true;
}
