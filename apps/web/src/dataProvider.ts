import type { AppState, DrainRecord, ReportRecord } from "./App";
import { createEmptyData } from "./emptyState";
import {
  groupReportsByFirstAnchor,
  priorityWithReportVolume,
} from "./reportGrouping";
import { supabase } from "./supabase";
import { signDashboardImage } from "./supabaseStorage";

const dashboardKey = "municipal";
let pendingSave: Promise<void> = Promise.resolve();
let loadedUpdatedAt: string | null = null;

function directCleaningReportsError(
  action: "load" | "refresh",
  error: { code: string; message: string },
): Error {
  const missingTable = error.code === "PGRST205" || error.code === "42P01";
  const actionLabel = action === "load" ? "load" : "refresh";
  const message = missingTable
    ? "the public.direct_cleaning_reports table is missing from Supabase. Run backend/supabase/migrations/202610240002_direct_cleaning_reports.sql in the Supabase SQL Editor, then reload the schema cache."
    : error.message;
  return new Error(`Could not ${actionLabel} direct cleaning reports: ${message}`);
}

export async function loadDashboardState(): Promise<AppState> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const client = supabase;
  const [
    dashboardResult,
    citizenResult,
    fieldTaskResult,
    directReportResult,
  ] = await Promise.all([
    client
      .from("dashboard_state")
      .select("payload,updated_at")
      .eq("id", dashboardKey)
      .maybeSingle(),
    client
      .from("citizen_reports")
      .select(
        "report_id,linked_drain_id,latitude,longitude,issue_category,is_urgent_flagged,description,status,estimated_priority_score,image_path,captured_at,uploaded_at,created_at",
      )
      .order("created_at", { ascending: false }),
    client
      .from("field_tasks")
      .select(
        "id,title,status,assigned_to_uid,crew_members,inspection_outcome",
      ),
    client
      .from("direct_cleaning_reports")
      .select(
        "report_id,reporter_uid,issue_category,description,ward,location_description,latitude,longitude,accuracy_meters,photo_path,captured_at,review_status,created_at",
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
  if (fieldTaskResult.error) {
    throw new Error(
      `Could not load field tasks: ${fieldTaskResult.error.message}`,
    );
  }
  if (directReportResult.error) {
    throw directCleaningReportsError("load", directReportResult.error);
  }

  const citizenReports = await mapCitizenRows(citizenResult.data);
  const directReports = await mapDirectCleaningRows(directReportResult.data);
  if (!dashboardResult.data) {
    loadedUpdatedAt = null;
    return mergeCitizenWorkflow(
      createEmptyData(),
      citizenReports,
      fieldTaskResult.data,
      directReports,
    );
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
  const withdrawnCitizenReportIds = new Set(
    citizenResult.data
      .filter((report) => report.status.toLowerCase() === "withdrawn")
      .map((report) => report.report_id),
  );
  const drains = (state.drains as DrainRecord[]).map((drain) => {
    const task = tasksById.get(drain.id);
    if (!task) return drain;
    return {
      ...drain,
      fieldTaskStatus: task.status,
      inspectionOutcome: task.inspection_outcome,
      workStatus:
        drain.workStatus?.startsWith("Inspection assigned") ||
        drain.workStatus?.startsWith("Cleaning assigned")
          ? drain.workStatus
          : task.status,
    };
  });

  const hydratedState = await hydrateDashboardImages({
    ...state,
    drains,
    reports: state.reports.filter(
      (report) => !withdrawnCitizenReportIds.has(report.id),
    ),
  } as AppState);
  return mergeCitizenWorkflow(
    hydratedState,
    citizenReports,
    fieldTaskResult.data,
    directReports,
  );
}

async function hydrateDashboardImages(state: AppState): Promise<AppState> {
  const [drains, reports] = await Promise.all([
    Promise.all(
      state.drains.map(async (drain) => {
        if (!drain.evidencePhotoPath) {
          return drain.evidencePhoto
            ? {
                ...drain,
                evidencePhoto: undefined,
                evidencePhotoLoadError:
                  "This image must be uploaded again to Supabase Storage.",
              }
            : drain;
        }
        const result = await signDashboardImage(drain.evidencePhotoPath);
        return {
          ...drain,
          evidencePhoto: result.signedUrl,
          evidencePhotoLoadError: result.error,
        };
      }),
    ),
    Promise.all(
      state.reports.map(async (report) => {
        if (!report.photoPath) {
          return report.photo
            ? {
                ...report,
                photo: undefined,
                photoLoadError:
                  "This image must be uploaded again to Supabase Storage.",
              }
            : report;
        }
        const result = await signDashboardImage(report.photoPath);
        return {
          ...report,
          photo: result.signedUrl,
          photoLoadError: result.error,
        };
      }),
    ),
  ]);

  return { ...state, drains, reports };
}

export async function refreshCitizenWorkflow(
  state: AppState,
): Promise<Pick<AppState, "drains" | "reports">> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const [citizenResult, fieldTaskResult, directReportResult] =
    await Promise.all([
    supabase
      .from("citizen_reports")
      .select(
        "report_id,linked_drain_id,latitude,longitude,issue_category,is_urgent_flagged,description,status,estimated_priority_score,image_path,captured_at,uploaded_at,created_at",
      )
      .order("created_at", { ascending: false }),
    supabase
      .from("field_tasks")
      .select("id,title,status,assigned_to_uid,crew_members,inspection_outcome"),
    supabase
      .from("direct_cleaning_reports")
      .select(
        "report_id,reporter_uid,issue_category,description,ward,location_description,latitude,longitude,accuracy_meters,photo_path,captured_at,review_status,created_at",
      )
      .order("created_at", { ascending: false }),
  ]);
  if (citizenResult.error) {
    throw new Error(`Could not refresh citizen reports: ${citizenResult.error.message}`);
  }
  if (fieldTaskResult.error) {
    throw new Error(`Could not refresh field tasks: ${fieldTaskResult.error.message}`);
  }
  if (directReportResult.error) {
    throw directCleaningReportsError("refresh", directReportResult.error);
  }
  const citizenReports = await mapCitizenRows(citizenResult.data);
  const directReports = await mapDirectCleaningRows(directReportResult.data);
  const refreshed = await mergeCitizenWorkflow(
    state,
    citizenReports,
    fieldTaskResult.data,
    directReports,
  );
  return { drains: refreshed.drains, reports: refreshed.reports };
}

async function mergeCitizenWorkflow(
  state: AppState,
  citizenReports: ReportRecord[],
  fieldTasks: FieldTaskRow[],
  directReports: DirectCleaningReportRecord[] = [],
): Promise<AppState> {
  const existingGroups = new Map(
    state.drains
      .filter((drain) => drain.citizenReportGroup)
      .map((drain) => [drain.id, drain]),
  );
  const tasksById = new Map(fieldTasks.map((task) => [task.id, task]));
  const existingDirectReports = new Map(
    state.drains
      .filter((drain) => drain.directCleaningReport)
      .map((drain) => [drain.id, drain]),
  );
  const {
    reports: groupedReports,
    drains: citizenReportDrains,
  } = buildCitizenReportGroups(
    citizenReports,
    existingGroups,
    tasksById,
  );
  return {
    ...state,
    drains: [
      ...state.drains.filter(
        (drain) => !drain.citizenReportGroup && !drain.directCleaningReport,
      ),
      ...citizenReportDrains,
      ...buildDirectCleaningDrains(
        directReports,
        existingDirectReports,
        tasksById,
      ),
    ],
    reports: mergeCitizenReports(groupedReports, state.reports),
    preferences: state.preferences ?? {
      notifications: true,
      dailyDigest: true,
    },
  };
}

type CitizenReportRow = {
  report_id: string;
  linked_drain_id: string;
  latitude: number;
  longitude: number;
  issue_category: string;
  is_urgent_flagged: boolean;
  description: string;
  status: string;
  estimated_priority_score: number;
  image_path: string | null;
  captured_at: string;
  uploaded_at: string;
  created_at: string;
};

type FieldTaskRow = {
  id: string;
  title: string;
  status: string;
  assigned_to_uid: string[];
  crew_members: unknown;
  inspection_outcome: "cleaning_required" | "no_cleaning_required" | null;
};

type DirectCleaningReportRecord = {
  report_id: string;
  reporter_uid: string;
  issue_category: string;
  description: string;
  ward: string;
  location_description: string;
  latitude: number;
  longitude: number;
  accuracy_meters: number;
  photo_path: string;
  captured_at: string;
  review_status: "pending" | "verified" | "rejected";
  created_at: string;
  photoUrl?: string;
  photoLoadError?: string;
};

async function mapDirectCleaningRows(
  rows: Omit<DirectCleaningReportRecord, "photoUrl" | "photoLoadError">[],
): Promise<DirectCleaningReportRecord[]> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const client = supabase;
  return Promise.all(
    rows
      .filter((row) => row.review_status !== "rejected")
      .map(async (row) => {
        const { data, error } = await client.storage
          .from("field-direct-reports")
          .createSignedUrl(row.photo_path, 3600);
        return {
          ...row,
          photoUrl: error ? undefined : data?.signedUrl,
          photoLoadError: error?.message,
        };
      }),
  );
}

function buildDirectCleaningDrains(
  reports: DirectCleaningReportRecord[],
  existing: Map<string, DrainRecord>,
  tasksById: Map<string, FieldTaskRow>,
): DrainRecord[] {
  return reports.map((report) => {
    const previous = existing.get(report.report_id);
    const task = tasksById.get(report.report_id);
    const location = `${report.location_description} (${report.latitude.toFixed(5)}, ${report.longitude.toFixed(5)})`;
    return {
      ...previous,
      id: report.report_id,
      directCleaningReport: true,
      directReportReviewStatus: report.review_status,
      directReportPhoto: report.photoUrl,
      directReportDescription: report.description,
      directReportReporterUid: report.reporter_uid,
      fieldTaskStatus: task?.status ?? previous?.fieldTaskStatus ?? "Pending",
      location,
      ward: report.ward,
      reason: report.description,
      status: previous?.status ?? "Cleaning Recommended",
      priority: previous?.priority ?? 75,
      consequence: previous?.consequence ?? 0.8,
      catchment: previous?.catchment ?? 0.8,
      visibleBlockage: previous?.visibleBlockage ?? 75,
      evidenceUncertainty: previous?.evidenceUncertainty ?? 0.2,
      condition: "Crew-reported cleaning needed",
      evidenceStatus:
        report.review_status === "verified"
          ? "Direct report verified"
          : "Direct report awaiting verification",
      lastObservation: report.captured_at,
      workStatus: previous?.workStatus ?? "Direct report · cleaning queue",
      issueType: report.issue_category
        .replace(/_/g, " ")
        .replace(/\b\w/g, (character) => character.toUpperCase()),
      mapPosition: [report.latitude, report.longitude],
      lastUpdated: report.created_at,
    };
  });
}

function buildCitizenReportGroups(
  reports: ReportRecord[],
  existingGroups: Map<string, DrainRecord>,
  tasksById: Map<string, FieldTaskRow>,
): { reports: ReportRecord[]; drains: DrainRecord[] } {
  const locatedReports = reports.map((report) => {
    if (
      typeof report.latitude !== "number" ||
      typeof report.longitude !== "number"
    ) {
      throw new Error(`Citizen report ${report.id} has no valid location.`);
    }
    return {
      ...report,
      latitude: report.latitude,
      longitude: report.longitude,
    };
  });
  const groups = groupReportsByFirstAnchor(locatedReports);

  const drains: DrainRecord[] = [];
  for (const group of groups) {
    const anchor = group.anchor;
    const id = `CRQ-${anchor.id}`;
    const sourceReportIds = group.members.map((report) => report.id);
    const previous = existingGroups.get(id);
    const task = tasksById.get(id);
    const newReportArrived = Boolean(
      previous &&
        sourceReportIds.some(
          (reportId) => !previous.sourceReportIds?.includes(reportId),
        ),
    );
    const shouldReopen =
      newReportArrived &&
      (previous?.status === "Monitoring" ||
        previous?.status === "Reviewed" ||
        previous?.status === "Resolved");
    const inspectionOutcome = shouldReopen
      ? null
      : (task?.inspection_outcome ?? previous?.inspectionOutcome ?? null);
    const priority = priorityWithReportVolume(
      group.members.map((report) => report.priority),
    );
    const reportIds = sourceReportIds.join(", ");
    let status: DrainRecord["status"] = shouldReopen
      ? "Inspection Required"
      : (previous?.status ?? "Inspection Required");
    let workStatus = shouldReopen
      ? "Inspection queued"
      : (previous?.workStatus ?? "Inspection queued");
    let assignedCrew = shouldReopen ? undefined : previous?.assignedCrew;
    let assignedCrews = shouldReopen ? [] : previous?.assignedCrews;
    let fieldTaskStatus = shouldReopen
      ? "Pending"
      : (task?.status ?? previous?.fieldTaskStatus ?? "Pending");
    const cleaningPhaseActive = previous?.workStatus?.startsWith(
      "Cleaning assigned",
    );
    if (
      inspectionOutcome === "cleaning_required" &&
      !cleaningPhaseActive
    ) {
      status = "Cleaning Recommended";
      workStatus = "Inspection completed · cleaning required";
      assignedCrew = undefined;
      assignedCrews = [];
      fieldTaskStatus = "Completed";
    } else if (
      inspectionOutcome === "no_cleaning_required" &&
      !cleaningPhaseActive
    ) {
      status = "Monitoring";
      workStatus = "Inspection completed · monitoring";
      assignedCrew = undefined;
      assignedCrews = [];
      fieldTaskStatus = "Completed";
    }
    const location = `${anchor.latitude!.toFixed(5)}, ${anchor.longitude!.toFixed(5)}`;
    const groupReason =
      `${group.members.length} citizen report${group.members.length === 1 ? "" : "s"} within 1 km of the first report (${anchor.id}); ` +
      `priority increased by ${5 * (group.members.length - 1)} points.`;
    const drain: DrainRecord = {
      ...previous,
      id,
      citizenReportGroup: true,
      sourceReportIds,
      anchorLatitude: anchor.latitude,
      anchorLongitude: anchor.longitude,
      fieldTaskStatus,
      inspectionOutcome,
      location,
      ward: previous?.ward ?? "Unassigned",
      reason: `${groupReason} Reports: ${reportIds}.`,
      status,
      priority,
      consequence: previous?.consequence ?? 0.7,
      catchment: previous?.catchment ?? 0.8,
      visibleBlockage: previous?.visibleBlockage ?? 0,
      evidenceUncertainty: previous?.evidenceUncertainty ?? 1,
      condition: "Citizen report cluster awaiting field inspection",
      evidenceStatus:
        inspectionOutcome === "cleaning_required"
          ? "Inspection complete; cleaning required"
          : inspectionOutcome === "no_cleaning_required"
            ? "Inspection complete; monitoring"
            : "Citizen reports awaiting inspection",
      lastObservation: anchor.submittedAt,
      assignedCrew,
      assignedCrews,
      workStatus,
      issueType: anchor.issueType,
      mapPosition: [anchor.latitude!, anchor.longitude!],
      lastUpdated: anchor.submittedAt,
    };
    drains.push(drain);
    for (const report of group.members) {
      report.drainId = id;
      report.priority = priority;
      report.reasons = [
        `${group.members.length} report${group.members.length === 1 ? "" : "s"} within 1 km of the first report`,
        `Area priority increased by ${5 * (group.members.length - 1)} points`,
      ];
      if (inspectionOutcome === "no_cleaning_required") {
        report.backendStatus = "under_monitoring";
      } else if (inspectionOutcome === "cleaning_required") {
        report.backendStatus = "work_assigned";
      }
    }
  }
  return { reports, drains };
}

async function mapCitizenRows(rows: CitizenReportRow[]): Promise<ReportRecord[]> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const client = supabase;
  return Promise.all(
    rows
      .filter((row) => row.status.toLowerCase() !== "withdrawn")
      .map(async (row) => {
      if (
        !Number.isFinite(row.latitude) ||
        !Number.isFinite(row.longitude) ||
        row.latitude < -90 ||
        row.latitude > 90 ||
        row.longitude < -180 ||
        row.longitude > 180
      ) {
        throw new Error(
          `Citizen report ${row.report_id} has invalid location coordinates.`,
        );
      }
      let photoUrl: string | null = null;
      let photoLoadError: string | undefined;
      if (row.image_path) {
        const { data, error } = await client.storage
          .from("citizen-photos")
          .createSignedUrl(row.image_path, 3600);
        if (error) {
          photoLoadError = error.message;
        } else if (!data?.signedUrl) {
          throw new Error(
            `The photo service returned no URL for citizen report ${row.report_id}.`,
          );
        } else {
          photoUrl = data.signedUrl;
        }
      }
      return mapCitizenReport(row, photoUrl, photoLoadError);
      }),
  );
}

function mapCitizenReport(
  row: CitizenReportRow,
  photoUrl: string | null,
  photoLoadError?: string,
): ReportRecord {
  const normalizedStatus = row.status.toLowerCase();
  return {
    id: row.report_id,
    drainId: row.linked_drain_id,
    latitude: row.latitude,
    longitude: row.longitude,
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
    photoLoadError,
    submittedAt: row.created_at || row.uploaded_at || row.captured_at,
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

export async function resetOperationalData(
  state: AppState,
): Promise<{ photoCleanupError: string | null }> {
  if (!supabase) throw new Error("Supabase is not configured.");
  await pendingSave.catch(() => undefined);

  const { error } = await supabase.rpc("reset_operational_data", {
    p_payload: state,
  });
  if (error) {
    throw new Error(`Could not reset operational data: ${error.message}`);
  }

  const photoCleanupError = await deleteStoredPhotos();
  return { photoCleanupError };
}

async function deleteStoredPhotos(): Promise<string | null> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const errors: string[] = [];

  for (const bucketName of [
    "citizen-photos",
    "work-photos",
    "dashboard-evidence",
  ]) {
    const bucket = supabase.storage.from(bucketName);
    try {
      const paths = await listStoredFiles(bucket, "");
      for (let offset = 0; offset < paths.length; offset += 100) {
        const { error } = await bucket.remove(paths.slice(offset, offset + 100));
        if (error) throw error;
      }
    } catch (error) {
      errors.push(
        `${bucketName}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  return errors.length ? errors.join("; ") : null;
}

async function listStoredFiles(
  bucket: NonNullable<typeof supabase>["storage"]["from"] extends (
    bucket: string,
  ) => infer StorageBucket
    ? StorageBucket
    : never,
  folder: string,
): Promise<string[]> {
  const paths: string[] = [];
  const pageSize = 100;
  let offset = 0;

  while (true) {
    const { data, error } = await bucket.list(folder, {
      limit: pageSize,
      offset,
    });
    if (error) throw error;

    for (const entry of data) {
      const path = folder ? `${folder}/${entry.name}` : entry.name;
      if (entry.id === null) {
        paths.push(...(await listStoredFiles(bucket, path)));
      } else {
        paths.push(path);
      }
    }
    if (data.length < pageSize) break;
    offset += pageSize;
  }

  return paths;
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
      status: drain.fieldTaskStatus ?? drain.workStatus ?? drain.status,
      inspection_outcome: drain.inspectionOutcome ?? null,
      assigned_ids: [...new Set(assignedIds)],
      source_report_ids: state.reports
        .filter((report) => report.drainId === drain.id)
        .map((report) => report.id),
    };
  });
}
