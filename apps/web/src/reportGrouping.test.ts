import { describe, expect, it } from "vitest";
import {
  citizenCleaningTaskId,
  fieldTaskIdForDrain,
  groupReportsByFirstAnchor,
  priorityWithReportVolume,
  shouldReopenCitizenReportGroup,
} from "./reportGrouping";

describe("citizen report grouping", () => {
  it("uses the first report as a fixed center for each 1 km area", () => {
    const groups = groupReportsByFirstAnchor([
      {
        id: "second",
        latitude: 28.008,
        longitude: 77,
        submittedAt: "2026-01-02T00:00:00Z",
      },
      {
        id: "third",
        latitude: 28.016,
        longitude: 77,
        submittedAt: "2026-01-03T00:00:00Z",
      },
      {
        id: "first",
        latitude: 28,
        longitude: 77,
        submittedAt: "2026-01-01T00:00:00Z",
      },
    ]);

    expect(groups).toHaveLength(2);
    expect(groups[0].anchor.id).toBe("first");
    expect(groups[0].members.map((report) => report.id)).toEqual([
      "first",
      "second",
    ]);
    expect(groups[1].anchor.id).toBe("third");
  });

  it("raises priority by five points for each additional nearby report", () => {
    expect(priorityWithReportVolume([61])).toBe(61);
    expect(priorityWithReportVolume([61, 40, 70])).toBe(80);
  });

  it("caps area priority at 100", () => {
    expect(priorityWithReportVolume([98, 99])).toBe(100);
  });

  it("reopens a completed cleaning recommendation for a new citizen report", () => {
    expect(
      shouldReopenCitizenReportGroup(true, "Cleaning Recommended"),
    ).toBe(true);
  });

  it("does not reopen a group without a new report or during active work", () => {
    expect(
      shouldReopenCitizenReportGroup(false, "Cleaning Recommended"),
    ).toBe(false);
    expect(shouldReopenCitizenReportGroup(true, "Assigned")).toBe(false);
  });

  it("gives citizen cleaning work a task ID distinct from its inspection", () => {
    expect(citizenCleaningTaskId("CRQ-report-1")).toBe("CLN-CRQ-report-1");
    expect(citizenCleaningTaskId("CRQ-report-1")).not.toBe("CRQ-report-1");
    expect(
      fieldTaskIdForDrain({
        id: "CRQ-report-1",
        citizenReportGroup: true,
        workStatus: "Cleaning assigned · evidence pending",
      }),
    ).toBe("CLN-CRQ-report-1");
    expect(
      fieldTaskIdForDrain({
        id: "CRQ-report-1",
        citizenReportGroup: true,
        fieldTaskId: "CLN-CRQ-report-1",
      }),
    ).toBe("CLN-CRQ-report-1");
  });
});
