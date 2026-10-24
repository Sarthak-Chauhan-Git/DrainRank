import { describe, expect, it } from "vitest";
import { advanceDebugReport, type DebugReport } from "./debugWorkflow";

const newReport: DebugReport = {
  id: "DBG-001",
  reporter: "Test citizen",
  location: "Ward 4",
  issue: "Blocked drain",
  description: "Standing water",
  stage: "inspection_required",
  credits: 0,
};

describe("offline debug workflow", () => {
  it("moves a report through inspection, cleaning, and verified credits", () => {
    const inspected = advanceDebugReport(newReport, "inspect");
    expect(inspected.stage).toBe("cleaning_required");
    expect(inspected.credits).toBe(0);

    const cleaned = advanceDebugReport(inspected, "clean");
    expect(cleaned.stage).toBe("awaiting_verification");
    expect(cleaned.credits).toBe(0);

    const verified = advanceDebugReport(cleaned, "verify");
    expect(verified.stage).toBe("verified");
    expect(verified.credits).toBe(100);
  });

  it("does not award credits before supervisor verification", () => {
    expect(advanceDebugReport(newReport, "verify")).toBe(newReport);
    expect(advanceDebugReport(newReport, "clean")).toBe(newReport);
  });
});
