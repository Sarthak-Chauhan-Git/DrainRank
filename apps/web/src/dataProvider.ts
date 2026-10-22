import type { AppState, ReportRecord } from "./App";
import { createEmptyData } from "./emptyState";
import { supabase } from "./supabase";

const dashboardKey = "municipal";
let pendingSave: Promise<void> = Promise.resolve();
let loadedRevision = 0;

export async function loadDashboardState(): Promise<AppState> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const [dashboardResult, citizenResult] = await Promise.all([
    supabase
      .from("web_dashboard_state")
      .select("payload,revision")
      .eq("singleton_id", dashboardKey)
      .maybeSingle(),
    supabase
      .from("citizen_reports")
      .select(
        "report_id,linked_drain_id,latitude,longitude,issue_category,is_urgent_flagged,description,status,estimated_priority_score,image_url,captured_at,uploaded_at,created_at",
      )
      .order("created_at", { ascending: false }),
  ]);
  if (dashboardResult.error) {
    throw new Error(
      `Could not load dashboard data: ${dashboardResult.error.message}`,
    );
  }
  if (citizenResult.error) {
    throw new Error(
      `Could not load citizen reports: ${citizenResult.error.message}`,
    );
  }

  const citizenReports = citizenResult.data.map(mapCitizenReport);
  if (!dashboardResult.data) {
    loadedRevision = 0;
    const empty = createEmptyData();
    return { ...empty, reports: citizenReports };
  }
  loadedRevision = dashboardResult.data.revision;

  const state = dashboardResult.data.payload as Partial<AppState> | null;
  if (
    !state ||
    !Array.isArray(state.drains) ||
    !Array.isArray(state.reports) ||
    !Array.isArray(state.activities) ||
    !Array.isArray(state.outcomes) ||
    !Array.isArray(state.workers) ||
    !Array.isArray(state.crews) ||
    !Array.isArray(state.creditPools) ||
    !Array.isArray(state.creditAllocations) ||
    !Array.isArray(state.creditAudits) ||
    !state.creditPolicy
  ) {
    throw new Error(
      "The saved dashboard record is incomplete or incompatible with this app version.",
    );
  }

  return {
    ...state,
    reports: mergeCitizenReports(citizenReports, state.reports),
    preferences: state.preferences ?? {
      notifications: true,
      dailyDigest: true,
    },
  } as AppState;
}

function mapCitizenReport(row: {
  report_id: string;
  linked_drain_id: string;
  latitude: number;
  longitude: number;
  issue_category: string;
  is_urgent_flagged: boolean;
  description: string;
  status: string;
  estimated_priority_score: number;
  image_url: string | null;
  captured_at: string;
  uploaded_at: string;
  created_at: string;
}): ReportRecord {
  const normalizedStatus = row.status.toLowerCase();
  return {
    id: row.report_id,
    drainId: row.linked_drain_id,
    reporterName: "Citizen",
    issueType: row.issue_category
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/[_-]/g, " ")
      .replace(/\b\w/g, (character) => character.toUpperCase()),
    ward: "Unassigned",
    location: `${row.latitude.toFixed(5)}, ${row.longitude.toFixed(5)}`,
    description: row.description,
    urgent: row.is_urgent_flagged,
    photo: row.image_url ?? undefined,
    submittedAt: row.uploaded_at || row.captured_at || row.created_at,
    priority: Number(row.estimated_priority_score),
    reasons: ["Submitted through the citizen app"],
    status: normalizedStatus.includes("duplicate")
      ? "Duplicate"
      : normalizedStatus.includes("resolved")
        ? "Resolved"
        : "Open",
  };
}

function mergeCitizenReports(
  citizenReports: ReportRecord[],
  savedReports: ReportRecord[],
): ReportRecord[] {
  const savedById = new Map(savedReports.map((report) => [report.id, report]));
  const citizenIds = new Set(citizenReports.map((report) => report.id));
  return [
    ...citizenReports.map((report) => {
      const saved = savedById.get(report.id);
      return saved ? { ...report, status: saved.status } : report;
    }),
    ...savedReports.filter((report) => !citizenIds.has(report.id)),
  ];
}

export async function saveDashboardState(state: AppState): Promise<void> {
  const save = async () => {
    if (!supabase) throw new Error("Supabase is not configured.");
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();
    if (userError) {
      throw new Error(`Could not verify dashboard user: ${userError.message}`);
    }
    if (!user) throw new Error("Your session has expired. Sign in again.");

    const { data: revision, error } = await supabase.rpc(
      "save_web_dashboard_state",
      {
        p_payload: state,
        p_expected_revision: loadedRevision,
      },
    );
    if (error) {
      throw new Error(`Could not save dashboard data: ${error.message}`);
    }
    if (typeof revision !== "number") {
      throw new Error("The backend did not confirm the dashboard save.");
    }
    loadedRevision = revision;
  };

  const nextSave = pendingSave.catch(() => undefined).then(save);
  pendingSave = nextSave;
  return nextSave;
}
