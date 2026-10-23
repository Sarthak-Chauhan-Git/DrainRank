import type { AppState, DrainRecord, ReportRecord } from "./App";
import { createEmptyData } from "./emptyState";
import { supabase } from "./supabase";

const dashboardKey = "municipal";
let pendingSave: Promise<void> = Promise.resolve();
let loadedUpdatedAt: string | null = null;

export async function loadDashboardState(): Promise<AppState> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const client = supabase;
  const [dashboardResult, citizenResult, fieldTaskResult] = await Promise.all([
    client
      .from("dashboard_state")
      .select("payload,updated_at")
      .eq("id", dashboardKey)
      .maybeSingle(),
    client
      .from("citizen_reports")
      .select(
        "report_id,linked_drain_id,latitude,longitude,issue_category,is_urgent_flagged,description,status,estimated_priority_score,image_url,image_path,captured_at,uploaded_at,created_at",
      )
      .order("created_at", { ascending: false }),
    client
      .from("field_tasks")
      .select("id,status,assigned_to_uid,crew_members"),
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
  if (fieldTaskResult.error) {
    throw new Error(
      `Could not load field tasks: ${fieldTaskResult.error.message}`,
    );
  }

  const citizenReports = await Promise.all(
    citizenResult.data.map(async (row) => {
      let photoUrl = row.image_url;
      if (!photoUrl && row.image_path) {
        const { data, error } = await client.storage
          .from("citizen-photos")
          .createSignedUrl(row.image_path, 3600);
        if (error) {
          throw new Error(`Could not open citizen report photo: ${error.message}`);
        }
        photoUrl = data.signedUrl;
      }
      return mapCitizenReport(row, photoUrl);
    }),
  );
  if (!dashboardResult.data) {
    loadedUpdatedAt = null;
    const empty = createEmptyData();
    return { ...empty, reports: citizenReports };
  }
  loadedUpdatedAt = dashboardResult.data.updated_at;

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

  const tasksById = new Map(
    fieldTaskResult.data.map((task) => [task.id, task]),
  );
  const drains = (state.drains as DrainRecord[]).map((drain) => {
    const task = tasksById.get(drain.id);
    if (!task) return drain;
    return {
      ...drain,
      workStatus: task.status,
    };
  });

  return {
    ...state,
    drains,
    reports: mergeCitizenReports(citizenReports, state.reports),
    preferences: state.preferences ?? {
      notifications: true,
      dailyDigest: true,
    },
  } as AppState;
}

function mapCitizenReport(
  row: {
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
  image_path: string | null;
  captured_at: string;
  uploaded_at: string;
  created_at: string;
  },
  photoUrl: string | null,
): ReportRecord {
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
    photo: photoUrl ?? undefined,
    submittedAt: row.uploaded_at || row.captured_at || row.created_at,
    priority: Number(row.estimated_priority_score),
    reasons: ["Submitted through the citizen app"],
    backendStatus: row.status,
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

    const { data: updatedAt, error } = await supabase.rpc(
      "save_dashboard_state",
      {
        p_payload: state,
        p_expected_updated_at: loadedUpdatedAt,
      },
    );
    if (error) {
      throw new Error(`Could not save dashboard data: ${error.message}`);
    }
    if (typeof updatedAt !== "string") {
      throw new Error("The backend did not confirm the dashboard save.");
    }
    loadedUpdatedAt = updatedAt;

    const { error: statusesError } = await supabase.rpc(
      "update_citizen_report_statuses",
      {
        p_statuses: state.reports.map((report) => ({
          report_id: report.id,
          status:
            report.status === "Resolved"
              ? "resolved"
              : report.status === "Duplicate"
                ? "duplicate"
                : mapOpenReportStatus(report.backendStatus),
        })),
      },
    );
    if (statusesError) {
      throw new Error(
        `Could not synchronize citizen report statuses: ${statusesError.message}`,
      );
    }

    const { error: fieldTaskError } = await supabase.rpc(
      "sync_dashboard_field_tasks",
      { p_tasks: mapDashboardTasks(state) },
    );
    if (fieldTaskError) {
      throw new Error(
        `Could not synchronize field assignments: ${fieldTaskError.message}`,
      );
    }
  };

  const nextSave = pendingSave.catch(() => undefined).then(save);
  pendingSave = nextSave;
  return nextSave;
}

function mapOpenReportStatus(status: string | undefined): string {
  const normalizedStatus = status?.toLowerCase();
  const openStatuses = new Set([
    "complaint_received",
    "under_verification",
    "work_assigned",
    "cleaning_completed",
    "under_monitoring",
  ]);
  return normalizedStatus && openStatuses.has(normalizedStatus)
    ? normalizedStatus
    : "complaint_received";
}

function mapDashboardTasks(state: AppState) {
  return state.drains.map((drain) => {
    const selectedCrews = new Set(
      drain.assignedCrews?.length
        ? drain.assignedCrews
        : (drain.assignedCrew
            ?.split(",")
            .map((name) => name.trim())
            .filter(Boolean) ?? []),
    );
    const selectedCrewRecords = state.crews.filter(
      (crew) => selectedCrews.has(crew.name) || selectedCrews.has(crew.id),
    );
    const municipalIds = new Set(
      selectedCrewRecords.flatMap((crew) => crew.memberIds),
    );
    for (const selected of selectedCrews) municipalIds.add(selected);
    const assignedIds = state.workers
      .filter(
        (worker) =>
          municipalIds.has(worker.id) ||
          selectedCrews.has(worker.currentCrew),
      )
      .map((worker) => worker.id);
    for (const selected of selectedCrews) {
      if (!state.workers.some((worker) => worker.id === selected)) {
        assignedIds.push(selected);
      }
    }
    const deadline = drain.deadlineAt ? new Date(drain.deadlineAt) : new Date();
    const dateKey = Number.isNaN(deadline.getTime())
      ? new Date().toISOString().slice(0, 10)
      : `${deadline.getFullYear()}-${String(deadline.getMonth() + 1).padStart(2, "0")}-${String(deadline.getDate()).padStart(2, "0")}`;
    const title = drain.workStatus?.toLowerCase().startsWith("inspection")
      ? `Inspect ${drain.id}`
      : `Maintain ${drain.id}`;

    return {
      id: drain.id,
      title,
      date_key: dateKey,
      location: drain.location,
      description: drain.reason,
      status: drain.workStatus ?? drain.status,
      assigned_ids: [...new Set(assignedIds)],
      source_report_ids: state.reports
        .filter((report) => report.drainId === drain.id)
        .map((report) => report.id),
    };
  });
}
