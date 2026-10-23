import type { AppState } from "./App";

export const createEmptyData = (): AppState => ({
  drains: [],
  reports: [],
  activities: [],
  outcomes: [],
  creditPolicy: {
    baseCleaning: 100,
    baseInspection: 60,
    complexityMultiplier: 1,
    scopeMultiplier: 1,
    evidenceMultiplier: 1,
    roleWeights: { Leader: 1.2, Technician: 1, Helper: 0.8 },
    wardAllowances: {
      "Ward 4": {
        successfulCleaning: 100,
        successfulInspection: 60,
        incompleteWorkPenalty: 20,
        rejectedEvidencePenalty: 30,
        delayedWorkPenalty: 15,
      },
      "Ward 7": {
        successfulCleaning: 120,
        successfulInspection: 70,
        incompleteWorkPenalty: 25,
        rejectedEvidencePenalty: 35,
        delayedWorkPenalty: 20,
      },
      "Ward 12": {
        successfulCleaning: 140,
        successfulInspection: 80,
        incompleteWorkPenalty: 30,
        rejectedEvidencePenalty: 40,
        delayedWorkPenalty: 20,
      },
      "Ward 15": {
        successfulCleaning: 100,
        successfulInspection: 60,
        incompleteWorkPenalty: 20,
        rejectedEvidencePenalty: 30,
        delayedWorkPenalty: 15,
      },
      "Ward 19": {
        successfulCleaning: 110,
        successfulInspection: 65,
        incompleteWorkPenalty: 25,
        rejectedEvidencePenalty: 35,
        delayedWorkPenalty: 15,
      },
      "Ward 22": {
        successfulCleaning: 130,
        successfulInspection: 75,
        incompleteWorkPenalty: 30,
        rejectedEvidencePenalty: 40,
        delayedWorkPenalty: 20,
      },
    },
  },
  workers: [],
  crews: [],
  creditPools: [],
  creditAllocations: [],
  creditAudits: [],
  preferences: {
    notifications: true,
    dailyDigest: true,
  },
});
