import type {
  ActivityEntry,
  DrainRecord,
  OutcomeRecord,
  ReportRecord,
} from "./App";

export type DrainIntelligenceInput = Pick<
  DrainRecord,
  | "id"
  | "location"
  | "ward"
  | "status"
  | "priority"
  | "condition"
  | "evidenceStatus"
  | "lastObservation"
  | "issueType"
  | "deadlineAt"
  | "visibleBlockage"
>;

export type DrainHistoryInput = Pick<
  ReportRecord,
  "drainId" | "issueType" | "status" | "priority" | "submittedAt"
>;

export type DrainOutcomeInput = Pick<
  OutcomeRecord,
  "drainId" | "outcome" | "recommendation" | "timestamp"
>;

export type DrainAuditInput = Pick<
  ActivityEntry,
  "id" | "title" | "timestamp" | "severity"
>;

export interface DrainAssessment {
  drain: DrainIntelligenceInput;
  score: number;
  complaintCount: number;
  priorOutcomeCount: number;
  recurring: boolean;
  overdue: boolean;
  awaitingReview: boolean;
  evidenceNeedsAttention: boolean;
  explanation: string[];
  nextAction: string;
  history: DrainHistoryInput[];
  outcomes: DrainOutcomeInput[];
}

export interface DrainIntelligenceSnapshot {
  cases: DrainAssessment[];
  overdueCount: number;
  awaitingReviewCount: number;
  recurringCount: number;
}

const terminalStatuses = new Set(["Resolved", "Reviewed"]);
const reviewEvidencePattern = /awaiting|pending|rework|mismatch|insufficient/i;

function normalizeRecommendation(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\b(the|a|an|for|to|and|at|in|after|during|with)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function recommendationIntent(value: string) {
  const text = value.toLowerCase();
  if (/downstream|connected drain|network capacity/.test(text)) return "network-check";
  if (/manual evidence review|completion evidence|approval|review evidence/.test(text)) {
    return "evidence-review";
  }
  if (/location-verifiable|evidence gap|verification visit|field observation/.test(text)) {
    return "evidence-capture";
  }
  if (/reschedul|revised visit|overdue|deadline/.test(text)) return "reschedule";
  if (/clean|debris|silt|inlet|obstruction/.test(text)) return "surface-clean";
  if (/rainfall|post-rain|after rainfall|rain event/.test(text)) return "rainfall-check";
  if (/flow|water depth|recession time/.test(text)) return "flow-check";
  if (/inspect|inspection|field visit/.test(text)) return "field-inspection";
  if (/monitor|routine spot check|scheduled check/.test(text)) return "routine-monitoring";
  return null;
}

function isRepeatedRecommendation(candidate: string, previous: string[]) {
  const candidateIntent = recommendationIntent(candidate);
  const candidateTokens = new Set(normalizeRecommendation(candidate).split(" "));
  if (!candidateTokens.size) return false;
  return previous.some((recommendation) => {
    const previousIntent = recommendationIntent(recommendation);
    if (candidateIntent && candidateIntent === previousIntent) return true;
    const previousTokens = new Set(
      normalizeRecommendation(recommendation).split(" "),
    );
    const intersection = [...candidateTokens].filter((token) =>
      previousTokens.has(token),
    ).length;
    const union = new Set([...candidateTokens, ...previousTokens]).size;
    return union > 0 && intersection / union >= 0.5;
  });
}

function buildNextAction(
  drain: DrainIntelligenceInput,
  facts: {
    overdue: boolean;
    awaitingReview: boolean;
    evidenceNeedsAttention: boolean;
    recurring: boolean;
    persistedOutcomes: number;
    complaintCount: number;
  },
  previousRecommendations: string[],
): string {
  const location = drain.location;
  const candidates: string[] = [];

  if (facts.overdue) {
    candidates.push(
      `Confirm the responsible field team and agree a revised visit date for ${location}; keep the case flagged overdue until the inspection or cleaning result is recorded.`,
      `Contact the ward operations lead to reschedule the overdue ${drain.issueType.toLowerCase()} work at ${location}, then update its deadline after the team confirms availability.`,
    );
  } else if (facts.awaitingReview) {
    candidates.push(
      `Complete the pending manual evidence review for ${location}; verify the location and work result before changing the status.`,
      `Compare the submitted completion evidence with the recorded drain location at ${location}, then record an approval or correction request.`,
    );
  } else if (drain.status === "Assigned") {
    candidates.push(
      `Check the assigned work progress at ${location} against its deadline and record the next field update; escalate only if the deadline is at risk.`,
      `Confirm whether the scheduled ${drain.issueType.toLowerCase()} visit at ${location} is underway, then update the case status from the field result.`,
    );
  } else if (
    facts.persistedOutcomes > 0 &&
    (drain.visibleBlockage == null || drain.visibleBlockage < 80)
  ) {
    candidates.push(
      `Because earlier work did not prevent recurrence at ${location}, inspect the nearest downstream connection and record flow before scheduling another clean.`,
      `Trace the connected drain section beyond ${location} during a field visit; compare the observation with the last persistent outcome before repeating surface cleaning.`,
    );
  } else if (facts.evidenceNeedsAttention) {
    candidates.push(
      `Request a new location-verifiable field observation for ${location} before changing its status; include a clear view of the affected drain section.`,
      `Arrange a short verification visit at ${location} to resolve the evidence gap, then update the case using the observed condition.`,
    );
  } else if (drain.status === "Cleaning Recommended") {
    if (drain.visibleBlockage != null && drain.visibleBlockage >= 80) {
      candidates.push(
        `Schedule a targeted inlet clean at ${location}; record a post-clean flow check before closing the work.`,
        `Assign the blocked section at ${location} for debris removal, then compare a clear follow-up observation with the current blockage record.`,
      );
    } else if (drain.visibleBlockage != null && drain.visibleBlockage >= 40) {
      candidates.push(
        `Inspect and clear the restricted inlet at ${location}; record whether water flow improves before closing the task.`,
        `Check for removable silt or debris at ${location}, then update the blockage estimate from a fresh field observation.`,
      );
    } else {
      candidates.push(
        `Verify the reported restriction at ${location} during a field visit; clean only the obstruction confirmed on site.`,
        `Check inlet flow at ${location} before dispatching a full clean, then record the observed blockage and any immediate maintenance completed.`,
      );
    }
  } else if (drain.issueType.toLowerCase().includes("waterlog")) {
    candidates.push(
      `Observe water flow at ${location} during or just after rainfall; if the drain is clear, trace the nearest downstream connection before ordering cleaning.`,
      `At the next safe rainfall check, record water depth and recession time at ${location}; use that observation to decide whether a downstream inspection is needed.`,
    );
  } else if (facts.recurring || facts.persistedOutcomes > 0) {
    candidates.push(
      `Compare the next post-rain observation at ${location} with its ${facts.complaintCount} linked complaints; inspect the connected downstream section if waterlogging returns.`,
      `Schedule one follow-up check at ${location} after rainfall and record whether the same issue recurs before widening the maintenance scope.`,
    );
  } else if (drain.status === "Inspection Required") {
    candidates.push(
      `Assign a field inspection at ${location} to measure visible blockage and confirm flow; update the case from the observed condition.`,
      `Verify the affected drain section at ${location} and record a dated condition estimate before deciding between cleaning and monitoring.`,
    );
  } else if (drain.status === "Monitoring" || drain.status === "Reviewed") {
    candidates.push(
      `Keep ${location} on routine monitoring and record a targeted check after the next rainfall; reopen work only if the issue is observed again.`,
      `At the next scheduled ward inspection, verify flow at ${location} and compare it with the latest observation before changing its status.`,
    );
  } else if (drain.status === "Resolved") {
    candidates.push(
      `Confirm the next routine observation at ${location}; reopen the case only if the same drainage issue is seen again.`,
      `Add ${location} to the next scheduled inspection round and verify the resolved condition remains clear.`,
    );
  } else {
    candidates.push(
      `Review the latest field condition at ${location} and assign the smallest follow-up task supported by that observation.`,
      `Confirm the current condition at ${location} with a field check, then route the case to cleaning or routine monitoring based on evidence.`,
    );
  }

  const newAction = candidates.find(
    (candidate) =>
      !isRepeatedRecommendation(candidate, previousRecommendations),
  );
  if (newAction) return newAction;

  return `At ${location}, perform a fresh condition check and record the observed result before selecting a follow-up action; the recent recommendation history already covers the other proposed steps.`;
}

export function analyzeDrainRecords(
  drains: readonly DrainIntelligenceInput[],
  reports: readonly DrainHistoryInput[],
  outcomes: readonly DrainOutcomeInput[],
  now = new Date(),
): DrainIntelligenceSnapshot {
  const cases = drains
    .map((drain): DrainAssessment => {
      const history = reports
        .filter(
          (report) =>
            report.drainId === drain.id && report.status !== "Duplicate",
        )
        .sort(
          (left, right) =>
            new Date(right.submittedAt).getTime() -
            new Date(left.submittedAt).getTime(),
        );
      const priorOutcomes = outcomes
        .filter((outcome) => outcome.drainId === drain.id)
        .sort(
          (left, right) =>
            new Date(right.timestamp).getTime() -
            new Date(left.timestamp).getTime(),
        );
      const overdue =
        Boolean(drain.deadlineAt) &&
        new Date(drain.deadlineAt as string).getTime() < now.getTime() &&
        !terminalStatuses.has(drain.status);
      const awaitingReview = drain.status === "Pending Review";
      const evidenceNeedsAttention =
        reviewEvidencePattern.test(drain.evidenceStatus) ||
        drain.status === "Rework Required";
      const persistedOutcomes = priorOutcomes.filter(
        (outcome) => outcome.outcome === "Persisted",
      ).length;
      const recurring = history.length >= 2 || persistedOutcomes > 0;
      const recurrenceBoost = Math.min(
        18,
        Math.max(0, history.length - 1) * 3 + persistedOutcomes * 6,
      );
      const score = Math.min(
        100,
        Math.max(0, Math.round(drain.priority + recurrenceBoost)),
      );
      const explanation = [
        `Current operational priority: ${Math.round(drain.priority)}/100.`,
      ];

      if (history.length > 1) {
        explanation.push(`${history.length} linked complaints indicate recurrence.`);
      }
      if (persistedOutcomes > 0) {
        explanation.push(
          `${persistedOutcomes} prior outcome(s) recorded a persistent issue.`,
        );
      }
      if (overdue) explanation.push("The work deadline has passed.");
      if (evidenceNeedsAttention) {
        explanation.push("Evidence is pending, flagged, or requires attention.");
      }
      if (history.length <= 1 && persistedOutcomes === 0) {
        explanation.push("No repeated issue is recorded in the available history.");
      }

      const nextAction = buildNextAction(
        drain,
        {
          overdue,
          awaitingReview,
          evidenceNeedsAttention,
          recurring,
          persistedOutcomes,
          complaintCount: history.length,
        },
        priorOutcomes.map((outcome) => outcome.recommendation),
      );

      return {
        drain,
        score,
        complaintCount: history.length,
        priorOutcomeCount: priorOutcomes.length,
        recurring,
        overdue,
        awaitingReview,
        evidenceNeedsAttention,
        explanation,
        nextAction,
        history,
        outcomes: priorOutcomes,
      };
    })
    .sort(
      (left, right) =>
        right.score - left.score ||
        left.drain.id.localeCompare(right.drain.id),
    );

  return {
    cases,
    overdueCount: cases.filter((item) => item.overdue).length,
    awaitingReviewCount: cases.filter((item) => item.awaitingReview).length,
    recurringCount: cases.filter((item) => item.recurring).length,
  };
}

const personalDataRequest =
  /\b(reporter|who reported|personal data|personal details|phone number|email address|contact details|citizen name|resident name|worker name|crew member name|assigned crew name|who is assigned)\b/i;
const drainWorkQuery =
  /\b(drains?|drainage|block(?:age|ed)?|waterlog(?:ging)?|overflow|complaint|inspection|evidence|priority|overdue|history|ward|clean(?:ing)?|recurr(?:ing|ence)?|status|case|work order|asset)\b/i;

export function answerDrainRankQuestion(
  question: string,
  cases: readonly DrainAssessment[],
): string {
  const query = question.trim();
  if (!query) return "Ask a question about drainage operations or a DrainRank case.";

  const idMatch = query.match(/\bDR-[A-Z0-9-]+\b/i);
  if (personalDataRequest.test(query)) {
    return "I can only assist with DrainRank drainage operations. I cannot retrieve or disclose personal, reporter, resident, or worker information.";
  }
  if (!drainWorkQuery.test(query) && !idMatch) {
    return "I can only answer DrainRank work-related questions about drainage cases, inspections, evidence, priorities, deadlines, and operational history.";
  }

  const normalizedQuery = query.toLowerCase();
  const selectedCase = idMatch
    ? cases.find((item) => item.drain.id.toLowerCase() === idMatch[0].toLowerCase())
    : cases.find((item) =>
        `${item.drain.location} ${item.drain.ward} ${item.drain.issueType}`
          .toLowerCase()
          .split(/[\s,/-]+/)
          .some((term) => term.length > 3 && normalizedQuery.includes(term)),
      );

  if (selectedCase) {
    const { drain, explanation, nextAction, score } = selectedCase;
    const wardPrefix = `${drain.ward}, `;
    const location = drain.location
      .toLowerCase()
      .startsWith(wardPrefix.toLowerCase())
      ? drain.location.slice(wardPrefix.length)
      : drain.location;
    return `${drain.id} (${drain.ward}, ${location}) has a DrainRank score of ${score}/100 and is currently "${drain.status}". ${explanation.join(" ")} Recommended next action: ${nextAction}`;
  }

  if (/\boverdue\b/i.test(query)) {
    const overdueCases = cases.filter((item) => item.overdue);
    return overdueCases.length
      ? `${overdueCases.length} drainage work item(s) are overdue: ${overdueCases.map((item) => item.drain.id).join(", ")}. Escalate each with its ward supervisor and confirm a revised field visit.`
      : "No drainage work items are currently overdue in the available records.";
  }

  if (/\brecurr(?:ing|ence)?\b/i.test(query)) {
    const recurringCases = cases.filter((item) => item.recurring);
    return recurringCases.length
      ? `${recurringCases.length} drain(s) have recurring complaint or persistent-outcome history: ${recurringCases.map((item) => item.drain.id).join(", ")}. Prioritize follow-up inspections and compare subsequent evidence.`
      : "No recurring drainage issues are recorded in the available case history.";
  }

  return `DrainRank is monitoring ${cases.length} drainage cases. The highest-ranked active case is ${cases.find((item) => !terminalStatuses.has(item.drain.status))?.drain.id ?? "not available"}. Ask about a case ID, recurrence, overdue work, evidence, or recommended actions.`;
}

export type DrainReviewAction = "Accept" | "Request Rework" | "Flag Location Mismatch";
