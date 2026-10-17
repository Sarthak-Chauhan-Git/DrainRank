import { useEffect, useMemo, useState } from "react";
import {
  BrowserRouter,
  NavLink,
  Navigate,
  Route,
  Routes,
  useLocation,
  useNavigate,
  useSearchParams,
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
  AlertTriangle,
  Bell,
  Building2,
  CheckCheck,
  ClipboardCheck,
  ChevronRight,
  ClipboardList,
  Download,
  Droplets,
  Eye,
  Gauge,
  LogOut,
  Mail,
  MapPinned,
  PanelLeftClose,
  PanelLeftOpen,
  ShieldAlert,
  RefreshCw,
  Search,
  ShieldCheck,
  Settings,
  Trash2,
  UsersRound,
  Wrench,
} from "lucide-react";

type DrainStatus =
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

interface DrainRecord {
  id: string;
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
  lastObservation: string;
  assignedCrew?: string;
  workStatus?: string;
  issueType: string;
  mapPosition: [number, number];
  lastUpdated: string;
}

interface ReportRecord {
  id: string;
  drainId: string;
  reporterName: string;
  issueType: string;
  ward: string;
  location: string;
  description: string;
  urgent: boolean;
  photo?: string;
  submittedAt: string;
  priority: number;
  reasons: string[];
  status: "Open" | "Duplicate" | "Resolved";
}

interface ActivityEntry {
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

interface OutcomeRecord {
  id: string;
  drainId: string;
  beforeCondition: string;
  afterCondition: string;
  postRainObservation: string;
  outcome: OutcomeType;
  recommendation: string;
  timestamp: string;
}

interface AppState {
  drains: DrainRecord[];
  reports: ReportRecord[];
  activities: ActivityEntry[];
  outcomes: OutcomeRecord[];
}

interface ReportForm {
  reporterName: string;
  issueType: string;
  ward: string;
  location: string;
  description: string;
  urgent: boolean;
  photo?: string;
}

interface InspectionForm {
  drainId: string;
  observedCondition: string;
  estimatedBlockage: number;
  notes: string;
  photo?: string;
}

const STORAGE_KEY = "drainrank-v1";
const navItems = [
  { label: "Overview", path: "/overview", icon: Gauge },
  { label: "Drain Map", path: "/map", icon: MapPinned },
  { label: "Work Queues", path: "/queues", icon: ClipboardCheck },
  { label: "Work Orders", path: "/work-orders", icon: ClipboardList },
  { label: "Evidence Review", path: "/evidence", icon: ShieldCheck },
  { label: "Outcome Intelligence", path: "/outcomes", icon: Bell },
  { label: "Reports", path: "/reports", icon: Download },
  { label: "Administration", path: "/administration", icon: UsersRound },
];

const createId = (prefix: string) =>
  `${prefix}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;

const formatDate = (value: string) =>
  new Date(value).toLocaleString([], {
    dateStyle: "medium",
    timeStyle: "short",
  });

const createSeedData = (): AppState => {
  const now = new Date();
  const iso = (daysAgo: number, hoursAgo = 0) =>
    new Date(
      now.getTime() - (daysAgo * 24 + hoursAgo) * 60 * 60 * 1000,
    ).toISOString();

  const drains: DrainRecord[] = [
    {
      id: "DR-A",
      location: "Ward 12, Hospital Road",
      ward: "Ward 12",
      reason: "Partial blockage near critical hospital access",
      status: "Cleaning Recommended",
      priority: 80,
      consequence: 1,
      catchment: 1,
      visibleBlockage: 50,
      condition: "Partially blocked",
      evidenceStatus: "Photo review complete",
      lastObservation: iso(1, 2),
      workStatus: "Ready for assignment",
      issueType: "Partial Blockage",
      mapPosition: [28.6469, 77.4316],
      lastUpdated: iso(1, 2),
    },
    {
      id: "DR-B",
      location: "Ward 12, Shanti Nagar",
      ward: "Ward 12",
      reason: "Severe visible blockage in a residential area",
      status: "Pending Review",
      priority: 76.25,
      consequence: 0.4,
      catchment: 0.75,
      visibleBlockage: 100,
      condition: "Severe blockage",
      evidenceStatus: "After photo submitted",
      lastObservation: iso(0, 4),
      assignedCrew: "Crew Alpha",
      workStatus: "Completion claim submitted",
      issueType: "Blocked Drain",
      mapPosition: [28.6412, 77.428],
      lastUpdated: iso(0, 4),
    },
    {
      id: "DR-C",
      location: "Ward 12, Central Underpass",
      ward: "Ward 12",
      reason:
        "Potentially high-consequence waterlogging location with insufficient current evidence",
      status: "Inspection Required",
      priority: 81,
      consequence: 0.8,
      catchment: 0.6,
      evidenceUncertainty: 1,
      condition: "Evidence uncertain",
      evidenceStatus: "Awaiting field inspection",
      lastObservation: iso(2, 5),
      workStatus: "Inspection queued",
      issueType: "Waterlogging",
      mapPosition: [28.6462, 77.4362],
      lastUpdated: iso(2, 5),
    },
    {
      id: "DR-D",
      location: "Ward 12, Green Lane",
      ward: "Ward 12",
      reason: "Visible blockage but lower documented consequence",
      status: "Cleaning Recommended",
      priority: 63.6,
      consequence: 0.3,
      catchment: 0.46,
      visibleBlockage: 100,
      condition: "Visible blockage",
      evidenceStatus: "Usable evidence available",
      lastObservation: iso(1, 9),
      workStatus: "Scheduled",
      issueType: "Blocked Drain",
      mapPosition: [28.6388, 77.4269],
      lastUpdated: iso(1, 9),
    },
    {
      id: "DR-E",
      location: "Ward 12, Park Lane",
      ward: "Ward 12",
      reason:
        "Latest observation does not show visible blockage; future problems remain possible",
      status: "Monitoring",
      priority: 18,
      consequence: 0.2,
      catchment: 0.42,
      condition: "Visually clear",
      evidenceStatus: "Recent usable image - clear",
      lastObservation: iso(0, 1),
      workStatus: "Monitoring",
      issueType: "Uncertain Condition",
      mapPosition: [28.6405, 77.422],
      lastUpdated: iso(0, 1),
    },
  ];

  drains.push(
    {
      id: "DR-F",
      location: "Ward 7, Nehru Market",
      ward: "Ward 7",
      reason: "Assigned cleaning for recurring market debris.",
      status: "Assigned",
      priority: 88,
      consequence: 0.85,
      catchment: 0.9,
      visibleBlockage: 92,
      condition: "Blocked",
      evidenceStatus: "Before and after evidence pending",
      lastObservation: iso(0, 6),
      assignedCrew: "Crew Bravo",
      workStatus: "In progress",
      issueType: "Blocked Drain",
      mapPosition: [28.6124, 77.2865],
      lastUpdated: iso(0, 6),
    },
    {
      id: "DR-G",
      location: "Ward 7, Railway Colony",
      ward: "Ward 7",
      reason: "Cleaning returned for poor-quality evidence.",
      status: "Rework Required",
      priority: 78,
      consequence: 0.7,
      catchment: 0.72,
      visibleBlockage: 84,
      condition: "Heavy silt",
      evidenceStatus: "Rework requested - image quality insufficient",
      lastObservation: iso(1, 4),
      assignedCrew: "Crew Bravo",
      workStatus: "Rework required",
      issueType: "Silt Accumulation",
      mapPosition: [28.6182, 77.2941],
      lastUpdated: iso(1, 4),
    },
    {
      id: "DR-H",
      location: "Ward 19, Yamuna Edge",
      ward: "Ward 19",
      reason: "Accepted cleaning evidence; monitor after rainfall.",
      status: "Reviewed",
      priority: 69,
      consequence: 0.8,
      catchment: 0.65,
      visibleBlockage: 76,
      condition: "Clear after cleaning",
      evidenceStatus: "Accepted by reviewer",
      lastObservation: iso(3, 2),
      assignedCrew: "Crew Charlie",
      workStatus: "Completed - evidence accepted",
      issueType: "Waterlogging",
      mapPosition: [28.6765, 77.2584],
      lastUpdated: iso(3, 2),
    },
    {
      id: "DR-I",
      location: "Ward 19, Seelampur Crossing",
      ward: "Ward 19",
      reason: "Repeated waterlogging after rainfall requires follow-up.",
      status: "Monitoring",
      priority: 54,
      consequence: 0.72,
      catchment: 0.83,
      condition: "No visible blockage; waterlogging recurring",
      evidenceStatus: "Outcome observation recorded",
      lastObservation: iso(2, 1),
      workStatus: "Monitoring and follow-up",
      issueType: "Waterlogging",
      mapPosition: [28.6697, 77.2718],
      lastUpdated: iso(2, 1),
    },
    {
      id: "DR-J",
      location: "Ward 4, Civil Lines",
      ward: "Ward 4",
      reason: "New report awaiting field verification.",
      status: "Inspection Required",
      priority: 73,
      consequence: 0.6,
      catchment: 0.55,
      evidenceUncertainty: 1,
      condition: "Unknown",
      evidenceStatus: "No field evidence yet",
      lastObservation: iso(5, 3),
      workStatus: "Inspection queued",
      issueType: "Overflow",
      mapPosition: [28.6812, 77.2256],
      lastUpdated: iso(5, 3),
    },
    {
      id: "DR-K",
      location: "Ward 4, Model Town",
      ward: "Ward 4",
      reason: "Low-severity section with no recent active complaint.",
      status: "Monitoring",
      priority: 34,
      consequence: 0.25,
      catchment: 0.35,
      condition: "Visually clear",
      evidenceStatus: "Recent observation available",
      lastObservation: iso(6, 1),
      workStatus: "Routine monitoring",
      issueType: "Uncertain Condition",
      mapPosition: [28.7041, 77.1927],
      lastUpdated: iso(6, 1),
    },
    {
      id: "DR-L",
      location: "Ward 22, Lajpat Nagar",
      ward: "Ward 22",
      reason: "Critical blocked inlet near school access.",
      status: "Cleaning Recommended",
      priority: 94,
      consequence: 0.95,
      catchment: 0.91,
      visibleBlockage: 100,
      condition: "Severe blockage",
      evidenceStatus: "Verified report evidence",
      lastObservation: iso(0, 9),
      workStatus: "Ready for assignment",
      issueType: "Blocked Drain",
      mapPosition: [28.5678, 77.2436],
      lastUpdated: iso(0, 9),
    },
    {
      id: "DR-M",
      location: "Ward 22, Amar Colony",
      ward: "Ward 22",
      reason: "Duplicate reports merged into one shared incident.",
      status: "Pending Review",
      priority: 67,
      consequence: 0.5,
      catchment: 0.6,
      visibleBlockage: 62,
      condition: "Partial blockage",
      evidenceStatus: "Awaiting evidence review",
      lastObservation: iso(1, 8),
      workStatus: "Completion claim submitted",
      issueType: "Partial Blockage",
      mapPosition: [28.5606, 77.2519],
      lastUpdated: iso(1, 8),
    },
    {
      id: "DR-N",
      location: "Ward 15, Okhla Phase I",
      ward: "Ward 15",
      reason: "Completed section with resolved post-rain outcome.",
      status: "Reviewed",
      priority: 61,
      consequence: 0.52,
      catchment: 0.5,
      visibleBlockage: 70,
      condition: "Clear after cleaning",
      evidenceStatus: "Accepted and archived",
      lastObservation: iso(8, 2),
      assignedCrew: "Crew Alpha",
      workStatus: "Completed - batch resolved",
      issueType: "Silt Accumulation",
      mapPosition: [28.5364, 77.2811],
      lastUpdated: iso(8, 2),
    },
    {
      id: "DR-O",
      location: "Ward 15, Jasola Vihar",
      ward: "Ward 15",
      reason:
        "Inspection found no visible blockage; retain for seasonal monitoring.",
      status: "Monitoring",
      priority: 42,
      consequence: 0.45,
      catchment: 0.48,
      condition: "Visually clear",
      evidenceStatus: "Inspection accepted",
      lastObservation: iso(4, 4),
      workStatus: "Monitoring after inspection",
      issueType: "Waterlogging",
      mapPosition: [28.5455, 77.3035],
      lastUpdated: iso(4, 4),
    },
  );

  const reports: ReportRecord[] = [
    {
      id: "RPT-1001",
      drainId: "DR-A",
      reporterName: "Citizen relay team",
      issueType: "Partial Blockage",
      ward: "Ward 12",
      location: "Hospital Road",
      description: "Blocked inlet by debris near ambulance route.",
      urgent: true,
      submittedAt: iso(2, 1),
      priority: 80,
      reasons: [
        "Visible blockage estimate 50%",
        "Catchment proxy 1.00",
        "Hospital access consequence factor",
      ],
      status: "Open",
    },
    {
      id: "RPT-1002",
      drainId: "DR-B",
      reporterName: "Resident",
      issueType: "Blocked Drain",
      ward: "Ward 12",
      location: "Shanti Nagar",
      description: "Standing water after a brief storm.",
      urgent: false,
      submittedAt: iso(4, 7),
      priority: 76.25,
      reasons: [
        "Severe blockage estimate 100%",
        "Low but relevant residential consequence",
      ],
      status: "Open",
    },
    ...[
      [
        "RPT-1003",
        "DR-A",
        "Ward 12",
        "Hospital Road",
        "Resident",
        "Partial Blockage",
        "Debris returned after rainfall.",
        79,
        "Open",
      ],
      [
        "RPT-1004",
        "DR-F",
        "Ward 7",
        "Nehru Market",
        "Market association",
        "Blocked Drain",
        "Market waste is restricting the inlet.",
        88,
        "Open",
      ],
      [
        "RPT-1005",
        "DR-F",
        "Ward 7",
        "Nehru Market",
        "Resident",
        "Waterlogging",
        "Standing water reported at the market entrance.",
        82,
        "Open",
      ],
      [
        "RPT-1006",
        "DR-G",
        "Ward 7",
        "Railway Colony",
        "Resident",
        "Silt Accumulation",
        "Cleaning appears incomplete in the submitted image.",
        78,
        "Open",
      ],
      [
        "RPT-1007",
        "DR-H",
        "Ward 19",
        "Yamuna Edge",
        "Field officer",
        "Blocked Drain",
        "Original blockage cleared and evidence accepted.",
        69,
        "Resolved",
      ],
      [
        "RPT-1008",
        "DR-I",
        "Ward 19",
        "Seelampur Crossing",
        "Resident",
        "Waterlogging",
        "Waterlogging returned during the last rain.",
        54,
        "Open",
      ],
      [
        "RPT-1009",
        "DR-I",
        "Ward 19",
        "Seelampur Crossing",
        "Resident",
        "Waterlogging",
        "Same recurring incident as RPT-1008.",
        51,
        "Duplicate",
      ],
      [
        "RPT-1010",
        "DR-J",
        "Ward 4",
        "Civil Lines",
        "Resident",
        "Overflow",
        "Overflow reported near the crossing.",
        73,
        "Open",
      ],
      [
        "RPT-1011",
        "DR-K",
        "Ward 4",
        "Model Town",
        "Field officer",
        "Uncertain Condition",
        "No active issue found during routine check.",
        34,
        "Resolved",
      ],
      [
        "RPT-1012",
        "DR-L",
        "Ward 22",
        "Lajpat Nagar",
        "School administrator",
        "Blocked Drain",
        "Blocked inlet affects school access.",
        94,
        "Open",
      ],
      [
        "RPT-1013",
        "DR-M",
        "Ward 22",
        "Amar Colony",
        "Resident",
        "Partial Blockage",
        "Standing water by the residential lane.",
        67,
        "Open",
      ],
      [
        "RPT-1014",
        "DR-M",
        "Ward 22",
        "Amar Colony",
        "Resident",
        "Partial Blockage",
        "Duplicate of the shared Amar Colony incident.",
        65,
        "Duplicate",
      ],
      [
        "RPT-1015",
        "DR-N",
        "Ward 15",
        "Okhla Phase I",
        "Field officer",
        "Silt Accumulation",
        "Section cleared through batch maintenance.",
        61,
        "Resolved",
      ],
      [
        "RPT-1016",
        "DR-O",
        "Ward 15",
        "Jasola Vihar",
        "Resident",
        "Waterlogging",
        "No visible blockage; retain seasonal watch.",
        42,
        "Resolved",
      ],
    ].map(
      (
        [
          id,
          drainId,
          ward,
          location,
          reporterName,
          issueType,
          description,
          priority,
          status,
        ],
        index,
      ) => ({
        id: String(id),
        drainId: String(drainId),
        reporterName: String(reporterName),
        issueType: String(issueType),
        ward: String(ward),
        location: String(location),
        description: String(description),
        urgent: Number(priority) >= 80,
        submittedAt: iso(index + 1, index % 8),
        priority: Number(priority),
        reasons: [
          status === "Duplicate"
            ? "Duplicate merged into the shared incident."
            : status === "Resolved"
              ? "Resolved through accepted section-level maintenance."
              : "Reason not recorded",
        ],
        status: status as ReportRecord["status"],
      }),
    ),
  ];

  const activities: ActivityEntry[] = [
    {
      id: "ACT-001",
      title: "DR-B evidence review opened",
      detail: "After-photo flagged for a location mismatch review.",
      timestamp: iso(0, 2),
      severity: "warning",
      category: "Evidence",
      reason: "Data Correction",
      user: "A. Mehta",
    },
    {
      id: "ACT-002",
      title: "Crew assignment logged",
      detail: "Crew Alpha assigned to DR-A cleaning task.",
      timestamp: iso(1, 1),
      severity: "success",
      category: "Cleaning",
      reason: "New Report",
      user: "R. Singh",
    },
    {
      id: "ACT-003",
      title: "Report triaged",
      detail: "New citizen report generated a provisional priority score.",
      timestamp: iso(2, 3),
      severity: "info",
      category: "Incidents",
      reason: "Reason not recorded",
      user: "System",
    },
  ];

  const outcomes: OutcomeRecord[] = [
    {
      id: "OUT-001",
      drainId: "DR-A",
      beforeCondition:
        "Blocked around the inlet; water collected at the hospital entry edge.",
      afterCondition: "Visually clear after cleaning; flow returned to normal.",
      postRainObservation: "Waterlogging reduced after the last rain event.",
      outcome: "Resolved",
      recommendation: "Continue routine spot checks during monsoon periods.",
      timestamp: iso(0, 8),
    },
    {
      id: "OUT-002",
      drainId: "DR-C",
      beforeCondition:
        "Evidence incomplete; underpass waterlogging remained uncertain.",
      afterCondition:
        "Flooding persisted after rainfall despite limited visible blockage evidence.",
      postRainObservation:
        "Waterlogging persists after rainfall; root cause requires further investigation.",
      outcome: "Persisted",
      recommendation:
        "Investigate downstream capacity, runoff, slope, or connected drainage infrastructure.",
      timestamp: iso(1, 5),
    },
    {
      id: "OUT-003",
      drainId: "DR-H",
      beforeCondition: "Blocked section beside the Yamuna edge.",
      afterCondition:
        "Flow restored after crew cleaning and accepted evidence.",
      postRainObservation:
        "No waterlogging observed in the next rainfall check.",
      outcome: "Resolved",
      recommendation: "Schedule monthly inspection during the monsoon.",
      timestamp: iso(2, 6),
    },
    {
      id: "OUT-004",
      drainId: "DR-I",
      beforeCondition: "No visible blockage at the inspection point.",
      afterCondition:
        "Surface remained clear but waterlogging recurred after rainfall.",
      postRainObservation:
        "Persistent waterlogging; investigate downstream capacity.",
      outcome: "Persisted",
      recommendation: "Create follow-up inspection for the connected network.",
      timestamp: iso(1, 2),
    },
    {
      id: "OUT-005",
      drainId: "DR-N",
      beforeCondition: "Silt accumulation across the covered section.",
      afterCondition:
        "Section cleared and evidence accepted in a batch review.",
      postRainObservation: "No recurring issue observed.",
      outcome: "Resolved",
      recommendation: "Retain the section in routine monitoring.",
      timestamp: iso(7, 4),
    },
    {
      id: "OUT-006",
      drainId: "DR-C",
      beforeCondition: "Evidence incomplete at the underpass.",
      afterCondition: "Condition not observed during the scheduled visit.",
      postRainObservation:
        "Follow-up could not confirm the source of waterlogging.",
      outcome: "Not Observed",
      recommendation: "Collect better evidence during the next rainfall event.",
      timestamp: iso(4, 5),
    },
  ];

  activities.push(
    {
      id: "ACT-004",
      title: "Section-level batch resolved",
      detail: "DR-N maintenance closed two eligible reports together.",
      timestamp: iso(2, 7),
      severity: "success",
      category: "Resolution batch",
      reason: "Resolved",
      user: "S. Chauhan",
    },
    {
      id: "ACT-005",
      title: "Duplicate report merged",
      detail: "RPT-1009 linked to the Seelampur shared incident.",
      timestamp: iso(1, 6),
      severity: "info",
      category: "Incidents",
      reason: "Duplicate Merged",
      user: "A. Mehta",
    },
    {
      id: "ACT-006",
      title: "Cleaning evidence returned",
      detail: "DR-G requires a clearer after image and location confirmation.",
      timestamp: iso(1, 4),
      severity: "warning",
      category: "Evidence",
      reason: "Data Correction",
      user: "R. Singh",
    },
    {
      id: "ACT-007",
      title: "Recurring waterlogging recorded",
      detail: "DR-I follow-up opened after rainfall observation.",
      timestamp: iso(2, 1),
      severity: "danger",
      category: "Outcomes",
      reason: "New Report",
      user: "System",
    },
    {
      id: "ACT-008",
      title: "Priority reclassified",
      detail: "DR-L moved to Critical after school-access consequence review.",
      timestamp: iso(3, 8),
      severity: "warning",
      category: "Priority",
      reason: "Reclassified",
      user: "S. Chauhan",
    },
    {
      id: "ACT-009",
      title: "Report status corrected",
      detail: "RPT-1011 marked resolved after a clear inspection.",
      timestamp: iso(5, 2),
      severity: "success",
      category: "Reports",
      reason: "Data Correction",
      user: "A. Mehta",
    },
    {
      id: "ACT-010",
      title: "Count change recorded",
      detail: "A category count changed without a recorded transition reason.",
      timestamp: iso(6, 3),
      severity: "info",
      category: "Analytics",
      reason: "Reason not recorded",
      user: "System",
    },
  );

  return {
    drains: drains.map((drain) => ({
      ...drain,
      evidenceId: `EVD-${drain.id}`,
    })),
    reports,
    activities,
    outcomes,
  };
};

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

function EvidenceIndexSidebar({ drains }: { drains: DrainRecord[] }) {
  const navigate = useNavigate();
  const reviewableDrains = drains.filter(
    (drain) =>
      (drain.status === "Pending Review" || drain.status === "Rework Required") &&
      !drain.workStatus?.startsWith("Returned to field app"),
  );

  return (
    <aside className="evidence-index-sidebar" aria-label="Evidence index">
      <div className="evidence-index-header">
        <ShieldCheck size={15} />
        <div>
          <strong>Evidence index</strong>
          <span>{reviewableDrains.length} pending records</span>
        </div>
      </div>
      <div className="evidence-index-list">
        {reviewableDrains.map((drain) => (
          <button
            key={drain.evidenceId ?? `EVD-${drain.id}`}
            type="button"
            className="evidence-index-item"
            onClick={() =>
              navigate(
                `/evidence?evidenceId=${encodeURIComponent(drain.evidenceId ?? `EVD-${drain.id}`)}`,
              )
            }
            title={`${drain.evidenceId ?? `EVD-${drain.id}`} · ${drain.location}`}
          >
            <span className="evidence-index-id">
              {drain.evidenceId ?? `EVD-${drain.id}`}
            </span>
            <span className="evidence-index-location">{drain.location}</span>
            <span className={`evidence-index-status ${getStatusColor(drain.status)}`}>
              {drain.status}
            </span>
          </button>
        ))}
      </div>
    </aside>
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
  const location = useLocation();
  const navigate = useNavigate();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [appState, setAppState] = useState<AppState>(() => {
    const savedValue = window.localStorage.getItem(STORAGE_KEY);
    if (savedValue) {
      try {
        const parsed = JSON.parse(savedValue) as Partial<AppState>;
        if (
          Array.isArray(parsed.drains) &&
          Array.isArray(parsed.reports) &&
          Array.isArray(parsed.activities) &&
          Array.isArray(parsed.outcomes)
        ) {
          return {
            ...(parsed as AppState),
            drains: (parsed.drains as DrainRecord[]).map((drain) => ({
              ...drain,
              evidenceId: drain.evidenceId || `EVD-${drain.id}`,
            })),
          };
        }
      } catch {
        window.localStorage.removeItem(STORAGE_KEY);
      }
    }
    return createSeedData();
  });
  const [toast, setToast] = useState<string | null>(null);
  const [submittedReportId, setSubmittedReportId] = useState<string | null>(
    null,
  );
  void submittedReportId;

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(appState));
  }, [appState]);

  useEffect(() => {
    if (!toast) return;
    const timeout = window.setTimeout(() => setToast(null), 2600);
    return () => window.clearTimeout(timeout);
  }, [toast]);

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
    note: string,
  ) => {
    updateDrainById(drainId, (drain) => ({
      ...drain,
      status: "Pending Review",
      assignedCrew: crew,
      evidenceStatus: "Temporary evidence awaiting review",
      workStatus: `Cleaning assigned · evidence pending`,
      reason: note || drain.reason,
      lastUpdated: new Date().toISOString(),
    }));
    addActivity(
      "Crew assignment recorded",
      `EVD-${drainId} · ${crew} assigned to clean ${drainId} for ${completionTime}; temporary evidence review created.`,
      "success",
    );
    setToast(`${crew} assigned to ${drainId}.`);
  };

  const handleInspectionAssignment = (
    drainId: string,
    crew: string,
    completionTime: string,
    note: string,
  ) => {
    updateDrainById(drainId, (drain) => ({
      ...drain,
      assignedCrew: crew,
      workStatus: `Inspection assigned · ${completionTime}`,
      reason: note || drain.reason,
      lastUpdated: new Date().toISOString(),
    }));
    addActivity(
      "Inspection crew assigned",
      `EVD-${drainId} · ${crew} assigned to inspect ${drainId} for ${completionTime}.`,
      "success",
    );
    setToast(`${crew} assigned to inspect ${drainId}.`);
  };

  const handleEvidenceAction = (
    drainId: string,
    action: "Accept" | "Request Rework" | "Flag Location Mismatch",
    details: string,
  ) => {
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

  const resetData = () => {
    const initialData = createSeedData();
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(initialData));
    setAppState(initialData);
    setSubmittedReportId(null);
    setToast("Initial synthetic dataset restored.");
  };

  const clearLocalData = () => {
    window.localStorage.removeItem(STORAGE_KEY);
    setAppState(createSeedData());
    setSubmittedReportId(null);
    setToast("Local data cleared and dashboard data restored.");
  };

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

  return (
    <div className={`app-shell ${sidebarCollapsed ? "sidebar-collapsed" : ""}`}>
      <aside className="sidebar">
        <div className="brand-panel">
          <img className="brand-logo" src="/logo.png" alt="DrainRank" />
          <div>
            <div className="brand-name">
              <span>Drain</span>
              <strong>Rank</strong>
            </div>
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

      {location.pathname === "/evidence" ? (
        <EvidenceIndexSidebar drains={appState.drains} />
      ) : null}

      <main className="main-panel">
        <header className="topbar">
          <div>
            <div className="eyebrow">Municipal drainage operations</div>
            <h1>Municipal Drain Intelligence</h1>
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
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
              />
            }
          />

          <Route
            path="/cleaning"
            element={
              <QueueHubPage
                initialTab="cleaning"
                drains={appState.drains}
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
              />
            }
          />

          <Route
            path="/queues"
            element={
              <QueueHubPage
                initialTab="inspection"
                drains={appState.drains}
                onInspectionAssign={handleInspectionAssignment}
                onAssign={handleCrewAssignment}
              />
            }
          />

          <Route
            path="/work-orders"
            element={<WorkOrdersPage drains={appState.drains} />}
          />

          <Route
            path="/monitoring"
            element={<Navigate to="/work-orders" replace />}
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
            path="/administration"
            element={
              <AdministrationPage
                onReset={resetData}
                onClear={clearLocalData}
              />
            }
          />
          <Route
            path="/settings"
            element={<Navigate to="/administration" replace />}
          />
        </Routes>
      </main>

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

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!form.location || !form.description || !form.ward) {
      window.alert(
        "Please provide the required location, ward, and description fields.",
      );
      return;
    }

    onSubmit({ ...form, photo: photoPreview });
    setForm({
      reporterName: "",
      issueType: "Blocked Drain",
      ward: "Ward 12",
      location: "",
      description: "",
      urgent: false,
    });
    setPhotoPreview(undefined);
  };

  const handlePhotoUpload = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => setPhotoPreview(String(reader.result ?? ""));
    reader.readAsDataURL(file);
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
            <button type="submit" className="btn-primary">
              Submit report
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
  onInspectionAssign,
  onAssign,
}: {
  initialTab: "inspection" | "cleaning";
  drains: DrainRecord[];
  onInspectionAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    note: string,
  ) => void;
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    note: string,
  ) => void;
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
                drains.filter(
                  (drain) =>
                    drain.status === "Cleaning Recommended" ||
                    drain.status === "Assigned" ||
                    drain.status === "Rework Required",
                ).filter((drain) => !drain.assignedCrew).length
              }
            </span>
          </button>
        </div>
      </div>
      {tab === "inspection" ? (
        <InspectionQueuePage drains={drains} onAssign={onInspectionAssign} />
      ) : (
        <CleaningQueuePage drains={drains} onAssign={onAssign} />
      )}
    </div>
  );
}

void ReportPage;

function InspectionQueuePage({
  drains,
  onAssign,
}: {
  drains: DrainRecord[];
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
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

  const submit = () => {
    onSubmit({
      drainId: drain.id,
      observedCondition,
      estimatedBlockage,
      notes,
      photo,
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
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (!file) return;
                const reader = new FileReader();
                reader.onload = () => setPhoto(String(reader.result ?? ""));
                reader.readAsDataURL(file);
              }}
            />
          </label>

          <div className="button-row full-width">
            <button type="button" className="btn-primary" onClick={submit}>
              Submit inspection
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
  onAssign,
}: {
  drains: DrainRecord[];
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    note: string,
  ) => void;
}) {
  const [selectedDrainId, setSelectedDrainId] = useState<string | null>(null);
  const cleaningDrains = drains.filter(
    (drain) =>
      drain.status === "Cleaning Recommended" ||
      drain.status === "Assigned" ||
      drain.status === "Rework Required",
  ).filter((drain) => !drain.assignedCrew);

  return (
    <div className="page-stack">
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
                  <td>{drain.assignedCrew ?? "Unassigned"}</td>
                  <td>
                    <button
                      type="button"
                      className="btn-secondary"
                      onClick={() => setSelectedDrainId(drain.id)}
                    >
                      Assign Crew
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
          onClose={() => setSelectedDrainId(null)}
          onAssign={onAssign}
        />
      ) : null}
    </div>
  );
}

function AssignCrewModal({
  drainId,
  onClose,
  onAssign,
}: {
  drainId: string;
  onClose: () => void;
  onAssign: (
    drainId: string,
    crew: string,
    completionTime: string,
    note: string,
  ) => void;
}) {
  const [crew, setCrew] = useState("Crew Alpha");
  const [completionTime, setCompletionTime] = useState("Today 16:00");
  const [note, setNote] = useState("");

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
          <label>
            Crew
            <select
              value={crew}
              onChange={(event) => setCrew(event.target.value)}
            >
              <option>Crew Alpha</option>
              <option>Crew Bravo</option>
              <option>Crew Charlie</option>
            </select>
          </label>

          <label>
            Target completion time
            <input
              value={completionTime}
              onChange={(event) => setCompletionTime(event.target.value)}
            />
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
              onClick={() => {
                onAssign(drainId, crew, completionTime, note);
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

function EvidenceReviewPage({
  drains,
  onAction,
}: {
  drains: DrainRecord[];
  onAction: (
    drainId: string,
    action: "Accept" | "Request Rework" | "Flag Location Mismatch",
    details: string,
  ) => void;
}) {
  const [searchParams, setSearchParams] = useSearchParams();
  const selectedEvidenceId = searchParams.get("evidenceId");
  const reviewQueue = drains.filter(
    (drain) =>
      (drain.status === "Pending Review" || drain.status === "Rework Required") &&
      !drain.workStatus?.startsWith("Returned to field app"),
  );
  const selectedDrain = reviewQueue.find(
    (drain) =>
      (drain.evidenceId ?? `EVD-${drain.id}`) === selectedEvidenceId,
  );

  if (!reviewQueue.length) {
    return (
      <div className="page-stack">
        <div className="panel empty-state">
          <AlertTriangle size={30} />
          <h2>No evidence review actions pending.</h2>
          <p>All completion claims are currently clear.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack evidence-review-page">
      {!selectedDrain ? (
        <div className="panel empty-state evidence-selection-empty">
          <ShieldCheck size={30} />
          <h2>Select an evidence record</h2>
          <p>Choose an evidence ID from the index to view its review details.</p>
        </div>
      ) : (
      [selectedDrain].map((drain) => (
        <div key={drain.id} className="panel evidence-card">
          <div className="panel-header">
            <div>
              <h2>{drain.evidenceId ?? `EVD-${drain.id}`}</h2>
              <span className="panel-note">{drain.id} · {drain.location}</span>
            </div>
            <span className={`status-chip ${getStatusColor(drain.status)}`}>
              {drain.status}
            </span>
          </div>

          <div className="evidence-grid">
            <div className="evidence-image placeholder">Before image</div>
            <div className="evidence-image placeholder">After image</div>
          </div>

          <div className="evidence-meta-list">
            <div>
              <span>Location</span>
              <strong>{drain.location}</strong>
            </div>
            <div>
              <span>Submitted timestamp</span>
              <strong>{formatDate(drain.lastObservation)}</strong>
            </div>
            <div>
              <span>Work notes</span>
              <strong>{drain.reason}</strong>
            </div>
            <div>
              <span>Evidence status</span>
              <strong>{drain.evidenceStatus}</strong>
            </div>
            <div>
              <span>Reviewer notes</span>
              <strong>
                Location mismatch review is flagged for checking the field
                trace.
              </strong>
            </div>
          </div>

          <div className="button-row">
            <button
              type="button"
              className="btn-primary"
              onClick={() => {
                const confirmed = window.confirm(
                  `Accept evidence for ${drain.id}?`,
                );
                if (confirmed) {
                  onAction(drain.id, "Accept", "Accepted after review.");
                  setSearchParams({});
                }
              }}
            >
              Accept Evidence
            </button>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => {
                const confirmed = window.confirm(
                  `Request rework for ${drain.evidenceId ?? `EVD-${drain.id}`} and return it to the cleaning queue?`,
                );
                if (confirmed) {
                  onAction(
                    drain.id,
                    "Request Rework",
                    "Rework requested because evidence quality is insufficient.",
                  );
                  setSearchParams({});
                }
              }}
            >
              Request Rework
            </button>
            <button
              type="button"
              className="btn-secondary alt"
              onClick={() => {
                const confirmed = window.confirm(
                  `Send ${drain.evidenceId ?? `EVD-${drain.id}`} back to the field app for location clarification?`,
                );
                if (confirmed) {
                  onAction(
                    drain.id,
                    "Flag Location Mismatch",
                    "Location mismatch warning: field evidence did not match the assigned drain location.",
                  );
                  setSearchParams({});
                }
              }}
            >
              Flag Location Mismatch
            </button>
          </div>
        </div>
      ))
      )}
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
  const assignedTeams = [...new Set(
    workOrders
      .map((drain) => drain.assignedCrew)
      .filter((crew): crew is string => Boolean(crew)),
  )].sort((first, second) => first.localeCompare(second));
  const normalizedTeamSearch = teamSearch.trim().toLowerCase();
  const matchingTeams = assignedTeams.filter((assignedTeam) =>
    assignedTeam.toLowerCase().includes(normalizedTeamSearch),
  );
  const teamWorkload = workOrders.filter((drain) =>
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
    ) return false;
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
                  <td>{drain.assignedCrew ?? "Unassigned"}</td>
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
    value: filteredReports.filter((report) => report.issueType === issueType).length,
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
            <p className="panel-note">Operational records and website activity history.</p>
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
                <span className="panel-note">Filtered reports by reported problem</span>
              </div>
            </div>
            <div className="chart-wrap small">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={issueTypeCounts}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="name" interval={0} angle={-18} textAnchor="end" height={48} />
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
                <span className="panel-note">Open, duplicate, and resolved records</span>
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
              <span className="panel-note">{filteredReports.length} matching records</span>
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
              <span className="panel-note">Combined website actions and task transitions</span>
            </div>
            <div className="reports-log-actions">
              <span className="panel-note">{filteredActivities.length} entries</span>
              <button type="button" className="btn-secondary" onClick={exportLogCsv}>
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
                  <small>{formatDate(activity.timestamp)} · {activity.user ?? "User not recorded"}</small>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function AdministrationPage({
  onReset,
  onClear,
}: {
  onReset: () => void;
  onClear: () => void;
}) {
  const [accountName, setAccountName] = useState("Aarav Mehta");
  const [accountEmail, setAccountEmail] = useState("aarav.mehta@municipal.gov.in");
  const [phone, setPhone] = useState("+91 98765 43210");
  const [notifications, setNotifications] = useState(true);
  const [digest, setDigest] = useState(true);

  return (
    <div className="page-stack settings-page">
      <div className="settings-heading">
        <div>
          <span className="eyebrow">Workspace settings</span>
          <h2>Administration</h2>
          <p className="panel-note">
            Manage your municipal account, access roles, and workspace preferences.
          </p>
        </div>
        <Settings size={24} color="#215B63" />
      </div>

      <div className="settings-grid">
        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Account details</h3>
              <p className="panel-note">Your profile used for municipal operations.</p>
            </div>
            <UsersRound size={20} color="#215B63" />
          </div>
          <div className="settings-form-grid">
            <label>
              Full name
              <input value={accountName} onChange={(event) => setAccountName(event.target.value)} />
            </label>
            <label>
              Official email
              <span className="settings-input-icon">
                <Mail size={15} />
                <input type="email" value={accountEmail} onChange={(event) => setAccountEmail(event.target.value)} />
              </span>
            </label>
            <label>
              Phone number
              <input value={phone} onChange={(event) => setPhone(event.target.value)} />
            </label>
            <label>
              Current role
              <input value="Ward Officer" readOnly />
            </label>
          </div>
          <div className="settings-inline-note">
            <ShieldCheck size={16} />
            <span>Account verification and password management will be connected to the backend login service.</span>
          </div>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Municipal workspace</h3>
              <p className="panel-note">Operating scope and organisational defaults.</p>
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
              <p className="panel-note">Review access responsibilities for the operations team.</p>
            </div>
            <button type="button" className="btn-secondary" disabled title="Available when user administration is connected to the backend">
              <UsersRound size={15} /> Add user
            </button>
          </div>
          <div className="user-role-table">
            <div className="user-role-row user-role-header">
              <span>User</span><span>Department</span><span>Role</span><span>Access</span>
            </div>
            <div className="user-role-row">
              <span><strong>{accountName}</strong><small>{accountEmail}</small></span>
              <span>Drainage Operations</span><span>Ward Officer</span><span className="status-chip success">Manage assigned ward</span>
            </div>
            <div className="user-role-row">
              <span><strong>Priya Sharma</strong><small>priya.sharma@municipal.gov.in</small></span>
              <span>Field Inspection</span><span>Inspection Supervisor</span><span className="status-chip info">Inspection and evidence</span>
            </div>
            <div className="user-role-row">
              <span><strong>Rohan Verma</strong><small>rohan.verma@municipal.gov.in</small></span>
              <span>Maintenance</span><span>Operations Manager</span><span className="status-chip warning">Queues and work orders</span>
            </div>
          </div>
          <div className="role-permissions">
            <span className="label">Role permissions</span>
            <span>Reports</span><span>Map</span><span>Queues</span><span>Evidence review</span><span>Administration</span>
          </div>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Notifications</h3>
              <p className="panel-note">Choose which operational updates appear in your workspace.</p>
            </div>
            <Bell size={20} color="#215B63" />
          </div>
          <label className="settings-toggle">
            <span><strong>Priority changes</strong><small>Notify when an issue is escalated or reclassified.</small></span>
            <input type="checkbox" checked={notifications} onChange={(event) => setNotifications(event.target.checked)} />
          </label>
          <label className="settings-toggle">
            <span><strong>Daily operations summary</strong><small>Receive a summary of queues, reports, and evidence.</small></span>
            <input type="checkbox" checked={digest} onChange={(event) => setDigest(event.target.checked)} />
          </label>
        </section>

        <section className="panel settings-panel">
          <div className="settings-section-heading">
            <div>
              <h3>Data and session</h3>
              <p className="panel-note">Local prototype data controls.</p>
            </div>
            <ShieldAlert size={20} color="#D97706" />
          </div>
          <div className="settings-actions">
            <button type="button" className="btn-secondary" onClick={() => {
              if (window.confirm("Reset all local records to the initial synthetic dataset?")) onReset();
            }}>
              <RefreshCw size={16} /> Reset initial data
            </button>
            <button type="button" className="btn-secondary alt" onClick={() => {
              if (window.confirm("Clear all local data? This will restore the seeded scenario.")) onClear();
            }}>
              <Trash2 size={16} /> Clear local data
            </button>
          </div>
          <div className="settings-logout">
            <div>
              <strong>Sign out</strong>
              <small>Logout will be enabled after backend authentication is added.</small>
            </div>
            <button type="button" className="btn-secondary" disabled title="Login and logout will be connected to the backend">
              <LogOut size={16} /> Logout
            </button>
          </div>
        </section>
      </div>
    </div>
  );
}

export default App;
