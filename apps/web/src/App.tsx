import { useContext, useEffect, useMemo, useRef, useState } from "react";
import {
  BrowserRouter,
  NavLink,
  Navigate,
  Route,
  Routes,
  useNavigate,
} from "react-router-dom";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  MapContainer,
  CircleMarker,
  Marker,
  Polyline,
  TileLayer,
  Tooltip as MapTooltip,
} from "react-leaflet";
import { divIcon } from "leaflet";
import {
  Award,
  Bell,
  BrainCircuit,
  Building2,
  CheckCheck,
  ClipboardCheck,
  ChevronRight,
  ClipboardList,
  Download,
  Droplets,
  Eye,
  Gauge,
  Mail,
  MapPinned,
  MoreVertical,
  PanelLeftClose,
  PanelLeftOpen,
  ShieldAlert,
  Search,
  ShieldCheck,
  Settings,
  Trash2,
  UsersRound,
  Wrench,
} from "lucide-react";
import { createEmptyData } from "./emptyState";
import {
  loadDashboardState,
  resetOperationalData,
  refreshCitizenWorkflow,
  refreshCrewRoster,
  saveDashboardState,
} from "./dataProvider";
import { uploadDashboardImage } from "./supabaseStorage";
import { DashboardSessionContext } from "./dashboardSession";
import { supabase } from "./supabase";
import { citizenCleaningTaskId } from "./reportGrouping";
import GlobalDrainAssistant from "./GlobalDrainAssistant";
import MonitoringIntelligencePage from "./MonitoringIntelligencePage";

export type DrainStatus =
  | "Cleaning Recommended"
  | "Inspection Required"
  | "Monitoring"
  | "Resolved"
  | "Assigned"
  | "Pending Review"
  | "Reviewed"
  | "Rework Required";

type OutcomeType =
  | "Resolved"
  | "Partially Resolved"
  | "Persisted"
  | "Not Observed";

type ActivitySeverity = "info" | "warning" | "success" | "danger";

function mergeRefreshedWorkflow(
  current: AppState,
  refreshed: Pick<AppState, "drains" | "reports">,
): AppState {
  const signature = (state: Pick<AppState, "drains" | "reports">) =>
    JSON.stringify({
      reports: state.reports.map(
        ({ id, drainId, priority, status, backendStatus }) => ({
          id,
          drainId,
          priority,
          status,
          backendStatus,
        }),
      ),
      groups: state.drains
        .filter((drain) => drain.citizenReportGroup)
        .map(
          ({
            id,
            status,
            priority,
            workStatus,
            fieldTaskStatus,
            fieldTaskId,
            inspectionOutcome,
            sourceReportIds,
          }) => ({
            id,
            status,
            priority,
            workStatus,
            fieldTaskStatus,
            fieldTaskId,
            inspectionOutcome,
            sourceReportIds,
          }),
        ),
    });
  if (signature(current) === signature(refreshed)) return current;
  return {
    ...current,
    reports: refreshed.reports,
    drains: [
      ...current.drains.filter((drain) => !drain.citizenReportGroup),
      ...refreshed.drains.filter((drain) => drain.citizenReportGroup),
    ],
  };
}

export interface DrainRecord {
  id: string;
  directCleaningReport?: boolean;
  directReportReviewStatus?: "pending" | "verified" | "rejected";
  directReportPhoto?: string;
  directReportDescription?: string;
  directReportReporterUid?: string;
  citizenReportGroup?: boolean;
  sourceReportIds?: string[];
  anchorLatitude?: number;
  anchorLongitude?: number;
  fieldTaskId?: string;
  fieldTaskStatus?: string;
  inspectionOutcome?: "cleaning_required" | "no_cleaning_required" | null;
  evidenceId?: string;
  location: string;
  ward: string;
  reason: string;
  status: DrainStatus;
  priority: number;
  consequence: number;
  catchment: number;
  visibleBlockage?: number;
  evidenceUncertainty?: number;
  condition: string;
  evidenceStatus: string;
  evidencePhoto?: string;
  evidencePhotoPath?: string;
  evidencePhotoLoadError?: string;
  lastObservation: string;
  assignedCrew?: string;
  assignedCrews?: string[];
  workStatus?: string;
  issueType: string;
  mapPosition: [number, number];
  lastUpdated: string;
  deadlineAt?: string;
  assignedShift?: string;
}

export interface ReportRecord {
  id: string;
  drainId: string;
  latitude?: number;
  longitude?: number;
  reporterName: string;
  issueType: string;
  ward: string;
  location: string;
  description: string;
  urgent: boolean;
  photo?: string;
  photoPath?: string;
  photoLoadError?: string;
  submittedAt: string;
  priority: number;
  reasons: string[];
  status: "Open" | "Duplicate" | "Resolved";
  backendStatus?: string;
}

export interface ActivityEntry {
  id: string;
  title: string;
  detail: string;
  timestamp: string;
  severity: ActivitySeverity;
  category?: string;
  reason?: string;
  user?: string;
  evidenceId?: string;
}

export interface OutcomeRecord {
  id: string;
  drainId: string;
  beforeCondition: string;
  afterCondition: string;
  postRainObservation: string;
  outcome: OutcomeType;
  recommendation: string;
  timestamp: string;
}

type CreditPoolStatus =
  | "Pending verification"
  | "Released"
  | "Held"
  | "Reversed";

export interface CreditPolicy {
  baseCleaning: number;
  baseInspection: number;
  complexityMultiplier: number;
  scopeMultiplier: number;
  evidenceMultiplier: number;
  roleWeights: Record<string, number>;
  wardAllowances: Record<string, WardAllowance>;
}

export interface WardAllowance {
  successfulCleaning: number;
  successfulInspection: number;
  incompleteWorkPenalty: number;
  rejectedEvidencePenalty: number;
  delayedWorkPenalty: number;
}

export interface CrewWorker {
  id: string;
  name: string;
  currentCrew: string;
  role: string;
  ward?: string;
  status?: "Active" | "On leave" | "Available";
  joinedAt?: string;
  officialEmail?: string;
  phoneNumber?: string;
  address?: string;
  loginStatus?: "Credentials pending" | "Credentials issued";
}

export interface CrewRecord {
  id: string;
  name: string;
  ward: string;
  memberIds: string[];
  createdAt: string;
}

interface CrewOption {
  name: string;
  label?: string;
  members: string[];
}

function buildCrewOptions(
  crews: CrewRecord[],
  workers: CrewWorker[],
): CrewOption[] {
  return [
    ...crews.map((crew) => ({
      name: crew.name,
      members: crew.memberIds
        .map((id) => workers.find((worker) => worker.id === id)?.name)
        .filter((name): name is string => Boolean(name)),
    })),
    ...workers.map((worker) => ({
      name: worker.id,
      label: `${worker.name} (${worker.id}) · individual`,
      members: [worker.name],
    })),
  ];
}

function getTodayInputDate() {
  const today = new Date();
  const month = String(today.getMonth() + 1).padStart(2, "0");
  const day = String(today.getDate()).padStart(2, "0");
  return `${today.getFullYear()}-${month}-${day}`;
}

export interface CreditPool {
  id: string;
  workOrderId: string;
  drainId: string;
  taskType: "Cleaning" | "Inspection";
  complexity: string;
  completedScope: number;
  evidenceQuality: number;
  proposedCredits: number;
  status: CreditPoolStatus;
  createdAt: string;
  releasedAt?: string;
  deadlineAt?: string;
  completedAt?: string;
  onTime?: boolean;
  reviewer?: string;
  reason: string;
}

export interface CreditAllocation {
  id: string;
  poolId: string;
  workOrderId: string;
  workerId: string;
  workerName: string;
  historicalCrew: string;
  role: string;
  weight: number;
  credits: number;
  timestamp: string;
}

export interface CreditAudit {
  id: string;
  action:
    | "Pool created"
    | "Credits released"
    | "Approval ignored"
    | "Adjustment";
  poolId: string;
  workOrderId: string;
  workerId?: string;
  reviewer: string;
  timestamp: string;
  reason: string;
}

export interface AppState {
  drains: DrainRecord[];
  reports: ReportRecord[];
  activities: ActivityEntry[];
  outcomes: OutcomeRecord[];
  creditPolicy: CreditPolicy;
  workers: CrewWorker[];
  crews: CrewRecord[];
  creditPools: CreditPool[];
  creditAllocations: CreditAllocation[];
  creditAudits: CreditAudit[];
  preferences?: {
    notifications: boolean;
    dailyDigest: boolean;
  };
}

interface ReportForm {
  reporterName: string;
  issueType: string;
  ward: string;
  location: string;
  description: string;
  urgent: boolean;
  photo?: string;
  photoPath?: string;
}

interface InspectionForm {
  drainId: string;
  observedCondition: string;
  estimatedBlockage: number;
  notes: string;
  photo?: string;
  photoPath?: string;
}

const navItems = [
  { label: "Overview", path: "/overview", icon: Gauge },
  { label: "Drain Map", path: "/map", icon: MapPinned },
  { label: "Work Queues", path: "/queues", icon: ClipboardCheck },
  { label: "Work Orders", path: "/work-orders", icon: ClipboardList },
  { label: "Evidence Review", path: "/evidence", icon: ShieldCheck },
  { label: "Drain Intelligence", path: "/monitoring", icon: BrainCircuit },
  { label: "Reports", path: "/reports", icon: Download },
  { label: "Crew Management", path: "/crew-management", icon: Award },
  { label: "Logs", path: "/logs", icon: ClipboardList },
  { label: "Administration", path: "/administration", icon: UsersRound },
];

const createId = (prefix: string) =>
  `${prefix}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;

const formatDate = (value: string) =>
  new Date(value).toLocaleString([], {
    dateStyle: "medium",
    timeStyle: "short",
  });

const getStatusColor = (status: DrainStatus) => {
  switch (status) {
    case "Cleaning Recommended":
    case "Assigned":
      return "bg-red-100 text-red-700 border-red-200";
    case "Inspection Required":
    case "Pending Review":
      return "bg-amber-100 text-amber-700 border-amber-200";
    case "Monitoring":
    case "Resolved":
    case "Reviewed":
      return "bg-emerald-100 text-emerald-700 border-emerald-200";
    case "Rework Required":
      return "bg-rose-100 text-rose-700 border-rose-200";
    default:
      return "bg-slate-100 text-slate-700 border-slate-200";
  }
};

const getOutcomeColor = (outcome: OutcomeType) => {
  switch (outcome) {
    case "Resolved":
      return "bg-emerald-100 text-emerald-700";
    case "Partially Resolved":
      return "bg-amber-100 text-amber-700";
    case "Persisted":
      return "bg-red-100 text-red-700";
    default:
      return "bg-slate-100 text-slate-700";
  }
};

const getPriorityColor = (score: number) => {
  if (score >= 75) return "text-red-600";
  if (score >= 60) return "text-amber-600";
  return "text-emerald-600";
};

type WorkOrderTeam = "Inspection team" | "Cleaning team";

const getWorkOrderTeam = (drain: DrainRecord): WorkOrderTeam => {
  return drain.workStatus?.toLowerCase().startsWith("inspection assigned")
    ? "Inspection team"
    : "Cleaning team";
};

const hasAcceptedEvidence = (drain: DrainRecord) =>
  drain.status === "Resolved" ||
  drain.status === "Reviewed" ||
  /accepted|archived|resolved/i.test(
    `${drain.evidenceStatus} ${drain.workStatus ?? ""}`,
  );

const getMapColor = (status: DrainStatus) => {
  if (
    status === "Cleaning Recommended" ||
    status === "Assigned" ||
    status === "Rework Required"
  )
    return "#ef4444";
  if (status === "Inspection Required" || status === "Pending Review")
    return "#f59e0b";
  if (status === "Monitoring" || status === "Reviewed") return "#10b981";
  return "#0f172a";
};

const buildPriorityReason = (issueType: string, urgent: boolean) => {
  const base = {
    "Blocked Drain": 72,
    "Partial Blockage": 66,
    Waterlogging: 74,
    Overflow: 80,
    "Uncertain Condition": 58,
  } as Record<string, number>;

  const score = Math.min(99, base[issueType] ?? 60 + (urgent ? 12 : 0));
  const reasons = [
    `${issueType} is a live civic asset risk.`,
    urgent
      ? "Urgent status adds an escalation factor."
      : "Routine verification continues on the standard queue.",
    "Priority assessment uses the available incident evidence and requires field validation.",
  ];
  return { score, reasons };
};

interface KmlFeature {
  name: string;
  type: string;
  waterway: string;
  coordinates: [number, number][];
}

function KmlOverlay() {
  const [features, setFeatures] = useState<KmlFeature[]>([]);

  useEffect(() => {
    let active = true;
    fetch("/map.kml")
      .then((response) => {
        if (!response.ok)
          throw new Error(`KML request failed with ${response.status}`);
        return response.text();
      })
      .then((source) => {
        const document = new DOMParser().parseFromString(
          source,
          "application/xml",
        );
        const parsed = Array.from(document.getElementsByTagName("Placemark"))
          .map((placemark) => {
            const value = (tag: string) =>
              placemark.getElementsByTagName(tag)[0]?.textContent?.trim() ?? "";
            const coordinates = value("coordinates")
              .split(/\s+/)
              .map((coordinate) => coordinate.split(",").map(Number))
              .filter(
                (coordinate) =>
                  Number.isFinite(coordinate[0]) &&
                  Number.isFinite(coordinate[1]),
              )
              .map(
                ([longitude, latitude]) =>
                  [latitude, longitude] as [number, number],
              );
            return {
              name: value("name") || "Drainage line",
              type: value("type") || "waterway",
              waterway: value("waterway") || "drainage",
              coordinates,
            };
          })
          .filter((feature) => feature.coordinates.length > 1);
        if (active) setFeatures(parsed);
      })
      .catch((error: unknown) => {
        console.error("Unable to load the drainage KML overlay.", error);
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <>
      {features.map((feature, index) => (
        <Polyline
          key={`${feature.name}-${index}`}
          positions={feature.coordinates}
          pathOptions={{ color: "#215B63", weight: 3, opacity: 0.55 }}
        >
          <MapTooltip sticky>
            <strong>{feature.name}</strong>
            <br />
            {feature.type} · {feature.waterway}
          </MapTooltip>
        </Polyline>
      ))}
    </>
  );
}

function App() {
  return (
    <BrowserRouter>
      <DrainRankApp />
    </BrowserRouter>
  );
}

function DrainRankApp() {
  const navigate = useNavigate();
  const dashboardSession = useContext(DashboardSessionContext);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [appState, setAppState] = useState<AppState>(createEmptyData);
  const appStateRef = useRef(appState);
  const [dataReady, setDataReady] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isRefreshingWorkflow, setIsRefreshingWorkflow] = useState(false);
  const [workflowRefreshError, setWorkflowRefreshError] = useState<
    string | null
  >(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [toast, setToast] = useState<string | null>(null);
  const [submittedReportId, setSubmittedReportId] = useState<string | null>(
    null,
  );
  void submittedReportId;

  useEffect(() => {
    appStateRef.current = appState;
  }, [appState]);

  useEffect(() => {
    let active = true;
    void loadDashboardState()
      .then((state) => {
        if (!active) return;
        setAppState(state);
        setDataReady(true);
      })
      .catch((error: unknown) => {
        if (!active) return;
        setLoadError(String(error));
      });
    return () => {
      active = false;
    };
  }, [reloadToken]);

  useEffect(() => {
    if (!dataReady || !supabase) return;
    const client = supabase;
    let active = true;
    const refresh = async () => {
      if (!active) return;
      setIsRefreshingWorkflow(true);
      try {
        const refreshed = await refreshCitizenWorkflow(appStateRef.current);
        if (!active) return;
        setAppState((current) => mergeRefreshedWorkflow(current, refreshed));
        setWorkflowRefreshError(null);
      } catch (error) {
        if (active) setWorkflowRefreshError(String(error));
      } finally {
        if (active) setIsRefreshingWorkflow(false);
      }
    };
    const channel = client
      .channel("citizen-report-inspection-queue")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "citizen_reports",
        },
        () => void refresh(),
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "direct_cleaning_reports",
        },
        () => void refresh(),
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "field_tasks",
        },
        (payload) => {
          const currentGroup = appStateRef.current.drains.find(
            (drain) =>
              drain.citizenReportGroup &&
              (drain.fieldTaskId ?? drain.id) === payload.new.id,
          );
          if (
            currentGroup &&
            (currentGroup.fieldTaskStatus !== payload.new.status ||
              currentGroup.inspectionOutcome !==
                payload.new.inspection_outcome)
          )
            void refresh();
        },
      )
      .subscribe((status) => {
        if (status === "CHANNEL_ERROR" && active) {
          setWorkflowRefreshError(
            "Live report updates are unavailable. Use Refresh queue to retry.",
          );
        }
      });
    return () => {
      active = false;
      void client.removeChannel(channel);
    };
  }, [dataReady]);

  useEffect(() => {
    if (!dataReady) return;
    const timeout = window.setTimeout(() => {
      setIsSaving(true);
      void saveDashboardState(appState)
        .then(() => setSaveError(null))
        .catch((error: unknown) => setSaveError(String(error)))
        .finally(() => setIsSaving(false));
    }, 350);
    return () => window.clearTimeout(timeout);
  }, [appState, dataReady]);

  useEffect(() => {
    if (!toast) return;
    const timeout = window.setTimeout(() => setToast(null), 2600);
    return () => window.clearTimeout(timeout);
  }, [toast]);

  const handleRefreshWorkers = async () => {
    const refreshedWorkers = await refreshCrewRoster(
      appStateRef.current.workers,
    );
    setAppState((previous) => ({
      ...previous,
      workers: refreshedWorkers,
    }));
  };

  const handleOperationalDataReset = async () => {
    const resetState: AppState = {
      ...createEmptyData(),
    };
    setDataReady(false);
    let result: Awaited<ReturnType<typeof resetOperationalData>>;
    try {
      result = await resetOperationalData(resetState);
    } catch (error) {
      setDataReady(true);
      throw error;
    }

    try {
      const verifiedState = await loadDashboardState();
      appStateRef.current = verifiedState;
      setAppState(verifiedState);
      setLoadError(null);
      setSaveError(null);
      setDataReady(true);

      if (verifiedState.drains.length || verifiedState.reports.length) {
        throw new Error(
          `Reset ran, but ${verifiedState.drains.length} incident(s) and ${verifiedState.reports.length} report(s) remain after reloading Supabase. Check for another client restoring records or verify the reset backend function.`,
        );
      }

      setToast("App data has been reset and verified.");
      return result.photoCleanupError;
    } catch (error) {
      setDataReady(true);
      throw error;
    }
  };

  const handleDirectReportReview = async (
    reportId: string,
    decision: "verify" | "reject",
  ) => {
    if (!supabase) throw new Error("Supabase is not configured.");
    if (
      !window.confirm(
        decision === "verify"
          ? `Verify report ${reportId} and award its ward's cleaning credits?`
          : `Reject direct cleaning report ${reportId}?`,
      )
    ) {
      return;
    }
    try {
      const { data, error } = await supabase.rpc(
        "review_direct_cleaning_report",
        { p_report_id: reportId, p_decision: decision },
      );
      if (error) throw new Error(error.message);
      const refreshedState = await loadDashboardState();
      appStateRef.current = refreshedState;
      setAppState(refreshedState);
      setToast(
        decision === "verify"
          ? `Report verified; ${data} credits awarded.`
          : "Direct cleaning report rejected.",
      );
    } catch (error) {
      setToast(`Could not review direct report: ${error}`);
    }
  };

  const addActivity = (
    title: string,
    detail: string,
    severity: ActivitySeverity = "info",
  ) => {
    setAppState((previous) => ({
      ...previous,
      activities: [
        {
          id: createId("ACT"),
          title,
          detail,
          timestamp: new Date().toISOString(),
          severity,
          reason: "Reason not recorded",
          user: "Current user",
        },
        ...previous.activities,
      ],
    }));
  };

  const updateDrainById = (
    drainId: string,
    nextState: Partial<DrainRecord> | ((previous: DrainRecord) => DrainRecord),
  ) => {
    setAppState((previous) => ({
      ...previous,
      drains: previous.drains.map((drain) => {
        if (drain.id !== drainId) return drain;
        const nextDrain =
          typeof nextState === "function"
            ? nextState(drain)
            : { ...drain, ...nextState };
        return nextDrain;
      }),
    }));
  };

  const submitCitizenReport = (form: ReportForm) => {
    const assessment = buildPriorityReason(form.issueType, form.urgent);
    const reportId = createId("RPT");
    const fullDrainId = `DR-${String(Math.floor(Math.random() * 999 + 1)).padStart(3, "0")}`;
    const syntheticDrain: DrainRecord = {
      id: fullDrainId,
      location:
        form.location || `${form.ward}, ${form.location || "New report area"}`,
      ward: form.ward,
      reason: `${form.issueType} reported in ${form.location || "the ward"} with ${form.urgent ? "urgent civic priority" : "standard review priority"}.`,
      status: form.urgent ? "Cleaning Recommended" : "Monitoring",
      priority: assessment.score,
      consequence: 0.7,
      catchment: 0.8,
      visibleBlockage:
        form.issueType === "Blocked Drain"
          ? 85
          : form.issueType === "Partial Blockage"
            ? 52
            : 35,
      evidenceUncertainty: form.issueType === "Uncertain Condition" ? 1 : 0.4,
      condition:
        form.issueType === "Waterlogging"
          ? "Standing water observed"
          : "New report received",
      evidenceStatus: "Report submitted; awaiting verification",
      lastObservation: new Date().toISOString(),
      issueType: form.issueType,
      mapPosition: [
        28.642 + Math.random() * 0.03,
        77.423 + Math.random() * 0.04,
      ],
      lastUpdated: new Date().toISOString(),
    };

    const report: ReportRecord = {
      id: reportId,
      drainId: fullDrainId,
      reporterName: form.reporterName || "Anonymous citizen",
      issueType: form.issueType,
      ward: form.ward,
      location: form.location,
      description: form.description,
      urgent: form.urgent,
      photo: form.photo,
      photoPath: form.photoPath,
      submittedAt: new Date().toISOString(),
      priority: assessment.score,
      reasons: assessment.reasons,
      status: "Open",
    };

    setAppState((previous) => ({
      ...previous,
      drains: [syntheticDrain, ...previous.drains],
      reports: [report, ...previous.reports],
      activities: [
        {
          id: createId("ACT"),
          title: "Citizen report submitted",
          detail: `${reportId} created for ${form.location}.`,
          timestamp: new Date().toISOString(),
          severity: "info" as const,
        },
        ...previous.activities,
      ],
    }));
    setSubmittedReportId(reportId);
    setToast("New report added to the municipal dashboard.");
    navigate("/report");
  };
  void submitCitizenReport;

  const handleInspectionSubmit = (payload: InspectionForm) => {
    const status: DrainStatus =
      payload.observedCondition === "Visually Clear"
        ? "Monitoring"
        : payload.estimatedBlockage >= 80
          ? "Cleaning Recommended"
          : "Inspection Required";
    updateDrainById(payload.drainId, (drain) => ({
      ...drain,
      status,
      visibleBlockage: payload.estimatedBlockage,
      condition: payload.observedCondition,
      evidenceStatus: "Inspection complete",
      evidencePhoto: payload.photo,
      evidencePhotoPath: payload.photoPath,
      evidencePhotoLoadError: undefined,
      lastObservation: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
      reason: payload.notes || drain.reason,
      workStatus:
        status === "Monitoring"
          ? "Monitoring after inspection"
          : "Awaiting queue update",
    }));
    addActivity(
      "Inspection submitted",
      `EVD-${payload.drainId} · Updated ${payload.drainId} with a ${payload.observedCondition.toLowerCase()} evaluation.`,
      "success",
    );
    setToast("Inspection saved and queue updated.");
  };
  void handleInspectionSubmit;

  const handleCrewAssignment = (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => {
    updateDrainById(drainId, (drain) => ({
      ...drain,
      status: "Pending Review",
      fieldTaskId: drain.citizenReportGroup
        ? citizenCleaningTaskId(drain.id)
        : drain.fieldTaskId,
      assignedCrew: crew,
      assignedCrews: crew
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean),
      evidenceStatus: "Temporary evidence awaiting review",
      workStatus: `Cleaning assigned · evidence pending`,
      fieldTaskStatus: "Pending",
      reason: note || drain.reason,
      deadlineAt: completionTime,
      assignedShift: shift,
      lastUpdated: new Date().toISOString(),
    }));
    addActivity(
      "Crew assignment recorded",
      `EVD-${drainId} · ${crew} assigned to clean ${drainId} for ${completionTime} (${shift}); temporary evidence review created.`,
      "success",
    );
    setToast(`${crew} assigned to ${drainId}.`);
  };

  const handleInspectionAssignment = (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => {
    updateDrainById(drainId, (drain) => ({
      ...drain,
      fieldTaskStatus: "Pending",
      fieldTaskId: drain.citizenReportGroup ? drain.id : drain.fieldTaskId,
      assignedCrew: crew,
      assignedCrews: crew
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean),
      workStatus: `Inspection assigned · ${completionTime}`,
      reason: note || drain.reason,
      deadlineAt: completionTime,
      assignedShift: shift,
      lastUpdated: new Date().toISOString(),
    }));
    setAppState((previous) => ({
      ...previous,
      reports: previous.reports.map((report) =>
        report.drainId === drainId
          ? { ...report, backendStatus: "work_assigned" }
          : report,
      ),
    }));
    addActivity(
      "Inspection crew assigned",
      `EVD-${drainId} · ${crew} assigned to inspect ${drainId} for ${completionTime} (${shift}).`,
      "success",
    );
    setToast(`${crew} assigned to inspect ${drainId}.`);
  };

  const handleEvidenceAction = (
    drainId: string,
    action: "Accept" | "Request Rework" | "Flag Location Mismatch",
    details: string,
  ) => {
    const sourceDrain = appState.drains.find((drain) => drain.id === drainId);
    const now = new Date().toISOString();
    if (sourceDrain && action === "Accept") {
      setAppState((previous) => {
        const existingPool = previous.creditPools.find(
          (pool) => pool.workOrderId === `WO-${drainId}`,
        );
        if (existingPool?.status === "Released") {
          return {
            ...previous,
            creditAudits: [
              {
                id: createId("AUD"),
                action: "Approval ignored",
                poolId: existingPool.id,
                workOrderId: existingPool.workOrderId,
                reviewer: "Current reviewer",
                timestamp: now,
                reason:
                  "Repeated approval did not duplicate a released credit pool.",
              },
              ...previous.creditAudits,
            ],
          };
        }
        const taskType =
          getWorkOrderTeam(sourceDrain) === "Inspection team"
            ? "Inspection"
            : "Cleaning";
        const complexity = sourceDrain.priority >= 80 ? "High" : "Standard";
        const proposedCredits = Math.round(
          (taskType === "Cleaning"
            ? previous.creditPolicy.baseCleaning
            : previous.creditPolicy.baseInspection) *
            (complexity === "High"
              ? 1.3
              : previous.creditPolicy.complexityMultiplier) *
            previous.creditPolicy.scopeMultiplier *
            previous.creditPolicy.evidenceMultiplier,
        );
        const pool: CreditPool = existingPool ?? {
          id: `POOL-${drainId}`,
          workOrderId: `WO-${drainId}`,
          drainId,
          taskType,
          complexity,
          completedScope: 1,
          evidenceQuality: 1,
          proposedCredits,
          status: "Pending verification",
          createdAt: now,
          deadlineAt:
            sourceDrain.deadlineAt ??
            new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
          completedAt: now,
          onTime: !sourceDrain.deadlineAt || now <= sourceDrain.deadlineAt,
          reason: "Credit pool created from completion evidence.",
        };
        const roster = previous.workers.filter(
          (worker) =>
            sourceDrain.assignedCrew
              ?.split(",")
              .map((crew) => crew.trim())
              .some(
                (assignment) =>
                  assignment === worker.currentCrew ||
                  assignment === worker.id,
              ) ?? false,
        );
        const members = roster;
        const totalWeight = members.reduce(
          (sum, worker) =>
            sum + (previous.creditPolicy.roleWeights[worker.role] ?? 1),
          0,
        );
        const allocations: CreditAllocation[] = members.map((worker) => {
          const weight = previous.creditPolicy.roleWeights[worker.role] ?? 1;
          return {
            id: `ALLOC-${pool.id}-${worker.id}`,
            poolId: pool.id,
            workOrderId: pool.workOrderId,
            workerId: worker.id,
            workerName: worker.name,
            historicalCrew: sourceDrain.assignedCrew ?? worker.currentCrew,
            role: worker.role,
            weight,
            credits: Number(
              ((proposedCredits * weight) / totalWeight).toFixed(2),
            ),
            timestamp: now,
          };
        });
        const delayed =
          Boolean(pool.deadlineAt) && now > String(pool.deadlineAt);
        const leader = members.find((worker) =>
          worker.role.toLowerCase().includes("leader"),
        );
        const delayedPenalty =
          previous.creditPolicy.wardAllowances[sourceDrain.ward]
            ?.delayedWorkPenalty ?? 0;
        const leaderPenaltyAllocation =
          delayed && leader && delayedPenalty > 0
            ? [
                {
                  id: `PENALTY-${pool.id}-${leader.id}`,
                  poolId: pool.id,
                  workOrderId: pool.workOrderId,
                  workerId: leader.id,
                  workerName: leader.name,
                  historicalCrew: sourceDrain.assignedCrew ?? leader.currentCrew,
                  role: leader.role,
                  weight: 0,
                  credits: -Math.abs(delayedPenalty),
                  timestamp: now,
                },
              ]
            : [];
        return {
          ...previous,
          creditPools: [
            {
              ...pool,
              status: "Released",
              releasedAt: now,
              reviewer: "Current reviewer",
              reason: details,
            },
            ...previous.creditPools.filter((item) => item.id !== pool.id),
          ],
          creditAllocations: [
            ...allocations,
            ...leaderPenaltyAllocation,
            ...previous.creditAllocations.filter(
              (item) => item.poolId !== pool.id,
            ),
          ],
          creditAudits: [
            {
              id: createId("AUD"),
              action: "Credits released",
              poolId: pool.id,
              workOrderId: pool.workOrderId,
              reviewer: "Current reviewer",
              timestamp: now,
              reason: details,
            },
            ...(leaderPenaltyAllocation.length
              ? [
                  {
                    id: createId("AUD"),
                    action: "Adjustment" as const,
                    poolId: pool.id,
                    workOrderId: pool.workOrderId,
                    reviewer: "Current reviewer",
                    timestamp: now,
                    reason: `Delayed deadline penalty applied only to crew leader ${leaderPenaltyAllocation[0].workerName}.`,
                  },
                ]
              : []),
            ...previous.creditAudits,
          ],
        };
      });
    }
    updateDrainById(drainId, (drain) => {
      if (action === "Accept") {
        return {
          ...drain,
          status: "Resolved",
          evidenceStatus: "Accepted",
          workStatus: "Issue resolved after evidence review",
          lastUpdated: new Date().toISOString(),
        };
      }
      if (action === "Request Rework") {
        setAppState((previous) => ({
          ...previous,
          creditPools: previous.creditPools.map((pool) =>
            pool.drainId === drainId && pool.status !== "Released"
              ? { ...pool, status: "Held", reason: details }
              : pool,
          ),
          creditAudits: [
            ...previous.creditAudits,
            ...previous.creditPools
              .filter((pool) => pool.drainId === drainId)
              .map((pool) => ({
                id: createId("AUD"),
                action: "Adjustment" as const,
                poolId: pool.id,
                workOrderId: pool.workOrderId,
                reviewer: "Current reviewer",
                timestamp: now,
                reason: details,
              })),
          ],
        }));
        return {
          ...drain,
          status: "Cleaning Recommended",
          assignedCrew: undefined,
          evidenceStatus: "Rework required",
          workStatus: "Returned to cleaning queue",
          lastUpdated: new Date().toISOString(),
        };
      }
      return {
        ...drain,
        status: "Pending Review",
        assignedCrew: undefined,
        evidenceStatus: "Location mismatch flagged",
        workStatus: "Returned to field app · location clarification pending",
        lastUpdated: new Date().toISOString(),
      };
    });
    const actionTitle =
      action === "Accept"
        ? "Evidence accepted"
        : action === "Request Rework"
          ? "Rework requested"
          : "Location mismatch flagged";
    addActivity(
      actionTitle,
      `EVD-${drainId} · ${drainId} — ${details}`,
      action === "Accept" ? "success" : "warning",
    );
    setToast(`${actionTitle} for ${drainId}.`);
  };

  const handlePostRainObservation = (payload: {
    drainId: string;
    beforeCondition: string;
    afterCondition: string;
    outcome: OutcomeType;
    recommendation: string;
    postRainObservation: string;
  }) => {
    const newOutcome: OutcomeRecord = {
      id: createId("OUT"),
      drainId: payload.drainId,
      beforeCondition: payload.beforeCondition,
      afterCondition: payload.afterCondition,
      postRainObservation: payload.postRainObservation,
      outcome: payload.outcome,
      recommendation: payload.recommendation,
      timestamp: new Date().toISOString(),
    };

    setAppState((previous) => ({
      ...previous,
      outcomes: [newOutcome, ...previous.outcomes],
      activities: [
        {
          id: createId("ACT"),
          title: "Post-rain outcome added",
          detail: `${payload.drainId} updated with a ${payload.outcome.toLowerCase()} outcome record.`,
          timestamp: new Date().toISOString(),
          severity: "info" as const,
        },
        ...previous.activities,
      ],
    }));
    setToast("Outcome observation saved and dashboard updated.");
  };

  const addWorker = (worker: CrewWorker) => {
    setAppState((previous) => ({
      ...previous,
      workers: [...previous.workers, worker],
      crews: previous.crews.map((crew) =>
        crew.name === worker.currentCrew
          ? { ...crew, memberIds: [...crew.memberIds, worker.id] }
          : crew,
      ),
      creditAudits: [
        {
          id: createId("AUD"),
          action: "Adjustment",
          poolId: "WORKER-REGISTRY",
          workOrderId: "WORKER-REGISTRY",
          workerId: worker.id,
          reviewer: "Current administrator",
          timestamp: new Date().toISOString(),
          reason: `${worker.name} registered to ${worker.currentCrew}.`,
        },
        ...previous.creditAudits,
      ],
    }));
    setToast(`${worker.name} added to ${worker.currentCrew}.`);
  };

  const addCrew = (crew: CrewRecord) => {
    setAppState((previous) => ({
      ...previous,
      crews: [...previous.crews, crew],
      activities: [
        {
          id: createId("ACT"),
          title: "Crew created",
          detail: `${crew.name} created for ${crew.ward}.`,
          timestamp: new Date().toISOString(),
          severity: "success",
          category: "Crew",
          user: "Current administrator",
        },
        ...previous.activities,
      ],
    }));
    setToast(`${crew.name} created.`);
  };

  const assignWorkersToCrew = (crewName: string, workerIds: string[]) => {
    setAppState((previous) => ({
      ...previous,
      workers: previous.workers.map((worker) =>
        workerIds.includes(worker.id)
          ? { ...worker, currentCrew: crewName }
          : worker,
      ),
      crews: previous.crews.map((crew) => ({
        ...crew,
        memberIds: previous.workers
          .filter((worker) =>
            workerIds.includes(worker.id)
              ? crew.name === crewName
              : worker.currentCrew === crew.name &&
                !workerIds.includes(worker.id),
          )
          .map((worker) => worker.id),
      })),
    }));
    setToast(
      `Crew assignments updated for ${workerIds.length} worker${workerIds.length === 1 ? "" : "s"}.`,
    );
  };

  const updateWorker = (workerId: string, changes: Partial<CrewWorker>) => {
    setAppState((previous) => ({
      ...previous,
      workers: previous.workers.map((worker) =>
        worker.id === workerId ? { ...worker, ...changes } : worker,
      ),
    }));
  };

  const resetWorkerPassword = (worker: CrewWorker) => {
    setAppState((previous) => ({
      ...previous,
      activities: [{
        id: createId("ACT"),
        title: "Password reset link sent",
        detail: `A password reset link was sent to ${worker.phoneNumber ?? "the registered phone"} for ${worker.id}.`,
        timestamp: new Date().toISOString(),
        severity: "warning",
        category: "Crew",
        user: "Current administrator",
      }, ...previous.activities],
    }));
    setToast(`Password reset link sent to ${worker.phoneNumber ?? "the registered phone"}.`);
  };

  if (loadError) {
    return (
      <main className="backend-gate">
        <section className="backend-login panel">
          <h1>Could not load dashboard data</h1>
          <p className="backend-error">{loadError}</p>
          <button
            type="button"
            className="btn-primary"
            onClick={() => {
              setDataReady(false);
              setLoadError(null);
              setReloadToken((current) => current + 1);
            }}
          >
            Retry connection
          </button>
        </section>
      </main>
    );
  }
  if (!dataReady) {
    return <main className="backend-gate">Loading municipal records…</main>;
  }

  const totalDrains = appState.drains.length;
  const openIncidents = appState.drains.filter(
    (drain) => drain.status !== "Monitoring" && drain.status !== "Reviewed",
  ).length;
  const cleaningRecommended = appState.drains.filter(
    (drain) =>
      drain.status === "Cleaning Recommended" || drain.status === "Assigned",
  ).length;
  const inspectionRequired = appState.drains.filter(
    (drain) =>
      drain.status === "Inspection Required" ||
      drain.status === "Pending Review",
  ).length;
  const pendingEvidence = appState.drains.filter(
    (drain) => drain.status === "Pending Review",
  ).length;
  const wardOptions = [
    "All",
    ...new Set(appState.drains.map((drain) => drain.ward)),
  ];
  const intelligenceDrains = appState.drains.map(
    ({
      id,
      location,
      ward,
      status,
      priority,
      condition,
      evidenceStatus,
      lastObservation,
      issueType,
      deadlineAt,
      visibleBlockage,
    }) => ({
      id,
      location,
      ward,
      status,
      priority,
      condition,
      evidenceStatus,
      lastObservation,
      issueType,
      deadlineAt,
      visibleBlockage,
    }),
  );
  const intelligenceReports = appState.reports.map(
    ({ drainId, issueType, status, priority, submittedAt }) => ({
      drainId,
      issueType,
      status,
      priority,
      submittedAt,
    }),
  );
  const intelligenceOutcomes = appState.outcomes.map(
    ({ drainId, outcome, recommendation, timestamp }) => ({
      drainId,
      outcome,
      recommendation,
      timestamp,
    }),
  );

  return (
    <div className={`app-shell ${sidebarCollapsed ? "sidebar-collapsed" : ""}`}>
      <aside className="sidebar">
        <div className="brand-panel">
          <img className="brand-logo" src="/logo.png" alt="Swachh Pravah" />
          <div>
            <div className="brand-name">Swachh Pravah</div>
            <div className="brand-subtitle">
              From Citizen Report to Verified Outcome
            </div>
          </div>
        </div>
        <button
          type="button"
          className="sidebar-toggle"
          onClick={() => setSidebarCollapsed((collapsed) => !collapsed)}
          aria-label={sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          {sidebarCollapsed ? (
            <PanelLeftOpen size={18} />
          ) : (
            <PanelLeftClose size={18} />
          )}
        </button>

        <nav className="nav-stack">
          {navItems.map(({ label, path, icon: Icon }) => (
            <NavLink
              key={path}
              to={path}
              className={({ isActive }) =>
                `nav-item ${isActive ? "active" : ""}`
              }
            >
              <Icon size={16} />
              <span className="nav-label">{label}</span>
            </NavLink>
          ))}
        </nav>
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <div>
            <div className="eyebrow">Municipal drainage operations</div>
            <h1>Municipal Drain Intelligence</h1>
          </div>
          <div
            className={`backend-sync-status ${saveError ? "error" : "synced"}`}
            role="status"
          >
            {workflowRefreshError
              ? `Queue refresh failed: ${workflowRefreshError}`
              : saveError
              ? `Save failed: ${saveError}`
              : isSaving
                ? "Saving to Supabase…"
                : "Connected to Supabase"}
            <button
              type="button"
              disabled={isRefreshingWorkflow}
              onClick={() => {
                setIsRefreshingWorkflow(true);
                void refreshCitizenWorkflow(appStateRef.current)
                  .then((refreshed) => {
                    setAppState((current) =>
                      mergeRefreshedWorkflow(current, refreshed),
                    );
                    setWorkflowRefreshError(null);
                  })
                  .catch((error: unknown) =>
                    setWorkflowRefreshError(String(error)),
                  )
                  .finally(() => setIsRefreshingWorkflow(false));
              }}
            >
              {isRefreshingWorkflow ? "Refreshing…" : "Refresh queue"}
            </button>
            {saveError ? (
              <button
                type="button"
                onClick={() => window.location.reload()}
              >
                Reload server data
              </button>
            ) : null}
          </div>
        </header>

        <Routes>
          <Route path="/" element={<Navigate to="/overview" replace />} />

          <Route
            path="/overview"
            element={
              <OverviewPage
                drains={appState.drains}
                reports={appState.reports}
                activities={appState.activities}
                totalDrains={totalDrains}
                openIncidents={openIncidents}
                cleaningRecommended={cleaningRecommended}
                inspectionRequired={inspectionRequired}
                pendingEvidence={pendingEvidence}
                navigate={navigate}
              />
            }
          />

          <Route
            path="/map"
            element={
              <MapPage drains={appState.drains} reports={appState.reports} />
            }
          />

          <Route
            path="/complaints"
            element={<Navigate to="/reports" replace />}
          />
          <Route path="/report" element={<Navigate to="/reports" replace />} />

          <Route
            path="/inspection"
            element={
              <QueueHubPage
                initialTab="inspection"
                drains={appState.drains}
                crewOptions={buildCrewOptions(appState.crews, appState.workers)}
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
                onReviewDirectReport={handleDirectReportReview}
              />
            }
          />

          <Route
            path="/cleaning"
            element={
              <QueueHubPage
                initialTab="cleaning"
                drains={appState.drains}
                crewOptions={buildCrewOptions(appState.crews, appState.workers)}
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
                onReviewDirectReport={handleDirectReportReview}
              />
            }
          />

          <Route
            path="/queues"
            element={
              <QueueHubPage
                initialTab="inspection"
                drains={appState.drains}
                crewOptions={buildCrewOptions(appState.crews, appState.workers)}
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
                onReviewDirectReport={handleDirectReportReview}
              />
            }
          />

          <Route
            path="/work-orders"
            element={<WorkOrdersPage drains={appState.drains} />}
          />

          <Route
            path="/monitoring"
            element={
              <MonitoringIntelligencePage
                drains={intelligenceDrains}
                reports={intelligenceReports}
                outcomes={intelligenceOutcomes}
                onStatusChange={(drainId, status) => {
                  updateDrainById(drainId, {
                    status,
                    lastUpdated: new Date().toISOString(),
                  });
                  addActivity(
                    "Drain status updated",
                    `${drainId} status changed to ${status} from the monitoring intelligence page.`,
                    "info",
                  );
                  setToast(`${drainId} status updated.`);
                }}
              />
            }
          />

          <Route
            path="/evidence"
            element={
              <EvidenceReviewPage
                drains={appState.drains}
                onAction={handleEvidenceAction}
              />
            }
          />

          <Route
            path="/outcomes"
            element={
              <OutcomePage
                drains={appState.drains}
                outcomes={appState.outcomes}
                onAddOutcome={handlePostRainObservation}
              />
            }
          />

          <Route
            path="/reports"
            element={
              <ReportsPage
                reports={appState.reports}
                activities={appState.activities}
                onExportReports={(count) => {
                  addActivity(
                    "Report data exported",
                    `Exported ${count} filtered report${count === 1 ? "" : "s"} to CSV.`,
                    "info",
                  );
                }}
                onExportLog={(count) => {
                  addActivity(
                    "Activity log exported",
                    `Exported ${count} activity log entr${count === 1 ? "y" : "ies"} to CSV.`,
                    "info",
                  );
                }}
                outcomes={appState.outcomes}
                wardOptions={wardOptions}
              />
            }
          />

          <Route
            path="/crew-management"
            element={
              <CrewManagementPage
                workers={appState.workers}
                crews={appState.crews}
                drains={appState.drains}
                onRefreshWorkers={handleRefreshWorkers}
                reports={appState.reports}
                pools={appState.creditPools}
                allocations={appState.creditAllocations}
                policy={appState.creditPolicy}
                onPolicyChange={(creditPolicy) =>
                  setAppState((previous) => ({ ...previous, creditPolicy }))
                }
                onAddWorker={addWorker}
                onUpdateWorker={updateWorker}
                onAssignWorkers={assignWorkersToCrew}
                onResetPassword={resetWorkerPassword}
              />
            }
          />
          <Route
            path="/crew-management/add-worker"
            element={
              <AddWorkerPage crews={appState.crews} onSave={addWorker} />
            }
          />
          <Route
            path="/crew-management/create-crew"
            element={
              <CreateCrewPage
                crews={appState.crews}
                workers={appState.workers}
                onSave={addCrew}
                onAssignWorkers={assignWorkersToCrew}
              />
            }
          />
          <Route
            path="/crew-credits"
            element={<Navigate to="/crew-management" replace />}
          />
          <Route
            path="/logs"
            element={
              <LogsPage
                activities={appState.activities}
                audits={appState.creditAudits}
                workers={appState.workers}
                crews={appState.crews}
              />
            }
          />

          <Route
          path="/administration"
          element={
            <AdministrationPage
              email={dashboardSession?.email ?? "Signed-in administrator"}
              preferences={
                appState.preferences ?? {
                  notifications: true,
                  dailyDigest: true,
                }
              }
              onPreferencesChange={(preferences) =>
                setAppState((previous) => ({ ...previous, preferences }))
              }
              onResetData={handleOperationalDataReset}
            />
          }
          />
          <Route
            path="/settings"
            element={<Navigate to="/administration" replace />}
          />
        </Routes>
      </main>

      <GlobalDrainAssistant
        drains={intelligenceDrains}
        reports={intelligenceReports}
        outcomes={intelligenceOutcomes}
      />
      {toast ? <div className="toast">{toast}</div> : null}
    </div>
  );
}

function MetricCard({
  label,
  value,
  route,
  accent,
  icon: Icon,
  navigate,
}: {
  label: string;
  value: number | string;
  route: string;
  accent: string;
  icon: typeof Gauge;
  navigate: (path: string) => void;
}) {
  return (
    <button
      type="button"
      className={`metric-card ${accent}`}
      onClick={() => navigate(route)}
    >
      <div className="metric-card-top">
        <span className="metric-icon">
          <Icon size={17} />
        </span>
        <div className="metric-label">{label}</div>
      </div>
      <div className="metric-value">{value}</div>
      <div className="metric-link">
        View details <ChevronRight size={14} />
      </div>
    </button>
  );
}

function OverviewPage({
  drains,
  reports,
  activities,
  totalDrains,
  openIncidents,
  cleaningRecommended,
  inspectionRequired,
  pendingEvidence,
  navigate,
}: {
  drains: DrainRecord[];
  reports: ReportRecord[];
  activities: ActivityEntry[];
  totalDrains: number;
  openIncidents: number;
  cleaningRecommended: number;
  inspectionRequired: number;
  pendingEvidence: number;
  navigate: (path: string) => void;
}) {
  const [period, setPeriod] = useState<"day" | "week" | "month">("week");
  const statusDistribution = [
    {
      name: "Cleaning",
      description: "Cleaning recommended or assigned",
      value: drains.filter(
        (drain) =>
          drain.status.includes("Cleaning") || drain.status === "Assigned",
      ).length,
      color: "#124170",
    },
    {
      name: "Inspection",
      description: "Evidence or condition needs review",
      value: drains.filter(
        (drain) =>
          drain.status.includes("Inspection") ||
          drain.status === "Pending Review",
      ).length,
      color: "#D97706",
    },
    {
      name: "Monitoring",
      description: "No active field action required",
      value: drains.filter(
        (drain) => drain.status === "Monitoring" || drain.status === "Reviewed",
      ).length,
      color: "#2F855A",
    },
  ];
  const priorityData = useMemo(() => {
    const now = Date.now();
    const span = period === "day" ? 24 : period === "week" ? 7 : 6;
    const bucketSize =
      period === "day"
        ? 60 * 60 * 1000
        : period === "week"
          ? 24 * 60 * 60 * 1000
          : 7 * 24 * 60 * 60 * 1000;
    const points = Array.from({ length: span }, (_, index) => {
      const start = now - (span - index) * bucketSize;
      const end = start + bucketSize;
      const date = new Date(end);
      const label =
        period === "day"
          ? date.toLocaleTimeString([], { hour: "numeric" })
          : date.toLocaleDateString([], { month: "short", day: "numeric" });
      const matching = drains.filter((drain) => {
        const updatedAt = new Date(drain.lastUpdated).getTime();
        return updatedAt >= start && updatedAt < end;
      });
      return {
        label,
        Critical: matching.filter((drain) => drain.priority >= 75).length,
        "Needs attention": matching.filter(
          (drain) => drain.priority >= 60 && drain.priority < 75,
        ).length,
        Monitoring: matching.filter((drain) => drain.priority < 60).length,
      };
    });
    return points;
  }, [drains, period]);
  const leaderboard = useMemo(
    () =>
      drains
        .map((drain) => ({
          ...drain,
          incidentCount:
            reports.filter(
              (report) =>
                report.drainId === drain.id ||
                report.location === drain.location,
            ).length || 1,
        }))
        .sort(
          (a, b) =>
            b.incidentCount - a.incidentCount || b.priority - a.priority,
        )
        .slice(0, 5),
    [drains, reports],
  );
  return (
    <div className="page-stack">
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <MetricCard
          label="Total Drains"
          value={totalDrains}
          route="/map"
          accent="teal"
          icon={Droplets}
          navigate={navigate}
        />
        <MetricCard
          label="Open Incidents"
          value={openIncidents}
          route="/inspection"
          accent="amber"
          icon={ShieldAlert}
          navigate={navigate}
        />
        <MetricCard
          label="Cleaning Recommended"
          value={cleaningRecommended}
          route="/cleaning"
          accent="red"
          icon={Wrench}
          navigate={navigate}
        />
        <MetricCard
          label="Inspection Required"
          value={inspectionRequired}
          route="/inspection"
          accent="amber"
          icon={ClipboardCheck}
          navigate={navigate}
        />
        <MetricCard
          label="Pending Evidence Reviews"
          value={pendingEvidence}
          route="/evidence"
          accent="slate"
          icon={Eye}
          navigate={navigate}
        />
      </div>

      <div className="analytics-grid">
        <div className="panel analytics-panel priority-panel">
          <div className="panel-header">
            <h2>Priority distribution</h2>
            <div
              className="period-tabs"
              role="tablist"
              aria-label="Priority period"
            >
              {(["day", "week", "month"] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  className={period === option ? "selected" : ""}
                  onClick={() => setPeriod(option)}
                >
                  {option[0].toUpperCase() + option.slice(1)}
                </button>
              ))}
            </div>
          </div>
          <div className="chart-wrap analytics-chart">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={priorityData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#E6EEF0" />
                <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                <YAxis
                  allowDecimals={false}
                  domain={[0, "auto"]}
                  tick={{ fontSize: 11 }}
                />
                <Tooltip
                  formatter={(value, name) => [`${value} incidents`, name]}
                  labelFormatter={(label) => `Recorded ${label}`}
                />
                <Legend />
                <Line
                  type="monotone"
                  dataKey="Critical"
                  stroke="#124170"
                  strokeWidth={2.5}
                  dot={{ r: 3 }}
                />
                <Line
                  type="monotone"
                  dataKey="Needs attention"
                  stroke="#D4A72C"
                  strokeWidth={2.5}
                  dot={{ r: 3 }}
                />
                <Line
                  type="monotone"
                  dataKey="Monitoring"
                  stroke="#67C090"
                  strokeWidth={2.5}
                  dot={{ r: 3 }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="panel analytics-panel status-panel">
          <div className="panel-header">
            <h2>Task status</h2>
            <span className="panel-note">{drains.length} tracked records</span>
          </div>
          <div className="status-chart-row">
            <div className="chart-wrap donut-chart">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={statusDistribution}
                    dataKey="value"
                    nameKey="name"
                    innerRadius={45}
                    outerRadius={72}
                    paddingAngle={4}
                  >
                    {statusDistribution.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value, name) => [`${value} records`, name]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <div className="status-legend">
              {statusDistribution.map((entry) => {
                const percentage = drains.length
                  ? Math.round((entry.value / drains.length) * 100)
                  : 0;
                return (
                  <div className="status-legend-item" key={entry.name}>
                    <span
                      className="legend-swatch"
                      style={{ background: entry.color }}
                    />
                    <div>
                      <strong>{entry.name}</strong>
                      <small>{entry.description}</small>
                      <span>
                        {entry.value} · {percentage}%
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
        <div className="panel analytics-panel leaderboard-panel">
          <div className="panel-header">
            <h2>Problem-area leaderboard</h2>
            <span className="panel-note">Top five by tracked incidents</span>
          </div>
          <div className="leaderboard-list">
            {leaderboard.map((drain, index) => (
              <button
                type="button"
                className="leaderboard-row"
                key={drain.id}
                onClick={() => navigate("/map")}
              >
                <span className={`rank-badge rank-${index + 1}`}>
                  {index + 1}
                </span>
                <span className="leaderboard-location">
                  <strong>{drain.location}</strong>
                  <small>
                    {drain.id} · {drain.condition}
                  </small>
                </span>
                <span className="leaderboard-count">
                  {drain.incidentCount}
                  <small>issues</small>
                </span>
                <span
                  className={`severity-dot ${drain.priority >= 75 ? "high" : drain.priority >= 60 ? "medium" : "low"}`}
                >
                  {drain.priority >= 75
                    ? "High"
                    : drain.priority >= 60
                      ? "Elevated"
                      : "Routine"}
                </span>
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="panel queue-entry-panel">
        <div>
          <h2>Field operations queues</h2>
          <p className="panel-note">
            Review inspections and assign cleaning work from one focused
            workspace.
          </p>
        </div>
        <button
          type="button"
          className="btn-primary"
          onClick={() => navigate("/queues")}
        >
          Open queues <ChevronRight size={15} />
        </button>
      </div>

      <div className="panel map-preview-panel">
        <div className="panel-header">
          <div>
            <h2>Delhi drainage network</h2>
            <span className="panel-note">
              Drainage lines from supplied KML with current field records
            </span>
          </div>
          <button
            type="button"
            className="btn-secondary"
            onClick={() => navigate("/map")}
          >
            Open map <ChevronRight size={14} />
          </button>
        </div>
        <div className="map-container overview-map">
          <MapContainer
            center={[28.643, 77.43]}
            zoom={11}
            scrollWheelZoom={false}
            className="leaflet-map"
          >
            <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
            <KmlOverlay />
            {drains.map((drain) => (
              <CircleMarker
                key={drain.id}
                center={drain.mapPosition}
                radius={drain.status === "Monitoring" ? 7 : 9}
                pathOptions={{
                  color: getMapColor(drain.status),
                  fillColor: getMapColor(drain.status),
                  fillOpacity: 0.85,
                }}
              >
                <MapTooltip>
                  <strong>{drain.id}</strong>
                  <br />
                  {drain.location}
                  <br />
                  {drain.status} · priority {drain.priority.toFixed(0)}
                </MapTooltip>{" "}
                <MapTooltip>
                  <strong>{drain.id}</strong>
                  <br />
                  {drain.location}
                  <br />
                  {drain.status}
                </MapTooltip>
              </CircleMarker>
            ))}
          </MapContainer>
        </div>
      </div>

      <div className="panel activity-panel compact-log">
        <div className="panel-header">
          <div>
            <h2>Change log</h2>
            <span className="panel-note">Recent category count changes</span>
          </div>
          <button
            type="button"
            className="btn-secondary"
            onClick={() => navigate("/reports")}
          >
            View full log <ChevronRight size={14} />
          </button>
        </div>
        <div className="change-log-list">
          {activities.slice(0, 3).map((item) => (
            <div key={item.id} className="change-log-row">
              <span className={`dot ${item.severity}`} />
              <div className="change-log-main">
                <strong>{item.category ?? "Operations"}</strong>
                <span>{item.title}</span>
                <small>
                  {item.reason ?? "Reason not recorded"} ·{" "}
                  {item.user ?? "User not recorded"}
                </small>
              </div>
              <time>{formatDate(item.timestamp)}</time>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function MapPage({
  drains,
  reports,
}: {
  drains: DrainRecord[];
  reports: ReportRecord[];
}) {
  const [selectedId, setSelectedId] = useState<string>("DR-A");
  const [search, setSearch] = useState("");
  const [priorityFilter, setPriorityFilter] = useState("All");
  const [wardFilter, setWardFilter] = useState("All");
  const [showSections, setShowSections] = useState(true);
  if (drains.length === 0) {
    return (
      <div className="map-workspace">
        <div className="map-toolbar panel">
          <div>
            <div className="eyebrow">Spatial operations</div>
            <h2>Drain Map</h2>
            <span className="panel-note">
              Delhi drainage network and section-level issue records
            </span>
          </div>
        </div>
        <div className="map-workspace-grid">
          <div className="panel map-panel">
            <div className="map-container">
              <MapContainer
                center={[28.643, 77.43]}
                zoom={13}
                scrollWheelZoom={false}
                className="leaflet-map"
              >
                <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                <KmlOverlay />
              </MapContainer>
            </div>
          </div>
          <div className="panel map-detail-panel">
            <div className="panel-header">
              <h2>Section details</h2>
            </div>
            <div className="detail-card empty-state">
              <MapPinned size={30} />
              <h3>No drainage sections yet</h3>
              <p>
                The map is ready, but no section records are available to
                display. Add drainage sections to the dashboard to see them
                here.
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  const filteredDrains = drains.filter((drain) => {
    const matchesSearch = `${drain.id} ${drain.location}`
      .toLowerCase()
      .includes(search.toLowerCase());
    const matchesWard = wardFilter === "All" || drain.ward === wardFilter;
    const matchesPriority =
      priorityFilter === "All" ||
      (priorityFilter === "Critical" && drain.priority >= 75) ||
      (priorityFilter === "Needs attention" &&
        drain.priority >= 60 &&
        drain.priority < 75) ||
      (priorityFilter === "Monitoring" && drain.priority < 60);
    return matchesSearch && matchesWard && matchesPriority;
  });
  const selectedDrain =
    drains.find((drain) => drain.id === selectedId) ??
    filteredDrains[0] ??
    drains[0];
  const selectedReports = reports.filter(
    (report) =>
      report.drainId === selectedDrain.id ||
      report.location === selectedDrain.location,
  );
  const facility = /hospital|school|clinic|station/i.test(
    selectedDrain.location,
  )
    ? selectedDrain.location.match(/hospital|school|clinic|station/i)?.[0]
    : null;
  const priorityClass =
    selectedDrain.priority >= 75
      ? "critical"
      : selectedDrain.priority >= 60
        ? "attention"
        : "monitoring";
  const squareIcon = (drain: DrainRecord) => {
    const markerPriority =
      drain.priority >= 75
        ? "critical"
        : drain.priority >= 60
          ? "attention"
          : "monitoring";
    return divIcon({
      className: `drain-section-marker ${markerPriority}`,
      html: `<span>${drain.id}</span>`,
      iconSize: [42, 24],
      iconAnchor: [21, 12],
    });
  };

  return (
    <div className="map-workspace">
      <div className="map-toolbar panel">
        <div>
          <div className="eyebrow">Spatial operations</div>
          <h2>Drain Map</h2>
          <span className="panel-note">
            Delhi drainage network and section-level issue records
          </span>
        </div>
        <div className="map-filters">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search section or location"
            aria-label="Search drain section"
          />
          <select
            value={wardFilter}
            onChange={(event) => setWardFilter(event.target.value)}
          >
            <option>All</option>
            {[...new Set(drains.map((drain) => drain.ward))].map((ward) => (
              <option key={ward}>{ward}</option>
            ))}
          </select>
          <select
            value={priorityFilter}
            onChange={(event) => setPriorityFilter(event.target.value)}
          >
            <option>All</option>
            <option>Critical</option>
            <option>Needs attention</option>
            <option>Monitoring</option>
          </select>
          <button
            type="button"
            className={`filter-toggle ${showSections ? "active" : ""}`}
            onClick={() => setShowSections((visible) => !visible)}
          >
            <MapPinned size={15} /> Sections
          </button>
          <button
            type="button"
            className="btn-secondary"
            onClick={() => {
              setSearch("");
              setWardFilter("All");
              setPriorityFilter("All");
              setShowSections(true);
            }}
          >
            Clear
          </button>
        </div>
      </div>
      <div className="map-workspace-grid">
        <div className="panel map-panel">
          <div className="panel-header">
            <span className="panel-note">
              {filteredDrains.length} of {drains.length} sections visible
            </span>
          </div>
          <div className="map-container">
            <MapContainer
              center={[28.643, 77.43]}
              zoom={13}
              scrollWheelZoom={false}
              className="leaflet-map"
            >
              <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
              <KmlOverlay />
              {showSections &&
                filteredDrains.map((drain) => (
                  <Marker
                    key={drain.id}
                    position={drain.mapPosition}
                    icon={squareIcon(drain)}
                    eventHandlers={{ click: () => setSelectedId(drain.id) }}
                  >
                    <MapTooltip>
                      {drain.id} · {drain.location}
                      <br />
                      Priority {drain.priority.toFixed(0)} · {drain.status}
                    </MapTooltip>
                  </Marker>
                ))}
              {filteredDrains.map((drain) => (
                <CircleMarker
                  key={`point-${drain.id}`}
                  center={drain.mapPosition}
                  radius={5}
                  pathOptions={{
                    color: getMapColor(drain.status),
                    fillColor: getMapColor(drain.status),
                    fillOpacity: 0.95,
                  }}
                >
                  <MapTooltip>
                    {drain.id} · {drain.mapPosition[0].toFixed(5)},{" "}
                    {drain.mapPosition[1].toFixed(5)}
                  </MapTooltip>
                </CircleMarker>
              ))}
            </MapContainer>
          </div>
        </div>

        <div className="panel map-detail-panel">
          <div className="panel-header">
            <h2>Section details</h2>
            <span className="panel-note">{selectedDrain.id}</span>
          </div>
          <div className="detail-card">
            <div className="detail-summary">
              <div>
                <span className="eyebrow">Selected drainage section</span>
                <strong>{selectedDrain.location}</strong>
                <small>
                  {selectedDrain.id} · {selectedDrain.ward}
                </small>
              </div>
              <span
                className={`status-chip ${getStatusColor(selectedDrain.status)}`}
              >
                {selectedDrain.status}
              </span>
            </div>
            <div className="detail-section-label">Section overview</div>
            <div className="map-detail-grid">
              <div>
                <span className="label">Location</span>
                <p>{selectedDrain.location}</p>
              </div>
              <div>
                <span className="label">Coordinates</span>
                <p>
                  {selectedDrain.mapPosition[0].toFixed(5)},{" "}
                  {selectedDrain.mapPosition[1].toFixed(5)}
                </p>
              </div>
              <div>
                <span className="label">Priority</span>
                <p className={getPriorityColor(selectedDrain.priority)}>
                  {selectedDrain.priority.toFixed(2)} ·{" "}
                  {priorityClass === "critical"
                    ? "Critical"
                    : priorityClass === "attention"
                      ? "Needs attention"
                      : "Monitoring"}
                </p>
              </div>
            </div>
            <div className="detail-section-label">Operational context</div>
            <div className="map-detail-grid">
              <div>
                <span className="label">People reporting issue</span>
                <p>
                  {selectedReports.length} linked report
                  {selectedReports.length === 1 ? "" : "s"}
                </p>
              </div>
              <div>
                <span className="label">High-priority facility</span>
                <p>
                  {facility
                    ? `Recorded near ${facility}`
                    : "No high-priority facility recorded"}
                </p>
              </div>
              <div>
                <span className="label">Current condition</span>
                <p>{selectedDrain.condition}</p>
              </div>
              <div>
                <span className="label">Reason / context</span>
                <p>{selectedDrain.reason}</p>
              </div>
              <div>
                <span className="label">Maintenance history</span>
                <p>
                  {selectedDrain.workStatus ??
                    "No maintenance work order recorded"}
                </p>
              </div>
              <div>
                <span className="label">Evidence</span>
                <p>{selectedDrain.evidenceStatus}</p>
              </div>
              <div>
                <span className="label">Last observation</span>
                <p>{formatDate(selectedDrain.lastObservation)}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ReportPage({
  onSubmit,
  submittedReportId,
}: {
  onSubmit: (form: ReportForm) => void;
  submittedReportId: string | null;
}) {
  const [form, setForm] = useState<ReportForm>({
    reporterName: "",
    issueType: "Blocked Drain",
    ward: "Ward 12",
    location: "Hospital Road",
    description: "",
    urgent: false,
  });
  const [photoPreview, setPhotoPreview] = useState<string | undefined>();
  const [photoPath, setPhotoPath] = useState<string | undefined>();
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [photoUploading, setPhotoUploading] = useState(false);

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!form.location || !form.description || !form.ward) {
      window.alert(
        "Please provide the required location, ward, and description fields.",
      );
      return;
    }

    onSubmit({ ...form, photo: photoPreview, photoPath });
    setForm({
      reporterName: "",
      issueType: "Blocked Drain",
      ward: "Ward 12",
      location: "",
      description: "",
      urgent: false,
    });
    setPhotoPreview(undefined);
    setPhotoPath(undefined);
  };

  const handlePhotoUpload = async (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setPhotoUploading(true);
    setPhotoError(null);
    try {
      const uploaded = await uploadDashboardImage(file);
      setPhotoPreview(uploaded.signedUrl);
      setPhotoPath(uploaded.path);
    } catch (error) {
      setPhotoPreview(undefined);
      setPhotoPath(undefined);
      setPhotoError(String(error));
    } finally {
      setPhotoUploading(false);
    }
  };

  if (submittedReportId) {
    return (
      <div className="page-stack narrow">
        <div className="panel success-panel">
          <div className="success-icon">
            <CheckCheck size={28} />
          </div>
          <h2>Citizen report submitted</h2>
          <p>
            Report ID: <strong>{submittedReportId}</strong>
          </p>
          <p className="muted">
            Priority review uses the submitted details and remains subject to
            field validation.
          </p>
          <button
            type="button"
            className="btn-primary"
            onClick={() => (window.location.hash = "#/overview")}
          >
            Return to dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack narrow">
      <div className="panel">
        <div className="panel-header">
          <h2>Report a Problem</h2>
          <button
            type="button"
            className="btn-secondary"
            onClick={() =>
              setForm((previous) => ({
                ...previous,
                ward: "Ward 12",
                location: "Hospital Road",
              }))
            }
          >
            Use saved location
          </button>
        </div>

        <form onSubmit={handleSubmit} className="form-grid">
          <label>
            Reporter name (optional)
            <input
              value={form.reporterName}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  reporterName: event.target.value,
                }))
              }
            />
          </label>

          <label>
            Issue type
            <select
              value={form.issueType}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  issueType: event.target.value,
                }))
              }
            >
              <option>Blocked Drain</option>
              <option>Partial Blockage</option>
              <option>Waterlogging</option>
              <option>Overflow</option>
              <option>Uncertain Condition</option>
            </select>
          </label>

          <label>
            Ward
            <input
              value={form.ward}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  ward: event.target.value,
                }))
              }
            />
          </label>

          <label>
            Location or landmark
            <input
              value={form.location}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  location: event.target.value,
                }))
              }
              required
            />
          </label>

          <label className="full-width">
            Description
            <textarea
              value={form.description}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  description: event.target.value,
                }))
              }
              rows={5}
              required
            />
          </label>

          <label className="full-width">
            Photo upload
            <input type="file" accept="image/*" onChange={handlePhotoUpload} />
          </label>
          {photoUploading ? (
            <p className="full-width">Uploading photo securely…</p>
          ) : null}
          {photoError ? (
            <p className="backend-error full-width">{photoError}</p>
          ) : null}

          {photoPreview ? (
            <div className="photo-preview full-width">
              <img src={photoPreview} alt="Report preview" />
              <p>Image review is completed by the field team.</p>
            </div>
          ) : (
            <div className="evidence-note full-width">
              Attach available evidence for field review.
            </div>
          )}

          <label className="checkbox-row full-width">
            <input
              type="checkbox"
              checked={form.urgent}
              onChange={(event) =>
                setForm((previous) => ({
                  ...previous,
                  urgent: event.target.checked,
                }))
              }
            />
            This problem is urgent
          </label>

          <div className="button-row full-width">
            <button
              type="submit"
              className="btn-primary"
              disabled={photoUploading}
            >
              {photoUploading ? "Uploading photo…" : "Submit report"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function QueueHubPage({
  initialTab,
  drains,
  crewOptions,
  onInspectionAssign,
  onAssign,
  onReviewDirectReport,
}: {
  initialTab: "inspection" | "cleaning";
  drains: DrainRecord[];
  crewOptions: CrewOption[];
  onInspectionAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => void;
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => void;
  onReviewDirectReport: (
    reportId: string,
    decision: "verify" | "reject",
  ) => Promise<void>;
}) {
  const [tab, setTab] = useState<"inspection" | "cleaning">(initialTab);

  return (
    <div className="page-stack queue-workspace">
      <div className="queue-workspace-header">
        <div>
          <div className="eyebrow">Field operations</div>
          <h2>Work queues</h2>
          <p className="panel-note">
            Prioritise inspections, then move confirmed issues into cleaning.
          </p>
        </div>
        <div className="queue-tabs" role="tablist" aria-label="Work queues">
          <button
            type="button"
            className={tab === "inspection" ? "active" : ""}
            onClick={() => setTab("inspection")}
          >
            <ClipboardCheck size={16} /> Inspection{" "}
            <span>
              {
                drains
                  .filter(
                    (drain) =>
                      drain.status === "Inspection Required" ||
                      drain.status === "Pending Review",
                  )
                  .filter(
                    (drain) =>
                      !drain.workStatus?.startsWith("Inspection assigned") &&
                      !drain.workStatus?.startsWith("Cleaning assigned"),
                  ).length
              }
            </span>
          </button>
          <button
            type="button"
            className={tab === "cleaning" ? "active" : ""}
            onClick={() => setTab("cleaning")}
          >
            <Wrench size={16} /> Cleaning{" "}
            <span>
              {
                drains
                  .filter(
                    (drain) =>
                      drain.status === "Cleaning Recommended" ||
                      drain.status === "Assigned" ||
                      drain.status === "Rework Required",
                  )
                  .filter((drain) => !drain.assignedCrew).length
              }
            </span>
          </button>
        </div>
      </div>
      {tab === "inspection" ? (
        <InspectionQueuePage
          drains={drains}
          crewOptions={crewOptions}
          onAssign={onInspectionAssign}
        />
      ) : (
        <CleaningQueuePage
          drains={drains}
          crewOptions={crewOptions}
          onAssign={onAssign}
          onReviewDirectReport={onReviewDirectReport}
        />
      )}
    </div>
  );
}

void ReportPage;

function InspectionQueuePage({
  drains,
  crewOptions,
  onAssign,
}: {
  drains: DrainRecord[];
  crewOptions: CrewOption[];
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => void;
}) {
  const [filterWard, setFilterWard] = useState("All");
  const [filterStatus, setFilterStatus] = useState("All");
  const [search, setSearch] = useState("");
  const [sortMode, setSortMode] = useState<"priority-desc" | "priority-asc">(
    "priority-desc",
  );
  const [assignedDrainId, setAssignedDrainId] = useState<string | null>(null);

  const queue = useMemo(() => {
    return drains
      .filter(
        (drain) =>
          drain.status === "Inspection Required" ||
          drain.status === "Pending Review",
      )
      .filter(
        (drain) =>
          !drain.workStatus?.startsWith("Inspection assigned") &&
          !drain.workStatus?.startsWith("Cleaning assigned"),
      )
      .filter((drain) => filterWard === "All" || drain.ward === filterWard)
      .filter(
        (drain) => filterStatus === "All" || drain.status === filterStatus,
      )
      .filter(
        (drain) =>
          drain.location.toLowerCase().includes(search.toLowerCase()) ||
          drain.id.toLowerCase().includes(search.toLowerCase()),
      )
      .sort((a, b) =>
        sortMode === "priority-desc"
          ? b.priority - a.priority
          : a.priority - b.priority,
      );
  }, [drains, filterWard, filterStatus, search, sortMode]);

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <h2>Inspection queue</h2>
          <span className="panel-note">
            Evidence gaps and uncertain conditions
          </span>
        </div>

        <div className="toolbar queue-filters">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search location or drain ID"
          />
          <select
            value={filterWard}
            onChange={(event) => setFilterWard(event.target.value)}
          >
            <option value="All">All wards</option>
            <option value="Ward 12">Ward 12</option>
          </select>
          <select
            value={filterStatus}
            onChange={(event) => setFilterStatus(event.target.value)}
          >
            <option value="All">All statuses</option>
            <option value="Inspection Required">Inspection Required</option>
            <option value="Pending Review">Pending Review</option>
          </select>
          <select
            value={sortMode}
            onChange={(event) =>
              setSortMode(
                event.target.value as "priority-desc" | "priority-asc",
              )
            }
          >
            <option value="priority-desc">Sort by priority: high to low</option>
            <option value="priority-asc">Sort by priority: low to high</option>
          </select>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Drain ID</th>
                <th>Location</th>
                <th>Reason</th>
                <th>Consequence</th>
                <th>Evidence status</th>
                <th>Priority</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {queue.map((drain) => (
                <tr key={drain.id}>
                  <td>{drain.id}</td>
                  <td>{drain.location}</td>
                  <td>{drain.reason}</td>
                  <td>{drain.consequence.toFixed(2)}</td>
                  <td>{drain.evidenceStatus}</td>
                  <td className={getPriorityColor(drain.priority)}>
                    {drain.priority.toFixed(2)}
                  </td>
                  <td>
                    <button
                      type="button"
                      className="btn-secondary"
                      onClick={() => setAssignedDrainId(drain.id)}
                    >
                      Assign Inspection Crew
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {assignedDrainId ? (
        <AssignCrewModal
          drainId={assignedDrainId}
          crewOptions={crewOptions}
          onClose={() => setAssignedDrainId(null)}
          onAssign={onAssign}
        />
      ) : null}
    </div>
  );
}

function InspectionModal({
  drain,
  onClose,
  onSubmit,
}: {
  drain: DrainRecord;
  onClose: () => void;
  onSubmit: (payload: InspectionForm) => void;
}) {
  const [observedCondition, setObservedCondition] = useState("Visually Clear");
  const [estimatedBlockage, setEstimatedBlockage] = useState<number>(
    drain.visibleBlockage ?? 40,
  );
  const [notes, setNotes] = useState("");
  const [photo, setPhoto] = useState<string | undefined>();
  const [photoPath, setPhotoPath] = useState<string | undefined>();
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [photoUploading, setPhotoUploading] = useState(false);

  const submit = () => {
    if (photoUploading) return;
    onSubmit({
      drainId: drain.id,
      observedCondition,
      estimatedBlockage,
      notes,
      photo,
      photoPath,
    });
  };

  return (
    <div className="modal-backdrop">
      <div className="modal-card wide">
        <div className="panel-header">
          <h2>Start inspection — {drain.id}</h2>
          <button type="button" className="btn-secondary" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="form-grid">
          <label>
            Observed condition
            <select
              value={observedCondition}
              onChange={(event) => setObservedCondition(event.target.value)}
            >
              <option>Visually Clear</option>
              <option>Partial Blockage</option>
              <option>Severe Blockage</option>
              <option>Waterlogging Observed</option>
              <option>Unknown</option>
            </select>
          </label>

          <label>
            Estimated blockage percentage
            <input
              type="number"
              value={estimatedBlockage}
              min={0}
              max={100}
              onChange={(event) =>
                setEstimatedBlockage(Number(event.target.value))
              }
            />
          </label>

          <label className="full-width">
            Notes
            <textarea
              rows={4}
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
            />
          </label>

          <label className="full-width">
            Upload inspection photo
            <input
              type="file"
              accept="image/*"
              onChange={async (event) => {
                const file = event.target.files?.[0];
                if (!file) return;
                setPhotoUploading(true);
                setPhotoError(null);
                try {
                  const uploaded = await uploadDashboardImage(file);
                  setPhoto(uploaded.signedUrl);
                  setPhotoPath(uploaded.path);
                } catch (error) {
                  setPhoto(undefined);
                  setPhotoPath(undefined);
                  setPhotoError(String(error));
                } finally {
                  setPhotoUploading(false);
                }
              }}
            />
          </label>
          {photoUploading ? (
            <p className="full-width">Uploading photo securely…</p>
          ) : null}
          {photoError ? (
            <p className="backend-error full-width">{photoError}</p>
          ) : null}

          <div className="button-row full-width">
            <button
              type="button"
              className="btn-primary"
              onClick={submit}
              disabled={photoUploading}
            >
              {photoUploading ? "Uploading photo…" : "Submit inspection"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

void InspectionModal;

function CleaningQueuePage({
  drains,
  crewOptions,
  onAssign,
  onReviewDirectReport,
}: {
  drains: DrainRecord[];
  crewOptions: CrewOption[];
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => void;
  onReviewDirectReport: (
    reportId: string,
    decision: "verify" | "reject",
  ) => Promise<void>;
}) {
  const [selectedDrainId, setSelectedDrainId] = useState<string | null>(null);
  const [selectedActionDrainId, setSelectedActionDrainId] = useState<
    string | null
  >(null);
  const cleaningDrains = drains
    .filter(
      (drain) =>
        drain.status === "Cleaning Recommended" ||
        drain.status === "Assigned" ||
        drain.status === "Rework Required",
    )
    .filter((drain) => !drain.assignedCrew);
  const selectedActionDrain = cleaningDrains.find(
    (drain) => drain.id === selectedActionDrainId,
  );

  return (
    <div className="page-stack cleaning-queue-page">
      <div className="panel">
        <div className="panel-header">
          <h2>Cleaning queue</h2>
          <span className="panel-note">Recommended cleaning work orders</span>
        </div>

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Drain ID</th>
                <th>Location</th>
                <th>Blockage</th>
                <th>Consequence</th>
                <th>Cleaning score</th>
                <th>Status</th>
                <th>Assigned crew</th>
                <th>Report check</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {cleaningDrains.map((drain) => (
                <tr key={drain.id}>
                  <td>{drain.id}</td>
                  <td>{drain.location}</td>
                  <td>{drain.visibleBlockage ?? 0}%</td>
                  <td>{drain.consequence.toFixed(2)}</td>
                  <td className={getPriorityColor(drain.priority)}>
                    {drain.priority.toFixed(2)}
                  </td>
                  <td>
                    <span
                      className={`status-chip ${getStatusColor(drain.status)}`}
                    >
                      {drain.status}
                    </span>
                  </td>
                  <td>
                    {drain.assignedCrews?.join(", ") ??
                      drain.assignedCrew ??
                      "Unassigned"}
                  </td>
                  <td>
                    {drain.directCleaningReport ? (
                      <span
                        className={`status-chip cleaning-report-status ${
                          drain.directReportReviewStatus === "verified"
                            ? "cleaning-report-status--verified"
                            : drain.directReportReviewStatus === "rejected"
                              ? "cleaning-report-status--rejected"
                              : "cleaning-report-status--pending"
                        }`}
                      >
                        {drain.directReportReviewStatus === "verified"
                          ? "Verified"
                          : drain.directReportReviewStatus === "rejected"
                            ? "Rejected"
                            : "Pending review"}
                      </span>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    <button
                      type="button"
                      className="cleaning-queue-action-button"
                      aria-label={`Actions for ${drain.id}`}
                      onClick={() => setSelectedActionDrainId(drain.id)}
                    >
                      <MoreVertical size={18} aria-hidden="true" />
                      <span>Actions</span>
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {selectedDrainId ? (
        <AssignCrewModal
          drainId={selectedDrainId}
          crewOptions={crewOptions}
          onClose={() => setSelectedDrainId(null)}
          onAssign={onAssign}
        />
      ) : null}
      {selectedActionDrain ? (
        <QueueActionsModal
          drain={selectedActionDrain}
          onClose={() => setSelectedActionDrainId(null)}
          onAssign={() => {
            setSelectedActionDrainId(null);
            setSelectedDrainId(selectedActionDrainId);
          }}
          onReview={onReviewDirectReport}
        />
      ) : null}
    </div>
  );
}

function QueueActionsModal({
  drain,
  onClose,
  onAssign,
  onReview,
}: {
  drain: DrainRecord;
  onClose: () => void;
  onAssign: () => void;
  onReview: (
    reportId: string,
    decision: "verify" | "reject",
  ) => Promise<void>;
}) {
  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, []);

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        className="modal-card queue-actions-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="queue-actions-title"
      >
        <div className="panel-header">
          <div>
            <h2 id="queue-actions-title">Queue actions</h2>
            <span className="panel-note">{drain.id} · {drain.location}</span>
          </div>
          <button type="button" className="btn-secondary" onClick={onClose}>
            Close
          </button>
        </div>
        <div className="queue-actions-modal-buttons">
          {drain.directReportPhoto ? (
            <a
              className="btn-secondary"
              href={drain.directReportPhoto}
              target="_blank"
              rel="noreferrer"
            >
              View report photo
            </a>
          ) : null}
          {drain.directCleaningReport &&
          drain.directReportReviewStatus === "pending" ? (
            <>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => {
                  onClose();
                  void onReview(drain.id, "verify");
                }}
              >
                Verify &amp; award
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => {
                  onClose();
                  void onReview(drain.id, "reject");
                }}
              >
                Reject report
              </button>
            </>
          ) : null}
          <button type="button" className="btn-primary" onClick={onAssign}>
            Assign crew
          </button>
        </div>
      </section>
    </div>
  );
}

function AssignCrewModal({
  drainId,
  crewOptions,
  onClose,
  onAssign,
}: {
  drainId: string;
  crewOptions: CrewOption[];
  onClose: () => void;
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    shift: string,
    note: string,
  ) => void;
}) {
  const [crews, setCrews] = useState<string[]>([]);
  const [crewSearch, setCrewSearch] = useState("");
  const [deadlineDate, setDeadlineDate] = useState("");
  const [deadlineTime, setDeadlineTime] = useState("08:00");
  const [shift, setShift] = useState("Morning");
  const [note, setNote] = useState("");
  const minimumDeadlineDate = getTodayInputDate();
  const matchingCrews = crewOptions.filter((crewOption) =>
    `${crewOption.name} ${crewOption.label ?? ""}`
      .toLowerCase()
      .includes(crewSearch.trim().toLowerCase()),
  );
  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, []);

  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="panel-header">
          <h2>Assign crew — {drainId}</h2>
          <button type="button" className="btn-secondary" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="form-grid">
          <div className="crew-picker-field">
            <span className="form-label">Crews</span>
            <div className="crew-picker">
              <div className="crew-picker-search">
                <Search size={16} aria-hidden="true" />
                <input
                  value={crewSearch}
                  onChange={(event) => setCrewSearch(event.target.value)}
                  placeholder="Search crews"
                  aria-label="Search crews"
                />
              </div>
              <div className="crew-picker-selection">
                {crews.length ? (
                  crews.map((crew) => (
                    <button
                      type="button"
                      className="crew-picker-chip"
                      key={crew}
                      onClick={() =>
                        setCrews((current) =>
                          current.filter((selectedCrew) => selectedCrew !== crew),
                        )
                      }
                      aria-label={`Remove ${crew}`}
                    >
                      {crewOptions.find((option) => option.name === crew)
                        ?.label ?? crew}{" "}
                      <span aria-hidden="true">×</span>
                    </button>
                  ))
                ) : (
                  <span className="crew-picker-empty">No crews selected</span>
                )}
              </div>
              <div className="crew-picker-results" role="listbox" aria-label="Available crews">
                {matchingCrews.length ? (
                  matchingCrews.map((crewOption) => {
                    const selected = crews.includes(crewOption.name);
                    return (
                      <button
                        type="button"
                        className={`crew-picker-option${selected ? " selected" : ""}`}
                        key={crewOption.name}
                        onClick={() =>
                          setCrews((current) =>
                            selected
                              ? current.filter((crew) => crew !== crewOption.name)
                              : [...current, crewOption.name],
                          )
                        }
                        role="option"
                        aria-selected={selected}
                      >
                        <span>
                          <strong>{crewOption.label ?? crewOption.name}</strong>
                          <small>
                            {` · ${crewOption.members.length} ${
                              crewOption.members.length === 1
                                ? "member"
                                : "members"
                            }`}
                          </small>
                        </span>
                        <span>{selected ? "Selected" : "Add"}</span>
                      </button>
                    );
                  })
                ) : (
                  <span className="crew-picker-empty">
                    {crewOptions.length
                      ? "No matching crews"
                      : "No crews are set up. Create a crew in Crew Management first."}
                  </span>
                )}
              </div>
            </div>
          </div>

          <label>
            Deadline date
            <input
              type="date"
              value={deadlineDate}
              min={minimumDeadlineDate}
              onChange={(event) => {
                const nextDate = event.target.value;
                setDeadlineDate(
                  nextDate && nextDate >= minimumDeadlineDate ? nextDate : "",
                );
              }}
              required
            />
          </label>

          <label>
            Deadline time
            <input
              type="time"
              value={deadlineTime}
              onChange={(event) => setDeadlineTime(event.target.value)}
              required
            />
          </label>

          <label>
            Shift
            <select
              value={shift}
              onChange={(event) => {
                const nextShift = event.target.value;
                setShift(nextShift);
                setDeadlineTime(
                  {
                    Morning: "08:00",
                    Afternoon: "14:00",
                    Evening: "18:00",
                    Night: "22:00",
                  }[nextShift] ?? "08:00",
                );
              }}
            >
              <option>Morning</option>
              <option>Afternoon</option>
              <option>Evening</option>
              <option>Night</option>
            </select>
          </label>

          <label className="full-width">
            Optional note
            <textarea
              rows={3}
              value={note}
              onChange={(event) => setNote(event.target.value)}
            />
          </label>

          <div className="button-row full-width">
            <button
              type="button"
              className="btn-primary"
              disabled={
                !crews.length ||
                !deadlineDate ||
                deadlineDate < minimumDeadlineDate
              }
              onClick={() => {
                if (
                  !crews.length ||
                  !deadlineDate ||
                  deadlineDate < minimumDeadlineDate
                ) {
                  return;
                }
                onAssign(
                  drainId,
                  crews.join(", "),
                  new Date(`${deadlineDate}T${deadlineTime}`).toISOString(),
                  shift,
                  note,
                );
                onClose();
              }}
            >
              Save assignment
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function MonitoringPage({
  drains,
  onRecordObservation,
}: {
  drains: DrainRecord[];
  onRecordObservation: (payload: {
    drainId: string;
    beforeCondition: string;
    afterCondition: string;
    outcome: OutcomeType;
    recommendation: string;
    postRainObservation: string;
  }) => void;
}) {
  const [selectedDrainId, setSelectedDrainId] = useState<string | null>(null);
  const monitoringDrains = drains.filter(
    (drain) => drain.status === "Monitoring" || drain.status === "Reviewed",
  );

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <h2>Monitoring</h2>
          <span className="panel-note">
            Latest usable observations show visual clearance
          </span>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Drain ID</th>
                <th>Last inspection date</th>
                <th>Evidence status</th>
                <th>Previous issue</th>
                <th>Status</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {monitoringDrains.map((drain) => (
                <tr key={drain.id}>
                  <td>{drain.id}</td>
                  <td>{formatDate(drain.lastObservation)}</td>
                  <td>{drain.evidenceStatus}</td>
                  <td>{drain.reason}</td>
                  <td>
                    <span
                      className={`status-chip ${getStatusColor(drain.status)}`}
                    >
                      {drain.status}
                    </span>
                  </td>
                  <td>
                    <button
                      type="button"
                      className="btn-secondary"
                      onClick={() => setSelectedDrainId(drain.id)}
                    >
                      Record New Observation
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {selectedDrainId ? (
        <ObservationModal
          drainId={selectedDrainId}
          onClose={() => setSelectedDrainId(null)}
          onSave={onRecordObservation}
        />
      ) : null}
    </div>
  );
}

void MonitoringPage;

function ObservationModal({
  drainId,
  onClose,
  onSave,
}: {
  drainId: string;
  onClose: () => void;
  onSave: (payload: {
    drainId: string;
    beforeCondition: string;
    afterCondition: string;
    outcome: OutcomeType;
    recommendation: string;
    postRainObservation: string;
  }) => void;
}) {
  const [beforeCondition, setBeforeCondition] = useState(
    "Clear after maintenance",
  );
  const [afterCondition, setAfterCondition] = useState("No visible blockage");
  const [outcome, setOutcome] = useState<OutcomeType>("Resolved");
  const [recommendation, setRecommendation] = useState(
    "Continue routine checks.",
  );
  const [postRainObservation, setPostRainObservation] = useState(
    "Waterlogging reduced after rainfall.",
  );

  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="panel-header">
          <h2>Record observation — {drainId}</h2>
          <button type="button" className="btn-secondary" onClick={onClose}>
            Close
          </button>
        </div>

        <div className="form-grid">
          <label>
            Before condition
            <input
              value={beforeCondition}
              onChange={(event) => setBeforeCondition(event.target.value)}
            />
          </label>
          <label>
            After condition
            <input
              value={afterCondition}
              onChange={(event) => setAfterCondition(event.target.value)}
            />
          </label>
          <label>
            Outcome category
            <select
              value={outcome}
              onChange={(event) =>
                setOutcome(event.target.value as OutcomeType)
              }
            >
              <option>Resolved</option>
              <option>Partially Resolved</option>
              <option>Persisted</option>
              <option>Not Observed</option>
            </select>
          </label>
          <label className="full-width">
            Post-rain observation
            <textarea
              rows={3}
              value={postRainObservation}
              onChange={(event) => setPostRainObservation(event.target.value)}
            />
          </label>
          <label className="full-width">
            Recommendation
            <textarea
              rows={3}
              value={recommendation}
              onChange={(event) => setRecommendation(event.target.value)}
            />
          </label>
          <div className="button-row full-width">
            <button
              type="button"
              className="btn-primary"
              onClick={() => {
                onSave({
                  drainId,
                  beforeCondition,
                  afterCondition,
                  outcome,
                  recommendation,
                  postRainObservation,
                });
                onClose();
              }}
            >
              Save observation
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

type FieldEvidenceRecord = {
  id: string;
  taskId: string;
  taskTitle: string;
  location: string;
  dateKey: string;
  deadline: string | null;
  submittedByUid: string;
  description: string;
  cleaningOutcome: string | null;
  photoUrl?: string;
  photoError?: string;
  photoPath: string;
  capturedAt: string;
  submittedAt: string;
  latitude: number;
  longitude: number;
  accuracyMeters: number | null;
  address: string | null;
  reviewStatus: string;
  reviewNote: string | null;
};

async function loadFieldEvidence(): Promise<FieldEvidenceRecord[]> {
  if (!supabase) throw new Error("Supabase is not configured.");
  const client = supabase;
  const { data: updateRows, error: updateError } = await client
    .from("field_work_updates")
    .select(
      "id,task_id,submitted_by_uid,description,photo_path,captured_at,submitted_at,latitude,longitude,accuracy_meters,address,cleaning_outcome,review_status,review_note",
    )
    .eq("review_status", "pending")
    .not("cleaning_outcome", "is", null)
    .order("submitted_at", { ascending: false });
  if (updateError) {
    throw new Error(
      `Could not load field evidence. Apply migration 202610240004_citizen_upload_and_field_evidence_review.sql: ${updateError.message}`,
    );
  }
  if (!updateRows.length) return [];

  const taskIds = [...new Set(updateRows.map((row) => row.task_id))];
  const { data: taskRows, error: taskError } = await client
    .from("field_tasks")
    .select("id,title,location,date_key,work_window_end")
    .in("id", taskIds);
  if (taskError) {
    throw new Error(`Could not load field task details: ${taskError.message}`);
  }
  const tasksById = new Map(taskRows.map((task) => [task.id, task]));

  return Promise.all(
    updateRows.map(async (row) => {
      const { data: photo, error: photoError } = await client.storage
        .from("work-photos")
        .createSignedUrl(row.photo_path, 3600);
      const task = tasksById.get(row.task_id);
      return {
        id: row.id,
        taskId: row.task_id,
        taskTitle: task?.title ?? "Assigned field task",
        location: task?.location ?? "Location not recorded",
        dateKey: task?.date_key ?? "",
        deadline: task?.work_window_end ?? null,
        submittedByUid: row.submitted_by_uid,
        description: row.description,
        cleaningOutcome: row.cleaning_outcome,
        photoUrl: photoError ? undefined : photo?.signedUrl,
        photoError: photoError?.message,
        photoPath: row.photo_path,
        capturedAt: row.captured_at,
        submittedAt: row.submitted_at,
        latitude: row.latitude,
        longitude: row.longitude,
        accuracyMeters: row.accuracy_meters,
        address: row.address,
        reviewStatus: row.review_status,
        reviewNote: row.review_note,
      };
    }),
  );
}

function FieldEvidenceQueue() {
  const [records, setRecords] = useState<FieldEvidenceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reviewingId, setReviewingId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const refresh = async () => {
      try {
        const nextRecords = await loadFieldEvidence();
        if (active) {
          setRecords(nextRecords);
          setError(null);
        }
      } catch (loadError) {
        if (active) setError(String(loadError));
      } finally {
        if (active) setLoading(false);
      }
    };
    void refresh();
    const channel = supabase
      ?.channel("field-evidence-review-queue")
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "field_work_updates",
        },
        () => void refresh(),
      )
      .subscribe();
    return () => {
      active = false;
      if (channel) void supabase?.removeChannel(channel);
    };
  }, []);

  const review = async (
    record: FieldEvidenceRecord,
    decision: "accept" | "request_rework" | "flag_location_mismatch",
  ) => {
    if (!supabase) {
      setError("Supabase is not configured.");
      return;
    }
    const labels = {
      accept: "accept this cleaning evidence and grant 10 credits",
      request_rework: "request rework for this task",
      flag_location_mismatch: "flag the photo location for review",
    };
    if (!window.confirm(`Are you sure you want to ${labels[decision]}?`)) {
      return;
    }
    setReviewingId(record.id);
    setError(null);
    try {
      const { error: reviewError } = await supabase.rpc(
        "review_field_work_update",
        {
          p_update_id: record.id,
          p_decision: decision,
          p_review_note:
            decision === "accept" ? "Accepted after evidence review." : labels[decision],
        },
      );
      if (reviewError) throw reviewError;
      setRecords(await loadFieldEvidence());
    } catch (reviewError) {
      const details =
        reviewError !== null && typeof reviewError === "object"
          ? (reviewError as {
              message?: unknown;
              code?: unknown;
              details?: unknown;
              hint?: unknown;
            })
          : null;
      const errorMessage =
        details && typeof details.message === "string"
          ? details.message
          : reviewError instanceof Error
            ? reviewError.message
            : String(reviewError);
      const errorCode =
        details && typeof details.code === "string"
          ? ` (${details.code})`
          : "";
      const errorDetails =
        details && typeof details.details === "string"
          ? ` Details: ${details.details}`
          : "";
      const errorHint =
        details && typeof details.hint === "string"
          ? ` Hint: ${details.hint}`
          : "";
      setError(
        `Could not review field evidence: ${errorMessage}${errorCode}${errorDetails}${errorHint}`,
      );
    } finally {
      setReviewingId(null);
    }
  };

  const pending = records;
  return (
    <section className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Field app cleaning evidence</h2>
            <span className="panel-note">
              {pending.length} submission{pending.length === 1 ? "" : "s"} awaiting review
            </span>
          </div>
          <button
            type="button"
            className="btn-secondary"
            disabled={loading}
            onClick={() => {
              setLoading(true);
              void loadFieldEvidence()
                .then((nextRecords) => {
                  setRecords(nextRecords);
                  setError(null);
                })
                .catch((loadError: unknown) => setError(String(loadError)))
                .finally(() => setLoading(false));
            }}
          >
            Refresh evidence
          </button>
        </div>
        {error && <p role="alert">{error}</p>}
        {loading && <p>Loading field evidence…</p>}
        {!loading && !error && pending.length === 0 && (
          <p>No field app submissions are waiting for review.</p>
        )}
        {pending.map((record) => (
          <article key={record.id} className="panel evidence-card">
            <div className="panel-header">
              <div>
                <h3>{record.taskTitle}</h3>
                <span className="panel-note">
                  {record.taskId} · {record.location}
                </span>
              </div>
              <span className="status-chip warning">Pending Review</span>
            </div>
            <div className="evidence-grid">
              {record.photoUrl ? (
                <img
                  className="evidence-image"
                  src={record.photoUrl}
                  alt={`Cleaning evidence for ${record.taskTitle}`}
                />
              ) : (
                <p className="panel-note" role="alert">
                  {record.photoError
                    ? `Photo unavailable: ${record.photoError}`
                    : "Photo unavailable"}
                </p>
              )}
              <div className="evidence-meta-list">
                <div>
                  <span>Cleaning result</span>
                  <strong>
                    {(record.cleaningOutcome ?? "Not specified")
                      .replaceAll("_", " ")
                      .replace(/\b\w/g, (character) => character.toUpperCase())}
                  </strong>
                </div>
                <div>
                  <span>Work notes</span>
                  <strong>{record.description}</strong>
                </div>
                <div>
                  <span>Photo address</span>
                  <strong>{record.address ?? "Address unavailable"}</strong>
                </div>
                <div>
                  <span>GPS coordinates</span>
                  <strong>
                    {record.latitude.toFixed(6)}, {record.longitude.toFixed(6)}
                    {record.accuracyMeters == null
                      ? ""
                      : ` · ±${record.accuracyMeters.toFixed(1)} m`}
                  </strong>
                </div>
                <div>
                  <span>Captured / submitted</span>
                  <strong>
                    {formatDate(record.capturedAt)} / {formatDate(record.submittedAt)}
                  </strong>
                </div>
                <div>
                  <span>Deadline</span>
                  <strong>
                    {record.deadline
                      ? formatDate(record.deadline)
                      : record.dateKey || "Not specified"}
                  </strong>
                </div>
              </div>
            </div>
            <div className="button-row">
              <button
                type="button"
                className="btn-primary"
                disabled={reviewingId === record.id}
                onClick={() => void review(record, "accept")}
              >
                Accept evidence (+10 credits)
              </button>
              <button
                type="button"
                className="btn-secondary"
                disabled={reviewingId === record.id}
                onClick={() => void review(record, "request_rework")}
              >
                Request rework
              </button>
              <button
                type="button"
                className="btn-secondary alt"
                disabled={reviewingId === record.id}
                onClick={() => void review(record, "flag_location_mismatch")}
              >
                Flag location
              </button>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function EvidenceReviewPage(_props: {
  drains: DrainRecord[];
  onAction: (
    drainId: string,
    action: "Accept" | "Request Rework" | "Flag Location Mismatch",
    details: string,
  ) => void;
}) {
  return (
    <div className="page-stack evidence-review-page">
      <FieldEvidenceQueue />
    </div>
  );
}

function OutcomePage({
  drains,
  outcomes,
  onAddOutcome,
}: {
  drains: DrainRecord[];
  outcomes: OutcomeRecord[];
  onAddOutcome: (payload: {
    drainId: string;
    beforeCondition: string;
    afterCondition: string;
    outcome: OutcomeType;
    recommendation: string;
    postRainObservation: string;
  }) => void;
}) {
  const [selectedDrainId, setSelectedDrainId] = useState("DR-A");

  return (
    <div className="page-stack">
      <div className="cards-grid two-col">
        {outcomes.map((outcome) => {
          const drain =
            drains.find((item) => item.id === outcome.drainId) ?? drains[0];
          return (
            <div key={outcome.id} className="panel outcome-card">
              <div className="panel-header">
                <h2>{outcome.drainId}</h2>
                <span
                  className={`status-chip ${getOutcomeColor(outcome.outcome)}`}
                >
                  {outcome.outcome}
                </span>
              </div>
              <div className="outcome-grid">
                <div>
                  <span>Before</span>
                  <p>{outcome.beforeCondition}</p>
                </div>
                <div>
                  <span>After</span>
                  <p>{outcome.afterCondition}</p>
                </div>
                <div>
                  <span>Post-rain</span>
                  <p>{outcome.postRainObservation}</p>
                </div>
                <div>
                  <span>Recommendation</span>
                  <p>{outcome.recommendation}</p>
                </div>
              </div>
              <div className="muted small">{drain.location}</div>
            </div>
          );
        })}
      </div>

      <div className="panel">
        <div className="panel-header">
          <h2>Add post-rain observation</h2>
          <span className="panel-note">
            Observed outcomes are not proof of causality
          </span>
        </div>
        <div className="form-grid">
          <label>
            Drain ID
            <select
              value={selectedDrainId}
              onChange={(event) => setSelectedDrainId(event.target.value)}
            >
              {drains.map((drain) => (
                <option key={drain.id} value={drain.id}>
                  {drain.id}
                </option>
              ))}
            </select>
          </label>
        </div>
        <div className="button-row">
          <button
            type="button"
            className="btn-primary"
            onClick={() =>
              onAddOutcome({
                drainId: selectedDrainId,
                beforeCondition:
                  "Maintenance was completed and the drain was reviewed.",
                afterCondition: "Current state observed after rainfall.",
                outcome: "Partially Resolved",
                recommendation:
                  "Continue monitoring and inspect downstream assets.",
                postRainObservation:
                  "Water level remains elevated after the last rainfall event.",
              })
            }
          >
            Add observation
          </button>
        </div>
      </div>
    </div>
  );
}

function ComplaintsPage({
  reports,
  drains,
}: {
  reports: ReportRecord[];
  drains: DrainRecord[];
}) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("All");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const filteredReports = reports.filter((report) => {
    const matchesSearch =
      `${report.id} ${report.location} ${report.issueType} ${report.drainId}`
        .toLowerCase()
        .includes(search.toLowerCase());
    return matchesSearch && (status === "All" || report.status === status);
  });
  const selectedReport = reports.find((report) => report.id === selectedId);
  const selectedDrain = selectedReport
    ? drains.find((drain) => drain.id === selectedReport.drainId)
    : undefined;

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Complaints &amp; incidents</h2>
            <p className="panel-note">
              Review incoming reports, group duplicates, and decide the next
              operational action.
            </p>
          </div>
          <span className="panel-note">Submitted reports</span>
        </div>
        <div className="toolbar">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search report, location, issue, or drain ID"
          />
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value)}
          >
            <option>All</option>
            <option>Open</option>
            <option>Duplicate</option>
            <option>Resolved</option>
          </select>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Report / drain</th>
                <th>Issue and location</th>
                <th>Received</th>
                <th>Urgency</th>
                <th>Evidence</th>
                <th>Status</th>
                <th>Next action</th>
              </tr>
            </thead>
            <tbody>
              {filteredReports.map((report) => (
                <tr key={report.id}>
                  <td>
                    <strong>{report.id}</strong>
                    <br />
                    <span className="muted">{report.drainId}</span>
                  </td>
                  <td>
                    {report.issueType}
                    <br />
                    <span className="muted">{report.location}</span>
                  </td>
                  <td>{formatDate(report.submittedAt)}</td>
                  <td>
                    {report.urgent ? (
                      <span className="status-chip bg-red-100 text-red-700 border-red-200">
                        Urgent
                      </span>
                    ) : (
                      "Standard"
                    )}
                  </td>
                  <td>
                    {report.photo ? "Photo attached" : "Description only"}
                  </td>
                  <td>{report.status}</td>
                  <td>
                    <button
                      type="button"
                      className="btn-secondary"
                      onClick={() => setSelectedId(report.id)}
                    >
                      Review
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {filteredReports.length === 0 ? (
            <div className="empty-state">
              <Search size={24} />
              <h2>No matching reports</h2>
              <p className="muted">Try a different search or status filter.</p>
            </div>
          ) : null}
        </div>
      </div>
      {selectedReport ? (
        <div className="panel">
          <div className="panel-header">
            <h2>Report review — {selectedReport.id}</h2>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => setSelectedId(null)}
            >
              Close
            </button>
          </div>
          <div className="outcome-grid">
            <div>
              <span>Report description</span>
              <p>{selectedReport.description}</p>
            </div>
            <div>
              <span>Linked asset</span>
              <p>
                {selectedDrain
                  ? `${selectedDrain.id} · ${selectedDrain.location}`
                  : "No matching drain record"}
              </p>
            </div>
            <div>
              <span>Priority context</span>
              <p>{selectedReport.reasons.join(" · ")}</p>
            </div>
            <div>
              <span>Human decision</span>
              <p>
                Complaint volume is supporting context; authorised staff should
                confirm the operational action.
              </p>
            </div>
          </div>
          <div className="button-row">
            <button
              type="button"
              className="btn-primary"
              onClick={() =>
                window.alert(
                  `Inspection recommendation recorded for ${selectedReport.id}.`,
                )
              }
            >
              Recommend inspection
            </button>
            <button
              type="button"
              className="btn-secondary"
              onClick={() =>
                window.alert(
                  `Duplicate review opened for ${selectedReport.id}.`,
                )
              }
            >
              Mark possible duplicate
            </button>
            <button
              type="button"
              className="btn-secondary"
              onClick={() =>
                window.alert(`Triage note opened for ${selectedReport.id}.`)
              }
            >
              Add triage note
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

void ComplaintsPage;

function WorkOrdersPage({ drains }: { drains: DrainRecord[] }) {
  const navigate = useNavigate();
  const [status, setStatus] = useState("All Work Orders");
  const [teamSearch, setTeamSearch] = useState("");
  const [search, setSearch] = useState("");
  const workOrders = drains.filter(
    (drain) =>
      drain.assignedCrew &&
      !hasAcceptedEvidence(drain) &&
      (drain.workStatus?.toLowerCase().includes("assigned") === true ||
        drain.status === "Assigned" ||
        drain.status === "Pending Review" ||
        drain.status === "Rework Required"),
  );
  const assignedTeams = [
    ...new Set(
      workOrders
        .map((drain) => drain.assignedCrew)
        .filter((crew): crew is string => Boolean(crew)),
    ),
  ].sort((first, second) => first.localeCompare(second));
  const normalizedTeamSearch = teamSearch.trim().toLowerCase();
  const matchingTeams = assignedTeams.filter((assignedTeam) =>
    assignedTeam.toLowerCase().includes(normalizedTeamSearch),
  );
  const teamWorkload = workOrders.filter(
    (drain) =>
      !normalizedTeamSearch ||
      drain.assignedCrew?.toLowerCase().includes(normalizedTeamSearch),
  ).length;
  const filtered = workOrders.filter((drain) => {
    const haystack =
      `${drain.id} ${drain.location} ${drain.issueType} ${drain.assignedCrew ?? ""}`.toLowerCase();
    if (search && !haystack.includes(search.toLowerCase())) return false;
    if (
      normalizedTeamSearch &&
      !drain.assignedCrew?.toLowerCase().includes(normalizedTeamSearch)
    )
      return false;
    if (status === "All Work Orders") return true;
    if (status === "Inspection")
      return getWorkOrderTeam(drain) === "Inspection team";
    if (status === "Cleaning")
      return getWorkOrderTeam(drain) === "Cleaning team";
    if (status === "In Progress")
      return (
        drain.status === "Assigned" ||
        drain.workStatus?.toLowerCase().includes("progress") === true
      );
    if (status === "Monitoring and Follow-up")
      return drain.status === "Monitoring" || drain.status === "Reviewed";
    if (status === "Awaiting Evidence Review")
      return drain.status === "Pending Review";
    if (status === "Rework Required") return drain.status === "Rework Required";
    return false;
  });

  return (
    <div className="page-stack work-orders-page">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Work orders</h2>
            <p className="panel-note">
              Assignment and completion lifecycle for field operations.
            </p>
          </div>
        </div>
        <div className="toolbar work-orders-filters">
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search work order, drain, ward, or crew"
          />
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value)}
          >
            <option>All Work Orders</option>
            <option>Inspection</option>
            <option>Cleaning</option>
            <option>In Progress</option>
            <option>Awaiting Evidence Review</option>
            <option>Rework Required</option>
          </select>
          <input
            value={teamSearch}
            onChange={(event) => setTeamSearch(event.target.value)}
            placeholder="Search assigned team"
            aria-label="Search assigned team"
          />
          <button
            type="button"
            className="btn-primary"
            onClick={() => navigate("/queues")}
          >
            Open queues
          </button>
        </div>
        <div className="work-orders-workload">
          <strong>
            {normalizedTeamSearch
              ? `${teamWorkload} active task${teamWorkload === 1 ? "" : "s"}`
              : `${workOrders.length} active assigned task${workOrders.length === 1 ? "" : "s"}`}
          </strong>
          <span>
            {normalizedTeamSearch
              ? `${matchingTeams.length} matching team${matchingTeams.length === 1 ? "" : "s"}`
              : `${assignedTeams.length} assigned teams`}
          </span>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Work order</th>
                <th>Drain / task</th>
                <th>Priority</th>
                <th>Team</th>
                <th>Crew</th>
                <th>Status</th>
                <th>Last updated</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((drain) => (
                <tr key={drain.id}>
                  <td>
                    <strong>WO-{drain.id}</strong>
                    <br />
                    <span className="muted">{drain.issueType}</span>
                  </td>
                  <td>
                    {drain.id}
                    <br />
                    <span className="muted">{drain.location}</span>
                  </td>
                  <td className={getPriorityColor(drain.priority)}>
                    {drain.priority.toFixed(2)}
                  </td>
                  <td>{getWorkOrderTeam(drain)}</td>
                  <td>
                    {drain.assignedCrews?.join(", ") ??
                      drain.assignedCrew ??
                      "Unassigned"}
                  </td>
                  <td>
                    <span
                      className={`status-chip ${getStatusColor(drain.status)}`}
                    >
                      {drain.workStatus ?? drain.status}
                    </span>
                  </td>
                  <td>{formatDate(drain.lastUpdated)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length === 0 ? (
            <div className="empty-state">
              <ClipboardList size={24} />
              <h2>No matching work orders</h2>
              <p className="muted">Create one from a queue item or incident.</p>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function ReportsPage({
  reports,
  activities,
  onExportReports,
  onExportLog,
  wardOptions,
}: {
  reports: ReportRecord[];
  activities: ActivityEntry[];
  onExportReports: (count: number) => void;
  onExportLog: (count: number) => void;
  outcomes?: OutcomeRecord[];
  wardOptions: string[];
}) {
  const navigate = useNavigate();
  const [wardFilter, setWardFilter] = useState("All");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const toCsvValue = (value: string | number) =>
    `"${String(value).replaceAll('"', '""')}"`;

  const filteredReports = reports.filter((report) => {
    if (wardFilter !== "All" && report.ward !== wardFilter) return false;
    if (startDate && new Date(report.submittedAt) < new Date(startDate))
      return false;
    if (endDate && new Date(report.submittedAt) > new Date(endDate))
      return false;
    return true;
  });

  const exportCsv = () => {
    const rows = [
      [
        "Drain ID",
        "Reporter",
        "Issue Type",
        "Ward",
        "Location",
        "Priority",
        "Submitted At",
      ],
      ...filteredReports.map((report) => [
        report.drainId,
        report.reporterName,
        report.issueType,
        report.ward,
        report.location,
        report.priority,
        report.submittedAt,
      ]),
    ];
    const csv = rows.map((row) => row.map(toCsvValue).join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "drainrank-reports.csv";
    link.click();
    URL.revokeObjectURL(url);
    onExportReports(filteredReports.length);
  };

  const exportLogCsv = () => {
    const rows = [
      ["Timestamp", "Action", "Details", "Status", "Reason", "User"],
      ...filteredActivities.map((activity) => [
        activity.timestamp,
        activity.title,
        activity.detail,
        activity.severity,
        activity.reason ?? "Reason not recorded",
        activity.user ?? "User not recorded",
      ]),
    ];
    const csv = rows.map((row) => row.map(toCsvValue).join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "drainrank-activity-log.csv";
    link.click();
    URL.revokeObjectURL(url);
    onExportLog(filteredActivities.length);
  };

  const issueTypeCounts = [
    ["Blocked Drain", "#0F766E"],
    ["Partial Blockage", "#D97706"],
    ["Waterlogging", "#2563EB"],
    ["Overflow", "#DC2626"],
    ["Uncertain Condition", "#7C3AED"],
  ].map(([issueType, color]) => ({
    name: issueType,
    value: filteredReports.filter((report) => report.issueType === issueType)
      .length,
    color,
  }));
  const reportStatusCounts = [
    ["Open", "#2563EB"],
    ["Duplicate", "#D97706"],
    ["Resolved", "#16A34A"],
  ].map(([status, color]) => ({
    name: status,
    value: filteredReports.filter((report) => report.status === status).length,
    color,
  }));
  const filteredActivities = activities.filter((activity) => {
    if (!startDate && !endDate) return true;
    const timestamp = new Date(activity.timestamp);
    if (startDate && timestamp < new Date(startDate)) return false;
    if (endDate && timestamp > new Date(`${endDate}T23:59:59`)) return false;
    return true;
  });

  return (
    <div className="page-stack reports-page">
      <div className="panel reports-panel">
        <div className="panel-header">
          <div>
            <h2>Reports</h2>
            <p className="panel-note">
              Operational records and website activity history.
            </p>
          </div>
        </div>

        <div className="toolbar reports-filters">
          <select
            value={wardFilter}
            onChange={(event) => setWardFilter(event.target.value)}
          >
            <option value="All">All wards</option>
            {wardOptions
              .filter((option) => option !== "All")
              .map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
          </select>
          <input
            type="date"
            value={startDate}
            onChange={(event) => setStartDate(event.target.value)}
          />
          <input
            type="date"
            value={endDate}
            onChange={(event) => setEndDate(event.target.value)}
          />
        </div>

        <div className="cards-grid two-col reports-charts">
          <div className="panel">
            <div className="panel-header">
              <div>
                <h2>Issue mix</h2>
                <span className="panel-note">
                  Filtered reports by reported problem
                </span>
              </div>
            </div>
            <div className="chart-wrap small">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={issueTypeCounts}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis
                    dataKey="name"
                    interval={0}
                    angle={-18}
                    textAnchor="end"
                    height={48}
                  />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]}>
                    {issueTypeCounts.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="panel">
            <div className="panel-header">
              <div>
                <h2>Report lifecycle</h2>
                <span className="panel-note">
                  Open, duplicate, and resolved records
                </span>
              </div>
            </div>
            <div className="chart-wrap small">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={reportStatusCounts}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="name" />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]}>
                    {reportStatusCounts.map((entry) => (
                      <Cell key={entry.name} fill={entry.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        <div className="table-wrap reports-table">
          <div className="reports-section-header">
            <div>
              <h2>Report data</h2>
              <span className="panel-note">
                {filteredReports.length} matching records
              </span>
            </div>
            <button type="button" className="btn-secondary" onClick={exportCsv}>
              <Download size={15} />
              Export reports CSV
            </button>
          </div>
          <table>
            <thead>
              <tr>
                <th>Report ID</th>
                <th>Issue</th>
                <th>Ward</th>
                <th>Priority</th>
                <th>Evidence</th>
                <th>Submission</th>
              </tr>
            </thead>
            <tbody>
              {filteredReports.map((report) => (
                <tr key={report.id}>
                  <td>{report.id}</td>
                  <td>{report.issueType}</td>
                  <td>{report.ward}</td>
                  <td>{report.priority}</td>
                  <td title={report.photoLoadError}>
                    {report.photoLoadError
                      ? "Photo unavailable"
                      : report.photo
                        ? "Photo attached"
                        : "No photo"}
                  </td>
                  <td>{formatDate(report.submittedAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="report-activity-log">
          <div className="panel-header">
            <div>
              <h2>Log</h2>
              <span className="panel-note">
                Combined website actions and task transitions
              </span>
            </div>
            <div className="reports-log-actions">
              <span className="panel-note">
                {filteredActivities.length} entries
              </span>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => navigate("/logs")}
              >
                Open full logs
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={exportLogCsv}
              >
                <Download size={15} />
                Export log CSV
              </button>
            </div>
          </div>
          <div className="report-activity-list">
            {filteredActivities.map((activity) => (
              <div className="report-activity-row" key={activity.id}>
                <span className={`dot ${activity.severity}`} />
                <div>
                  <strong>{activity.title}</strong>
                  <p>{activity.detail}</p>
                  <small>
                    {formatDate(activity.timestamp)} ·{" "}
                    {activity.user ?? "User not recorded"}
                  </small>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function AddWorkerPage({
  crews,
  onSave,
}: {
  crews: CrewRecord[];
  onSave: (worker: CrewWorker) => void;
}) {
  const navigate = useNavigate();
  const [form, setForm] = useState({
    id: "",
    name: "",
    email: "",
    phone: "",
    address: "",
    role: "Helper",
    crew: "Unassigned",
    ward: "Ward 12",
    status: "Available" as CrewWorker["status"],
  });
  const save = () => {
    if (!form.id.trim() || !form.name.trim() || !form.email.trim() || !form.phone.trim() || !form.address.trim()) return;
    onSave({
      id: form.id.trim().toUpperCase(),
      name: form.name.trim(),
      currentCrew: form.crew,
      role: form.role,
      ward: form.ward,
      status: form.status,
      officialEmail: form.email.trim(),
      phoneNumber: form.phone.trim(),
      address: form.address.trim(),
      loginStatus: "Credentials issued",
      joinedAt: new Date().toISOString(),
    });
    navigate("/crew-management");
  };
  return (
    <div className="page-stack dedicated-form-page">
      <div className="panel form-page-header">
        <div>
          <div className="eyebrow">Crew Management</div>
          <h2>Register new worker</h2>
          <p className="panel-note">
            The officer approves the worker record and issues secure field-app
            credentials before returning to Crew Management.
          </p>
        </div>
        <button
          type="button"
          className="btn-secondary"
          onClick={() => navigate("/crew-management")}
        >
          Back to Crew Management
        </button>
      </div>
      <div className="panel">
        <div className="form-grid">
          <label>
            Worker ID
            <input
              value={form.id}
              onChange={(event) => setForm({ ...form, id: event.target.value })}
              placeholder="WRK-107"
            />
          </label>
          <label>
            Full name
            <input
              value={form.name}
              onChange={(event) =>
                setForm({ ...form, name: event.target.value })
              }
            />
          </label>
          <label>
            Official email
            <input
              type="email"
              value={form.email}
              onChange={(event) =>
                setForm({ ...form, email: event.target.value })
              }
            />
          </label>
          <label>Phone number<input value={form.phone} onChange={(event) => setForm({ ...form, phone: event.target.value })} placeholder="+91 98765 00000" /></label>
          <label>Address<input value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} /></label>
          <label>
            Assignment role
            <select
              value={form.role}
              onChange={(event) =>
                setForm({ ...form, role: event.target.value })
              }
            >
              <option>Leader</option>
              <option>Technician</option>
              <option>Helper</option>
            </select>
          </label>
          <label>
            Initial crew
            <select
              value={form.crew}
              onChange={(event) =>
                setForm({ ...form, crew: event.target.value })
              }
            >
              <option>Unassigned</option>
              {crews.map((crew) => (
                <option key={crew.id}>{crew.name}</option>
              ))}
            </select>
          </label>
          <label>
            Ward
            <select
              value={form.ward}
              onChange={(event) =>
                setForm({ ...form, ward: event.target.value })
              }
            >
              <option>Ward 4</option>
              <option>Ward 7</option>
              <option>Ward 12</option>
              <option>Ward 15</option>
              <option>Ward 19</option>
              <option>Ward 22</option>
            </select>
          </label>
          <label>
            Operational status
            <select
              value={form.status}
              onChange={(event) =>
                setForm({
                  ...form,
                  status: event.target.value as CrewWorker["status"],
                })
              }
            >
              <option>Available</option>
              <option>Active</option>
              <option>On leave</option>
            </select>
          </label>
        </div>
        <div className="button-row">
          <button
            type="button"
            className="btn-primary"
            onClick={save}
            disabled={!form.id || !form.name || !form.email || !form.phone || !form.address}
          >
            Approve worker and save
          </button>
        </div>
      </div>
    </div>
  );
}

function CreateCrewPage({
  crews,
  workers,
  onSave,
  onAssignWorkers,
}: {
  crews: CrewRecord[];
  workers: CrewWorker[];
  onSave: (crew: CrewRecord) => void;
  onAssignWorkers: (crew: string, workerIds: string[]) => void;
}) {
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [ward, setWard] = useState("Ward 12");
  const [selectedWorkers, setSelectedWorkers] = useState<string[]>([]);
  const [sourceCrew, setSourceCrew] = useState("");
  const [splitName, setSplitName] = useState("");
  const unassigned = workers.filter(
    (worker) => worker.currentCrew === "Unassigned",
  );
  const save = () => {
    if (!name.trim()) return;
    onSave({
      id: createId("CREW"),
      name: name.trim(),
      ward,
      memberIds: selectedWorkers,
      createdAt: new Date().toISOString(),
    });
    if (selectedWorkers.length) onAssignWorkers(name.trim(), selectedWorkers);
    navigate("/crew-management");
  };
  return (
    <div className="page-stack dedicated-form-page">
      <div className="panel form-page-header">
        <div>
          <div className="eyebrow">Crew Management</div>
          <h2>Create or split a crew</h2>
          <p className="panel-note">
            Create a ward crew, assign unassigned workers, or prepare a new crew
            for a large operation.
          </p>
        </div>
        <button
          type="button"
          className="btn-secondary"
          onClick={() => navigate("/crew-management")}
        >
          Back to Crew Management
        </button>
      </div>
      <div className="panel">
        <div className="form-grid">
          <label>
            Crew name
            <input
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Crew Delta"
            />
          </label>
          <label>
            Assigned ward
            <select
              value={ward}
              onChange={(event) => setWard(event.target.value)}
            >
              <option>Ward 4</option>
              <option>Ward 7</option>
              <option>Ward 12</option>
              <option>Ward 15</option>
              <option>Ward 19</option>
              <option>Ward 22</option>
            </select>
          </label>
        </div>
        <h3>Assign unassigned workers</h3>
        <div className="worker-check-list">
          {unassigned.length ? (
            unassigned.map((worker) => (
              <label key={worker.id} className="checkbox-row">
                <input
                  type="checkbox"
                  checked={selectedWorkers.includes(worker.id)}
                  onChange={(event) =>
                    setSelectedWorkers(
                      event.target.checked
                        ? [...selectedWorkers, worker.id]
                        : selectedWorkers.filter((id) => id !== worker.id),
                    )
                  }
                />
                {worker.id} · {worker.name}
              </label>
            ))
          ) : (
            <span className="panel-note">
              No unassigned workers. Workers can be reassigned from the Crew
              Management worker detail panel.
            </span>
          )}
        </div>
        <div className="button-row">
          <button
            type="button"
            className="btn-primary"
            onClick={save}
            disabled={!name.trim()}
          >
            Create crew and assign selected
          </button>
        </div>
      </div>
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Split an existing crew</h2>
            <span className="panel-note">
              Use this when a crew grows beyond the ward’s practical operating
              size.
            </span>
          </div>
        </div>
        <div className="form-grid">
          <label>
            Source crew
            <select
              value={sourceCrew}
              onChange={(event) => setSourceCrew(event.target.value)}
            >
              <option value="">Select crew</option>
              {crews.map((crew) => (
                <option key={crew.id} value={crew.name}>
                  {crew.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            New crew name
            <input
              value={splitName}
              onChange={(event) => setSplitName(event.target.value)}
              placeholder="Crew Alpha B"
            />
          </label>
        </div>
        <div className="button-row">
          <button
            type="button"
            className="btn-secondary"
            disabled={!sourceCrew || !splitName.trim()}
            onClick={() => {
              const members = workers.filter(
                (worker) => worker.currentCrew === sourceCrew,
              );
              const moved = members
                .slice(Math.ceil(members.length / 2))
                .map((worker) => worker.id);
              onSave({
                id: createId("CREW"),
                name: splitName.trim(),
                ward:
                  crews.find((crew) => crew.name === sourceCrew)?.ward ?? ward,
                memberIds: moved,
                createdAt: new Date().toISOString(),
              });
              onAssignWorkers(splitName.trim(), moved);
              navigate("/crew-management");
            }}
          >
            Create split crew
          </button>
        </div>
      </div>
    </div>
  );
}

function LogsPage({
  activities,
  audits,
  workers,
  crews,
}: {
  activities: ActivityEntry[];
  audits: CreditAudit[];
  workers: CrewWorker[];
  crews: CrewRecord[];
}) {
  const [tab, setTab] = useState("Universal");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("All");
  const records =
    tab === "Universal"
      ? activities.map((item) => ({
          id: item.id,
          title: item.title,
          detail: item.detail,
          timestamp: item.timestamp,
          user: item.user ?? "System",
          category: item.category ?? "General",
        }))
      : tab === "Report logs"
        ? activities
            .filter(
              (item) =>
                item.category === "Reports" ||
                item.title.toLowerCase().includes("report"),
            )
            .map((item) => ({
              id: item.id,
              title: item.title,
              detail: item.detail,
              timestamp: item.timestamp,
              user: item.user ?? "System",
              category: "Reports",
            }))
        : tab === "Crew logs"
          ? activities
              .filter(
                (item) =>
                  item.category === "Crew" ||
                  item.detail.toLowerCase().includes("crew"),
              )
              .map((item) => ({
                id: item.id,
                title: item.title,
                detail: item.detail,
                timestamp: item.timestamp,
                user: item.user ?? "System",
                category: "Crew",
              }))
          : audits.map((item) => ({
              id: item.id,
              title: item.action,
              detail: `${item.workerId ?? ""} ${item.workOrderId} · ${item.reason}`,
              timestamp: item.timestamp,
              user: item.reviewer,
              category: tab === "Worker logs" ? "Worker" : "Ward",
            }));
  const filtered = records.filter((record) => {
    const textMatch = `${record.title} ${record.detail} ${record.user}`
      .toLowerCase()
      .includes(query.toLowerCase());
    return textMatch && (filter === "All" || record.category === filter);
  });
  const searchPlaceholder =
    tab === "Worker logs"
      ? "Search worker ID or name"
      : tab === "Crew logs"
        ? "Search crew"
        : tab === "Ward logs"
          ? "Search ward"
          : tab === "Report logs"
            ? "Search report activity"
            : "Search all activity";
  return (
    <div className="logs-page">
      <div className="logs-page-heading">
        <div>
          <div className="eyebrow">Audit and traceability</div>
          <h2>Logs</h2>
        </div>
        <span className="logs-result-count">{filtered.length} matching records</span>
      </div>
      <div className="logs-tabs">
        {[
          "Universal",
          "Report logs",
          "Crew logs",
          "Worker logs",
          "Ward logs",
        ].map((name) => (
          <button
            type="button"
            key={name}
            className={tab === name ? "active" : ""}
            onClick={() => {
              setTab(name);
              setQuery("");
            }}
          >
            {name}
          </button>
        ))}
      </div>
      <div className="logs-toolbar">
        <label className="logs-search-field">
          <Search size={17} aria-hidden="true" />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={searchPlaceholder} aria-label={searchPlaceholder} />
          {query ? <button type="button" onClick={() => setQuery("")} aria-label="Clear log search">×</button> : null}
        </label>
        {tab === "Universal" ? (
          <label className="logs-filter-field">
            <span>Filter</span>
            <select value={filter} onChange={(event) => setFilter(event.target.value)} aria-label="Filter universal logs">
              <option>All</option>
              <option>Evidence</option>
              <option>Cleaning</option>
              <option>Crew</option>
              <option>Credit</option>
            </select>
          </label>
        ) : null}
      </div>
      <div className="logs-list panel">
        {filtered.map((record) => (
          <div className="log-row" key={record.id}>
            <span className="dot info" />
            <div>
              <strong>{record.title}</strong>
              <p>{record.detail}</p>
              <small>
                {record.user} · {formatDate(record.timestamp)}
              </small>
            </div>
          </div>
        ))}
        {!filtered.length ? (
          <div className="empty-state">
            <ClipboardList size={28} />
            <h2>No matching logs</h2>
          </div>
        ) : null}
      </div>
      <div className="panel-note">
        {workers.length} workers · {crews.length} crews · {filtered.length}{" "}
        matching log records
      </div>
    </div>
  );
}

function CrewManagementPage({
  workers,
  crews,
  drains,
  onRefreshWorkers,
  reports,
  pools,
  allocations,
  policy,
  onPolicyChange,
  onAddWorker,
  onUpdateWorker,
  onAssignWorkers,
  onResetPassword,
}: {
  workers: CrewWorker[];
  crews: CrewRecord[];
  drains: DrainRecord[];
  onRefreshWorkers: () => Promise<void>;
  reports: ReportRecord[];
  pools: CreditPool[];
  allocations: CreditAllocation[];
  policy: CreditPolicy;
  onPolicyChange: (policy: CreditPolicy) => void;
  onAddWorker: (worker: CrewWorker) => void;
  onUpdateWorker: (workerId: string, changes: Partial<CrewWorker>) => void;
  onAssignWorkers: (crew: string, workerIds: string[]) => void;
  onResetPassword: (worker: CrewWorker) => void;
}) {
  const navigate = useNavigate();
  const [showAddForm, setShowAddForm] = useState(false);
  const [workerQuery, setWorkerQuery] = useState("");
  const [selectedWorkerId, setSelectedWorkerId] = useState("");
  const [reportPeriod, setReportPeriod] = useState("month");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [selectedWard, setSelectedWard] = useState<string | null>(null);
  const [editingWard, setEditingWard] = useState(false);
  const [wardDraft, setWardDraft] = useState<WardAllowance | null>(null);
  const [refreshingWorkers, setRefreshingWorkers] = useState(false);
  const [workerRefreshError, setWorkerRefreshError] = useState<string | null>(
    null,
  );
  const [newWorker, setNewWorker] = useState({
    name: "",
    id: "",
    email: "",
    role: "Helper",
    crew: "Unassigned",
    ward: "Ward 12",
    status: "Available" as CrewWorker["status"],
  });
  const workerStatus = (worker: CrewWorker) => worker.status ?? "Active";
  const assignedTaskCount = (worker: CrewWorker) =>
    drains.filter((drain) => {
      const assignedCrews = drain.assignedCrews?.length
        ? drain.assignedCrews
        : (drain.assignedCrew
            ?.split(",")
            .map((crew) => crew.trim())
            .filter(Boolean) ?? []);
      return (
        assignedCrews.some(
          (assignment) =>
            assignment === worker.currentCrew || assignment === worker.id,
        ) &&
        (drain.workStatus?.startsWith("Inspection assigned") === true ||
          drain.workStatus?.startsWith("Cleaning assigned") === true)
      );
    }).length;
  const crewNames = crews.map((crew) => crew.name);
  const activeWorkers = workers.filter(
    (worker) => workerStatus(worker) === "Active",
  ).length;
  const onLeave = workers.filter(
    (worker) => workerStatus(worker) === "On leave",
  ).length;
  const availableWorkers = workers.filter(
    (worker) => workerStatus(worker) === "Available",
  ).length;
  const monthlyPoints = allocations
    .filter((allocation) => {
      const date = new Date(allocation.timestamp);
      const now = new Date();
      return (
        date.getMonth() === now.getMonth() &&
        date.getFullYear() === now.getFullYear()
      );
    })
    .reduce((sum, allocation) => sum + allocation.credits, 0);
  const matchingWorkers = workers.filter((worker) =>
    `${worker.id} ${worker.name} ${worker.currentCrew}`
      .toLowerCase()
      .includes(workerQuery.toLowerCase()),
  );
  const selectedWorker = workers.find(
    (worker) => worker.id === selectedWorkerId,
  );
  const selectedAllocations = allocations.filter(
    (allocation) => allocation.workerId === selectedWorkerId,
  );
  const reportCutoff = (period: string) => {
    const date = new Date();
    if (period === "week") date.setDate(date.getDate() - 7);
    if (period === "month") date.setMonth(date.getMonth() - 1);
    if (period === "3 months") date.setMonth(date.getMonth() - 3);
    if (period === "6 months") date.setMonth(date.getMonth() - 6);
    return date;
  };
  const workerReportRows = selectedAllocations.filter((allocation) => {
    if (reportPeriod === "custom") {
      if (customStart && new Date(allocation.timestamp) < new Date(customStart))
        return false;
      if (
        customEnd &&
        new Date(allocation.timestamp) > new Date(`${customEnd}T23:59:59`)
      )
        return false;
      return true;
    }
    return new Date(allocation.timestamp) >= reportCutoff(reportPeriod);
  });
  const downloadWorkerReport = () => {
    if (!selectedWorker) return;
    const rows = [
      [
        "Worker ID",
        "Worker",
        "Historical crew",
        "Role",
        "Work order",
        "Drain section",
        "Linked reports",
        "Credits",
        "Timestamp",
      ],
      ...workerReportRows.map((allocation) => {
        const pool = pools.find((item) => item.id === allocation.poolId);
        return [
          allocation.workerId,
          allocation.workerName,
          allocation.historicalCrew,
          allocation.role,
          allocation.workOrderId,
          pool?.drainId ?? "",
          reports
            .filter((report) => report.drainId === pool?.drainId)
            .map((report) => report.id)
            .join(" "),
          allocation.credits,
          allocation.timestamp,
        ];
      }),
    ];
    const csv = rows
      .map((row) =>
        row
          .map((value) => `"${String(value).replaceAll('"', '""')}"`)
          .join(","),
      )
      .join("\n");
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = `${selectedWorker.id}-work-report.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };
  const refreshWorkers = async () => {
    setRefreshingWorkers(true);
    setWorkerRefreshError(null);
    try {
      await onRefreshWorkers();
    } catch (error) {
      setWorkerRefreshError(String(error));
    } finally {
      setRefreshingWorkers(false);
    }
  };
  const saveWorker = () => {
    if (!newWorker.id.trim() || !newWorker.name.trim()) return;
    onAddWorker({
      id: newWorker.id.trim().toUpperCase(),
      name: newWorker.name.trim(),
      currentCrew: newWorker.crew,
      role: newWorker.role,
      ward: newWorker.ward,
      status: newWorker.status,
      officialEmail: newWorker.email,
      loginStatus: "Credentials issued",
      joinedAt: new Date().toISOString(),
    });
    setNewWorker({
      name: "",
      id: "",
      email: "",
      role: "Helper",
      crew: "Unassigned",
      ward: "Ward 12",
      status: "Available",
    });
    setShowAddForm(false);
  };
  return (
    <div className="page-stack crew-management-redesign">
      <div className="panel crew-management-hero">
        <div>
          <div className="eyebrow">Workforce operations</div>
          <h2>Crew Management</h2>
          <p className="panel-note">
            Manage approved workers, ward crews and verified work outcomes.
            Attendance remains a field coordination record, never a credit
            input.
          </p>
        </div>
        <div className="button-row">
          <button
            type="button"
            className="btn-secondary"
            onClick={() => void refreshWorkers()}
            disabled={refreshingWorkers}
          >
            {refreshingWorkers ? "Refreshing workers…" : "Refresh workers"}
          </button>
          <button
            type="button"
            className="btn-primary"
            onClick={() => navigate("/crew-management/add-worker")}
          >
            <UsersRound size={16} /> Add new worker
          </button>
          <button
            type="button"
            className="btn-secondary"
            onClick={() => navigate("/crew-management/create-crew")}
          >
            <UsersRound size={16} /> Create new crew
          </button>
        </div>
      </div>
      {workerRefreshError ? (
        <p className="panel-note" role="alert">
          {workerRefreshError}
        </p>
      ) : null}
      <div className="cards-grid three-col crew-stat-grid">
        {[
          ["Total workers connected", workers.length, "teal"],
          ["Active workers", activeWorkers, "teal"],
          ["Workers on leave", onLeave, "amber"],
          ["Workers available", availableWorkers, "slate"],
          ["Crews / ward groups", crews.length, "teal"],
          ["Points given this month", monthlyPoints.toFixed(0), "teal"],
        ].map(([label, value, accent]) => (
          <div className={`metric-card ${accent}`} key={label}>
            <span className="metric-label">{label}</span>
            <span className="metric-value">{value}</span>
            <span className="panel-note">Outcome-based records only</span>
          </div>
        ))}
      </div>
      {showAddForm ? (
        <div className="panel worker-form-panel">
          <div className="panel-header">
            <div>
              <h2>Register and approve worker</h2>
              <span className="panel-note">
                Approved workers receive official field-app access credentials.
              </span>
            </div>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => setShowAddForm(false)}
            >
              Cancel
            </button>
          </div>
          <div className="form-grid">
            <label>
              Worker ID
              <input
                value={newWorker.id}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, id: event.target.value })
                }
                placeholder="WRK-107"
              />
            </label>
            <label>
              Full name
              <input
                value={newWorker.name}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, name: event.target.value })
                }
              />
            </label>
            <label>
              Official email
              <input
                type="email"
                value={newWorker.email}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, email: event.target.value })
                }
              />
            </label>
            <label>
              Assignment role
              <select
                value={newWorker.role}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, role: event.target.value })
                }
              >
                <option>Leader</option>
                <option>Technician</option>
                <option>Helper</option>
              </select>
            </label>
            <label>
              Assign crew
              <select
                value={newWorker.crew}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, crew: event.target.value })
                }
              >
                <option value="Unassigned">Unassigned</option>
                {crewNames.map((crew) => (
                  <option key={crew}>{crew}</option>
                ))}
              </select>
            </label>
            <label>
              Ward
              <select
                value={newWorker.ward}
                onChange={(event) =>
                  setNewWorker({ ...newWorker, ward: event.target.value })
                }
              >
                {Object.keys(policy.wardAllowances).map((ward) => (
                  <option key={ward}>{ward}</option>
                ))}
              </select>
            </label>
            <label>
              Worker status
              <select
                value={newWorker.status}
                onChange={(event) =>
                  setNewWorker({
                    ...newWorker,
                    status: event.target.value as CrewWorker["status"],
                  })
                }
              >
                <option>Available</option>
                <option>Active</option>
                <option>On leave</option>
              </select>
            </label>
          </div>
          <div className="button-row">
            <button
              type="button"
              className="btn-primary"
              onClick={saveWorker}
              disabled={!newWorker.id || !newWorker.name}
            >
              Approve worker and issue credentials
            </button>
          </div>
        </div>
      ) : null}
      <div className="crew-management-layout">
        <div className="page-stack">
          <div className="panel">
            <div className="panel-header">
              <div>
                <h2>Worker lookup</h2>
                <span className="panel-note">
                  Select an ID to reveal the worker report and role controls.
                </span>
              </div>
              <Search size={18} color="#0f766e" />
            </div>
            <input
              className="crew-worker-search"
              value={workerQuery}
              onChange={(event) => setWorkerQuery(event.target.value)}
              placeholder="Search by worker ID, name or crew"
            />
            <div className="worker-search-results">
              {matchingWorkers.map((worker) => (
                <button
                  type="button"
                  className={`worker-result ${selectedWorkerId === worker.id ? "selected" : ""}`}
                  key={worker.id}
                  onClick={() => setSelectedWorkerId(worker.id)}
                >
                  <span>
                    <strong>{worker.id}</strong>
                    <small>
                      {worker.name} · {worker.currentCrew} ·{" "}
                      {assignedTaskCount(worker)} assigned task
                      {assignedTaskCount(worker) === 1 ? "" : "s"}
                    </small>
                  </span>
                  <span className="status-chip bg-slate-100 text-slate-700">
                    {workerStatus(worker)}
                  </span>
                </button>
              ))}
            </div>
          </div>
          {selectedWorker ? (
            <div className="panel worker-detail-panel">
              <div className="panel-header">
                <div>
                  <h2>{selectedWorker.name}</h2>
                  <span className="panel-note">
                    {selectedWorker.id} ·{" "}
                    {selectedWorker.officialEmail ??
                      "Official email not recorded"}
                  </span>
                </div>
                <span className="status-chip bg-emerald-100 text-emerald-700">
                  {workerStatus(selectedWorker)}
                </span>
              </div>
              <div className="worker-detail-grid">
                <div>
                  <span>Current crew</span>
                  <select
                    value={selectedWorker.currentCrew}
                    onChange={(event) =>
                      onAssignWorkers(event.target.value, [selectedWorker.id])
                    }
                  >
                    <option value="Unassigned">Unassigned</option>
                    {crewNames.map((crew) => (
                      <option key={crew}>{crew}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <span>Assigned tasks</span>
                  <strong>{assignedTaskCount(selectedWorker)}</strong>
                </div>
                <div>
                  <span>Ward</span>
                  <strong>{selectedWorker.ward ?? "Not assigned"}</strong>
                </div>
                <div>
                  <span>Phone number</span>
                  <strong>{selectedWorker.phoneNumber ?? "Not recorded"}</strong>
                </div>
                <div>
                  <span>Address</span>
                  <strong>{selectedWorker.address ?? "Not recorded"}</strong>
                </div>
                <div>
                  <span>Role</span>
                  <select
                    value={selectedWorker.role}
                    onChange={(event) =>
                      onUpdateWorker(selectedWorker.id, {
                        role: event.target.value,
                      })
                    }
                  >
                    <option>Leader</option>
                    <option>Technician</option>
                    <option>Helper</option>
                  </select>
                </div>
                <div>
                  <span>Field-app access</span>
                  <strong>
                    {selectedWorker.loginStatus ?? "Credentials issued"}
                  </strong>
                </div>
              </div>
              <div className="button-row">
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={downloadWorkerReport}
                >
                  <Download size={15} /> Download work report
                </button>
                <button
                  type="button"
                  className="btn-danger"
                  onClick={() => onResetPassword(selectedWorker)}
                >
                  Reset password
                </button>
              </div>
              <div className="toolbar report-period-toolbar">
                {["week", "month", "3 months", "6 months", "custom"].map(
                  (option) => (
                    <button
                      type="button"
                      className={
                        reportPeriod === option
                          ? "btn-primary"
                          : "btn-secondary"
                      }
                      key={option}
                      onClick={() => setReportPeriod(option)}
                    >
                      {option === "3 months"
                        ? "3-month"
                        : option === "6 months"
                          ? "6-month"
                          : option.charAt(0).toUpperCase() + option.slice(1)}
                    </button>
                  ),
                )}
                {reportPeriod === "custom" ? (
                  <>
                    <input
                      type="date"
                      value={customStart}
                      onChange={(event) => setCustomStart(event.target.value)}
                    />
                    <input
                      type="date"
                      value={customEnd}
                      onChange={(event) => setCustomEnd(event.target.value)}
                    />
                  </>
                ) : null}
              </div>
              <div className="worker-report-summary">
                <strong>{workerReportRows.length} verified tasks</strong>
                <strong>
                  {workerReportRows
                    .reduce((sum, allocation) => sum + allocation.credits, 0)
                    .toFixed(2)}{" "}
                  credits earned
                </strong>
                <span>
                  Pending credits are excluded until evidence approval.
                </span>
              </div>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Work order</th>
                      <th>Drain section</th>
                      <th>Role at assignment</th>
                      <th>Credits</th>
                      <th>Timestamp</th>
                    </tr>
                  </thead>
                  <tbody>
                    {workerReportRows.map((allocation) => {
                      const pool = pools.find(
                        (item) => item.id === allocation.poolId,
                      );
                      return (
                        <tr key={allocation.id}>
                          <td>{allocation.workOrderId}</td>
                          <td>{pool?.drainId}</td>
                          <td>{allocation.role}</td>
                          <td>{allocation.credits.toFixed(2)}</td>
                          <td>{formatDate(allocation.timestamp)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          ) : (
            <div className="panel empty-state">
              <Award size={28} />
              <h2>Select a worker to view their report</h2>
              <p>
                Worker-specific credits, tasks, current role and report download
                appear here after selection.
              </p>
            </div>
          )}
        </div>
        <div className="page-stack">
          <div className="panel">
            <div className="panel-header">
              <div>
                <h2>Ward credit allowances</h2>
                <span className="panel-note">
                  Configure reward and adjustment points by ward.
                </span>
              </div>
              <Settings size={18} color="#0f766e" />
            </div>
            <input className="crew-worker-search" placeholder="Search ward" onChange={(event) => {
              const query = event.target.value.toLowerCase();
              document.querySelectorAll<HTMLElement>(".ward-policy-row").forEach((row) => {
                row.hidden = !row.dataset.ward?.toLowerCase().includes(query);
              });
            }} />
            <div className="ward-policy-list ward-policy-scroll">
              {Object.keys(policy.wardAllowances).map((ward) => (
                <button type="button" className="ward-policy-row" data-ward={ward} key={ward} onClick={() => {
                  setSelectedWard(ward);
                  setWardDraft(policy.wardAllowances[ward]);
                  setEditingWard(false);
                }}>
                  <strong>{ward}</strong>
                  <span>{policy.wardAllowances[ward].successfulCleaning} cleaning points · View policy</span>
                </button>
              ))}
            </div>
          </div>
          {selectedWard && wardDraft ? (
            <div className="modal-backdrop">
              <div className="modal-card ward-policy-modal">
                <div className="panel-header">
                  <div><h2>{selectedWard} credit policy</h2><span className="panel-note">Successful completion allowances and related penalties.</span></div>
                  <button type="button" className="btn-secondary" onClick={() => setSelectedWard(null)}>Close</button>
                </div>
                <div className="ward-policy-form">
                  {([
                    ["successfulCleaning", "Successful cleaning completion"],
                    ["successfulInspection", "Successful inspection completion"],
                    ["incompleteWorkPenalty", "Incomplete work penalty"],
                    ["rejectedEvidencePenalty", "Rejected evidence penalty"],
                    ["delayedWorkPenalty", "Delayed work penalty"],
                  ] as [keyof WardAllowance, string][]).map(([key, label]) => (
                    <label key={key}>{label}<input type="number" min="0" value={wardDraft[key]} disabled={!editingWard} onChange={(event) => setWardDraft({ ...wardDraft, [key]: Number(event.target.value) })} /></label>
                  ))}
                </div>
                <div className="button-row">
                  {!editingWard ? <button type="button" className="btn-primary" onClick={() => setEditingWard(true)}>Edit allowance</button> : <button type="button" className="btn-primary" onClick={() => { onPolicyChange({ ...policy, wardAllowances: { ...policy.wardAllowances, [selectedWard]: wardDraft } }); setEditingWard(false); }}>Save allowance changes</button>}
                </div>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function CrewCreditsPage({
  workers,
  reports,
  pools,
  allocations,
  audits,
  policy,
  onPolicyChange,
}: {
  workers: CrewWorker[];
  reports: ReportRecord[];
  pools: CreditPool[];
  allocations: CreditAllocation[];
  audits: CreditAudit[];
  policy: CreditPolicy;
  onPolicyChange: (policy: CreditPolicy) => void;
}) {
  const [period, setPeriod] = useState("3 months");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [showPolicy, setShowPolicy] = useState(false);
  const [reportNow] = useState(() => new Date());
  const cutoff = new Date(reportNow);
  if (period === "7 days") cutoff.setDate(cutoff.getDate() - 7);
  if (period === "1 month") cutoff.setMonth(cutoff.getMonth() - 1);
  if (period === "3 months") cutoff.setMonth(cutoff.getMonth() - 3);
  if (period === "6 months") cutoff.setMonth(cutoff.getMonth() - 6);
  const inRange = (timestamp: string) => {
    const date = new Date(timestamp);
    if (startDate && date < new Date(startDate)) return false;
    if (endDate && date > new Date(`${endDate}T23:59:59`)) return false;
    if (!startDate && !endDate && date < cutoff) return false;
    return true;
  };
  const rangeAllocations = allocations.filter((allocation) =>
    inRange(allocation.timestamp),
  );
  const rangePools = pools.filter((pool) => inRange(pool.createdAt));
  const rosterCount = workers.length;
  const delayedTasks = rangePools.filter(
    (pool) => pool.onTime === false,
  ).length;
  const releasedCredits = rangePools
    .filter((pool) => pool.status === "Released")
    .reduce((sum, pool) => sum + pool.proposedCredits, 0);
  const exportCredits = () => {
    const rows = [
      [
        "Worker ID",
        "Worker",
        "Historical crew",
        "Role",
        "Work order",
        "Drain section",
        "Credits",
        "Timestamp",
      ],
      ...rangeAllocations.map((allocation) => [
        allocation.workerId,
        allocation.workerName,
        allocation.historicalCrew,
        allocation.role,
        allocation.workOrderId,
        allocation.workOrderId.replace("WO-", ""),
        allocation.credits,
        allocation.timestamp,
      ]),
    ];
    const csv = rows
      .map((row) =>
        row
          .map((value) => `"${String(value).replaceAll('"', '""')}"`)
          .join(","),
      )
      .join("\n");
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = "drainrank-individual-credit-history.csv";
    link.click();
    URL.revokeObjectURL(url);
  };
  const updatePolicy = (key: keyof CreditPolicy, value: number) =>
    onPolicyChange({ ...policy, [key]: value });

  return (
    <div className="page-stack crew-management-page">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Crew Management</h2>
            <p className="panel-note">
              Work-outcome points are released only after authorised evidence
              acceptance. Credits are not wages and have no monetary conversion.
            </p>
          </div>
          <button
            type="button"
            className="btn-secondary"
            onClick={() => setShowPolicy((visible) => !visible)}
          >
            <Settings size={15} />{" "}
            {showPolicy ? "Hide policy" : "Configure policy"}
          </button>
        </div>
        <div className="toolbar reports-filters">
          {["7 days", "1 month", "3 months", "6 months"].map((option) => (
            <button
              key={option}
              type="button"
              className={
                period === option && !startDate && !endDate
                  ? "btn-primary"
                  : "btn-secondary"
              }
              onClick={() => {
                setPeriod(option);
                setStartDate("");
                setEndDate("");
              }}
            >
              {option}
            </button>
          ))}
          <input
            type="date"
            value={startDate}
            onChange={(event) => setStartDate(event.target.value)}
            aria-label="Credit report start date"
          />
          <input
            type="date"
            value={endDate}
            onChange={(event) => setEndDate(event.target.value)}
            aria-label="Credit report end date"
          />
          <button
            type="button"
            className="btn-secondary"
            onClick={exportCredits}
          >
            <Download size={15} /> Export CSV
          </button>
        </div>
        <div className="cards-grid three-col">
          {[
            ["Released points", releasedCredits.toFixed(0), "teal"],
            [
              "Verified work orders",
              rangePools.filter((pool) => pool.status === "Released").length,
              "teal",
            ],
            [
              "Pending verification",
              rangePools.filter(
                (pool) => pool.status === "Pending verification",
              ).length,
              "amber",
            ],
            ["Delayed tasks", delayedTasks, delayedTasks ? "amber" : "teal"],
          ].map(([label, value, accent]) => (
            <div className={`metric-card ${accent}`} key={label}>
              <span className="metric-label">{label}</span>
              <span className="metric-value">{value}</span>
            </div>
          ))}
        </div>
        {showPolicy ? (
          <div className="panel policy-editor">
            <div className="panel-header">
              <h2>Credit policy</h2>
              <span className="panel-note">
                Changes apply to future pools; released history is immutable.
              </span>
            </div>
            <div className="form-grid">
              <label>
                Cleaning base points
                <input
                  type="number"
                  min="0"
                  value={policy.baseCleaning}
                  onChange={(event) =>
                    updatePolicy("baseCleaning", Number(event.target.value))
                  }
                />
              </label>
              <label>
                Inspection base points
                <input
                  type="number"
                  min="0"
                  value={policy.baseInspection}
                  onChange={(event) =>
                    updatePolicy("baseInspection", Number(event.target.value))
                  }
                />
              </label>
              <label>
                Complexity multiplier
                <input
                  type="number"
                  min="0"
                  step="0.1"
                  value={policy.complexityMultiplier}
                  onChange={(event) =>
                    updatePolicy(
                      "complexityMultiplier",
                      Number(event.target.value),
                    )
                  }
                />
              </label>
              <label>
                Scope multiplier
                <input
                  type="number"
                  min="0"
                  step="0.1"
                  value={policy.scopeMultiplier}
                  onChange={(event) =>
                    updatePolicy("scopeMultiplier", Number(event.target.value))
                  }
                />
              </label>
              <label>
                Evidence multiplier
                <input
                  type="number"
                  min="0"
                  step="0.1"
                  value={policy.evidenceMultiplier}
                  onChange={(event) =>
                    updatePolicy(
                      "evidenceMultiplier",
                      Number(event.target.value),
                    )
                  }
                />
              </label>
            </div>
            <div className="form-grid">
              {Object.entries(policy.roleWeights).map(([role, weight]) => (
                <label key={role}>
                  {role} weight
                  <input
                    type="number"
                    min="0"
                    step="0.1"
                    value={weight}
                    onChange={(event) =>
                      onPolicyChange({
                        ...policy,
                        roleWeights: {
                          ...policy.roleWeights,
                          [role]: Number(event.target.value),
                        },
                      })
                    }
                  />
                </label>
              ))}
            </div>
            <p className="panel-note">
              Allocation uses the recorded roster and these role weights only.
            </p>
          </div>
        ) : null}
      </div>

      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Individual work reports</h2>
            <span className="panel-note">
              Historical crew and role are captured at allocation time.
            </span>
          </div>
          <span className="panel-note">
            {rangeAllocations.length} allocation records · {rosterCount}{" "}
            rostered workers
          </span>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Worker ID</th>
                <th>Historical crew / role</th>
                <th>Work order</th>
                <th>Drain section / reports</th>
                <th>Review outcome</th>
                <th>Credits</th>
                <th>Timestamp</th>
              </tr>
            </thead>
            <tbody>
              {rangeAllocations.map((allocation) => {
                const pool = pools.find(
                  (item) => item.id === allocation.poolId,
                );
                return (
                  <tr key={allocation.id}>
                    <td>
                      <strong>{allocation.workerId}</strong>
                      <br />
                      <span className="muted">{allocation.workerName}</span>
                    </td>
                    <td>
                      {allocation.historicalCrew}
                      <br />
                      <span className="muted">{allocation.role}</span>
                    </td>
                    <td>{allocation.workOrderId}</td>
                    <td>
                      {pool?.drainId ?? "Not recorded"}
                      <br />
                      <span className="muted">
                        {reports
                          .filter((report) => report.drainId === pool?.drainId)
                          .map((report) => report.id)
                          .join(", ") || "No linked report"}
                      </span>
                    </td>
                    <td>
                      <span className="status-chip bg-emerald-100 text-emerald-700">
                        Accepted
                      </span>
                    </td>
                    <td>
                      <strong>{allocation.credits.toFixed(2)}</strong>
                    </td>
                    <td>{formatDate(allocation.timestamp)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {!rangeAllocations.length ? (
            <div className="empty-state">
              <Award size={24} />
              <h2>No released credits in this period</h2>
              <p>
                Pending or rejected evidence never appears as final individual
                credits.
              </p>
            </div>
          ) : null}
        </div>
      </div>

      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Credit pools and audit trail</h2>
            <span className="panel-note">
              Every pool, approval and adjustment is tied to a work order and
              reviewer.
            </span>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Pool / work order</th>
                <th>Scope and evidence</th>
                <th>Proposed points</th>
                <th>Status</th>
                <th>Reason</th>
              </tr>
            </thead>
            <tbody>
              {rangePools.map((pool) => (
                <tr key={pool.id}>
                  <td>
                    <strong>{pool.id}</strong>
                    <br />
                    <span className="muted">
                      {pool.workOrderId} · {pool.drainId}
                    </span>
                  </td>
                  <td>
                    {pool.taskType} · {pool.complexity}
                    <br />
                    <span className="muted">
                      {Math.round(pool.completedScope * 100)}% scope ·{" "}
                      {Math.round(pool.evidenceQuality * 100)}% evidence ·{" "}
                      {pool.onTime === false ? "Delayed" : "On deadline"}
                    </span>
                  </td>
                  <td>{pool.proposedCredits}</td>
                  <td>
                    <span
                      className={`status-chip ${pool.status === "Released" ? "bg-emerald-100 text-emerald-700" : pool.status === "Held" ? "bg-rose-100 text-rose-700" : "bg-amber-100 text-amber-700"}`}
                    >
                      {pool.status}
                    </span>
                  </td>
                  <td>{pool.reason}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="report-activity-list">
          {audits
            .filter((audit) => inRange(audit.timestamp))
            .slice(0, 10)
            .map((audit) => (
              <div className="report-activity-row" key={audit.id}>
                <ShieldCheck size={15} />
                <div>
                  <strong>
                    {audit.action} · {audit.workOrderId}
                  </strong>
                  <p>{audit.reason}</p>
                  <small>
                    {audit.reviewer} · {formatDate(audit.timestamp)}
                  </small>
                </div>
              </div>
            ))}
        </div>
      </div>
      <div className="panel-note">
        Crew responsibility is evaluated through completed scope, verified
        quality and deadline compliance. Operational field attendance remains
        separate from this municipal credit record.
      </div>
    </div>
  );
}

void CrewCreditsPage;

function AdministrationPage({
  email,
  preferences,
  onPreferencesChange,
  onResetData,
}: {
  email: string;
  preferences: { notifications: boolean; dailyDigest: boolean };
  onPreferencesChange: (
    preferences: { notifications: boolean; dailyDigest: boolean },
  ) => void;
  onResetData: () => Promise<string | null>;
}) {
  const [isResetting, setIsResetting] = useState(false);
  const [resetMessage, setResetMessage] = useState<string | null>(null);

  const confirmDataReset = async () => {
    const confirmation = window.prompt(
      "This permanently deletes all operational data, photos, and non-admin login accounts. Admin accounts are kept; configuration resets to defaults. Type RESET DATA to continue.",
    );
    if (confirmation !== "RESET DATA") return;

    setIsResetting(true);
    setResetMessage(null);
    try {
      const photoCleanupError = await onResetData();
      setResetMessage(
        photoCleanupError
          ? `App data was reset, but Supabase photo cleanup failed: ${photoCleanupError}`
          : "App data and Supabase Storage photos were reset.",
      );
    } catch (error) {
      setResetMessage(
        `Reset failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    } finally {
      setIsResetting(false);
    }
  };

  return (
    <div className="page-stack settings-page">
      <div className="settings-heading">
        <div>
          <span className="eyebrow">Workspace settings</span>
          <h2>Administration</h2>
          <p className="panel-note">
            Manage your municipal account, access roles, and workspace
            preferences.
          </p>
        </div>
        <Settings size={24} color="#215B63" />
      </div>

      <div className="settings-grid">
        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Account details</h3>
              <p className="panel-note">
                Your profile used for municipal operations.
              </p>
            </div>
            <UsersRound size={20} color="#215B63" />
          </div>
          <div className="settings-form-grid">
            <label>
              Official email
              <span className="settings-input-icon">
                <Mail size={15} />
                <input type="email" value={email} readOnly />
              </span>
            </label>
            <label>
              Current role
              <input value="Dashboard administrator" readOnly />
            </label>
          </div>
          <div className="settings-inline-note">
            <ShieldCheck size={16} />
            <span>
              Authentication and access are verified by Supabase before
              dashboard data is loaded.
            </span>
          </div>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Municipal workspace</h3>
              <p className="panel-note">
                Operating scope and organisational defaults.
              </p>
            </div>
            <Building2 size={20} color="#215B63" />
          </div>
          <div className="settings-form-grid">
            <label>
              Municipality
              <input value="Delhi Municipal Operations" readOnly />
            </label>
            <label>
              Operating ward
              <select defaultValue="Ward 12">
                <option>Ward 12</option>
                <option>All wards</option>
              </select>
            </label>
            <label>
              Time zone
              <select defaultValue="Asia/Kolkata">
                <option value="Asia/Kolkata">India Standard Time (IST)</option>
              </select>
            </label>
            <label>
              Default priority view
              <select defaultValue="Needs attention">
                <option>Critical first</option>
                <option>Needs attention</option>
                <option>Monitoring</option>
              </select>
            </label>
          </div>
        </section>

        <section className="panel settings-panel settings-wide">
          <div className="settings-section-heading">
            <div>
              <h3>Municipal users and roles</h3>
              <p className="panel-note">
                Review access responsibilities for the operations team.
              </p>
            </div>
            <button
              type="button"
              className="btn-secondary"
              disabled
              title="Manage dashboard administrator access in Supabase."
            >
              <UsersRound size={15} /> Manage access in Supabase
            </button>
          </div>
          <div className="user-role-table">
            <div className="user-role-row user-role-header">
              <span>User</span>
              <span>Department</span>
              <span>Role</span>
              <span>Access</span>
            </div>
            <div className="user-role-row">
              <span>
                <strong>{email}</strong>
                <small>Verified Supabase account</small>
              </span>
              <span>Drainage Operations</span>
              <span>Dashboard administrator</span>
              <span className="status-chip success">Authorized</span>
            </div>
          </div>
          <div className="role-permissions">
            <span className="label">Role permissions</span>
            <span>Reports</span>
            <span>Map</span>
            <span>Queues</span>
            <span>Evidence review</span>
            <span>Administration</span>
          </div>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Notifications</h3>
              <p className="panel-note">
                Choose which operational updates appear in your workspace.
              </p>
            </div>
            <Bell size={20} color="#215B63" />
          </div>
          <label className="settings-toggle">
            <span>
              <strong>Priority changes</strong>
              <small>Notify when an issue is escalated or reclassified.</small>
            </span>
            <input
              type="checkbox"
              checked={preferences.notifications}
              onChange={(event) =>
                onPreferencesChange({
                  ...preferences,
                  notifications: event.target.checked,
                })
              }
            />
          </label>
          <label className="settings-toggle">
            <span>
              <strong>Daily operations summary</strong>
              <small>Receive a summary of queues, reports, and evidence.</small>
            </span>
            <input
              type="checkbox"
              checked={preferences.dailyDigest}
              onChange={(event) =>
                onPreferencesChange({
                  ...preferences,
                  dailyDigest: event.target.checked,
                })
              }
            />
          </label>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Backend data and session</h3>
              <p className="panel-note">
                Dashboard records are loaded from and saved to the authorized
                Supabase workspace.
              </p>
            </div>
            <ShieldCheck size={20} color="#0F766E" />
          </div>
          <div className="settings-logout">
            <div>
              <strong>Session security</strong>
              <small>
                Your session uses Supabase authentication and row-level
                authorization. Sign out from the secure session control above
                the dashboard.
              </small>
            </div>
          </div>
        </section>

        <section className="panel settings-panel settings-wide">
          <div className="settings-section-heading">
            <div>
              <h3>Reset operational data</h3>
              <p className="panel-note">
                Clear reports, operational logs, work history, non-admin login
                accounts, settings, and Supabase photos for a fresh test.
              </p>
            </div>
            <ShieldAlert size={20} color="#b42318" />
          </div>
          <div className="settings-logout">
            <div>
              <strong>All accounts with the admin role are kept</strong>
              <small>
                Admin accounts are kept. Crew and citizen accounts and rosters
                are deleted. App settings return to defaults, and stored
                photos are removed from the app's Supabase buckets.
              </small>
            </div>
            <button
              type="button"
              className="btn-danger"
              disabled={isResetting}
              onClick={() => void confirmDataReset()}
            >
              <Trash2 size={15} />
              {isResetting ? "Resetting..." : "Reset all app data"}
            </button>
          </div>
          {resetMessage ? (
            <p className="panel-note" role="status" aria-live="polite">
              {resetMessage}
            </p>
          ) : null}
        </section>
      </div>
    </div>
  );
}

export default App;
