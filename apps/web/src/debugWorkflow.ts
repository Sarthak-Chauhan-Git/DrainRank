export type DebugStage =
  | "inspection_required"
  | "cleaning_required"
  | "awaiting_verification"
  | "verified";

export interface DebugReport {
  id: string;
  reporter: string;
  location: string;
  issue: string;
  description: string;
  stage: DebugStage;
  credits: number;
}

export type DebugAction = "inspect" | "clean" | "verify";

export function advanceDebugReport(
  report: DebugReport,
  action: DebugAction,
): DebugReport {
  if (action === "inspect" && report.stage === "inspection_required") {
    return { ...report, stage: "cleaning_required" };
  }
  if (action === "clean" && report.stage === "cleaning_required") {
    return { ...report, stage: "awaiting_verification" };
  }
  if (action === "verify" && report.stage === "awaiting_verification") {
    return { ...report, stage: "verified", credits: 100 };
  }
  return report;
}
