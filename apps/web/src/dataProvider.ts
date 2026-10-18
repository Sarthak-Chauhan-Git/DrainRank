import { createSeedData } from "./data";
import type { AppState, DrainRecord } from "./App";

export interface DataProvider {
  load(): AppState;
  save(state: AppState): void;
  clear(): void;
}

const STORAGE_KEY = "drainrank-v1";

function mergeWithSeedData(parsed: Partial<AppState>): AppState {
  const defaults = createSeedData();
  return {
    ...defaults,
    ...parsed,
    drains: (parsed.drains ?? defaults.drains).map((drain: DrainRecord) => ({
      ...drain,
      evidenceId: drain.evidenceId || `EVD-${drain.id}`,
    })),
    creditPolicy: parsed.creditPolicy
      ? {
          ...defaults.creditPolicy,
          ...parsed.creditPolicy,
          wardAllowances: Object.fromEntries(
            Object.entries(
              parsed.creditPolicy.wardAllowances ??
                defaults.creditPolicy.wardAllowances,
            ).map(([ward, value]) => [
              ward,
              typeof value === "number"
                ? {
                    ...defaults.creditPolicy.wardAllowances[ward],
                    successfulCleaning: value,
                  }
                : value,
            ]),
          ),
        }
      : defaults.creditPolicy,
    workers: parsed.workers ?? defaults.workers,
    crews: parsed.crews ?? defaults.crews,
    creditPools: parsed.creditPools ?? defaults.creditPools,
    creditAllocations:
      parsed.creditAllocations ?? defaults.creditAllocations,
    creditAudits: parsed.creditAudits ?? defaults.creditAudits,
  };
}

export const localDataProvider: DataProvider = {
  load() {
    const savedValue = window.localStorage.getItem(STORAGE_KEY);
    if (!savedValue) return createSeedData();

    try {
      const parsed = JSON.parse(savedValue) as Partial<AppState>;
      if (
        !Array.isArray(parsed.drains) ||
        !Array.isArray(parsed.reports) ||
        !Array.isArray(parsed.activities) ||
        !Array.isArray(parsed.outcomes)
      ) {
        return createSeedData();
      }
      return mergeWithSeedData(parsed);
    } catch {
      window.localStorage.removeItem(STORAGE_KEY);
      return createSeedData();
    }
  },
  save(state) {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  },
  clear() {
    window.localStorage.removeItem(STORAGE_KEY);
  },
};
