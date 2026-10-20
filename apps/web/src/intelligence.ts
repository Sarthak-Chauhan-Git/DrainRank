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

      let nextAction =
        "Continue routine monitoring and record the next inspection outcome.";
      if (overdue) {
        nextAction =
          "Escalate the overdue work item to the ward supervisor and confirm a revised field visit.";
      } else if (awaitingReview) {
        nextAction =
          "Have an authorized reviewer verify location and before/after evidence before approving completion.";
      } else if (persistedOutcomes > 0) {
        nextAction =
          "Inspect the connected downstream section and capture evidence during the next rainfall event.";
      } else if (evidenceNeedsAttention) {
        nextAction =
          "Request clear, location-verifiable field evidence before changing the work status.";
      } else if (
        drain.status === "Cleaning Recommended" ||
        drain.status === "Rework Required"
      ) {
        nextAction =
          "Schedule cleaning, then require verifiable completion evidence for review.";
      } else if (drain.status === "Inspection Required") {
        nextAction =
          "Assign a field inspection to verify blockage severity and update the evidence record.";
      } else if (recurring) {
        nextAction =
          "Schedule a follow-up inspection and compare the next observation with this drain's history.";
      }

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
