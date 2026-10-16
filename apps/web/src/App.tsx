import { useEffect, useMemo, useState } from 'react';
import { BrowserRouter, NavLink, Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { MapContainer, CircleMarker, TileLayer } from 'react-leaflet';
import {
  AlertTriangle,
  Bell,
  CheckCheck,
  ChevronRight,
  ClipboardList,
  Download,
  Eye,
  FileText,
  Gauge,
  ListChecks,
  MapPinned,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  UsersRound,
  Wrench,
} from 'lucide-react';

type DrainStatus =
  | 'Cleaning Recommended'
  | 'Inspection Required'
  | 'Monitoring'
  | 'Assigned'
  | 'Pending Review'
  | 'Reviewed'
  | 'Rework Required';

type OutcomeType = 'Resolved' | 'Partially Resolved' | 'Persisted' | 'Not Observed';

type ActivitySeverity = 'info' | 'warning' | 'success' | 'danger';

interface DrainRecord {
  id: string;
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
  status: 'Open' | 'Duplicate' | 'Resolved';
}

interface ActivityEntry {
  id: string;
  title: string;
  detail: string;
  timestamp: string;
  severity: ActivitySeverity;
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

const STORAGE_KEY = 'drainrank-demo-v1';
const navItems = [
  { label: 'Overview', path: '/overview', icon: Gauge },
  { label: 'Complaints & Incidents', path: '/complaints', icon: ListChecks },
  { label: 'Drain Map', path: '/map', icon: MapPinned },
  { label: 'Report a Problem', path: '/report', icon: FileText },
  { label: 'Inspection Queue', path: '/inspection', icon: Search },
  { label: 'Cleaning Queue', path: '/cleaning', icon: Wrench },
  { label: 'Work Orders', path: '/work-orders', icon: ClipboardList },
  { label: 'Monitoring', path: '/monitoring', icon: Eye },
  { label: 'Evidence Review', path: '/evidence', icon: ShieldCheck },
  { label: 'Outcome Intelligence', path: '/outcomes', icon: Bell },
  { label: 'Reports', path: '/reports', icon: Download },
  { label: 'Administration', path: '/administration', icon: UsersRound },
];

const createId = (prefix: string) => `${prefix}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;

const formatDate = (value: string) => new Date(value).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });

const createSeedData = (): AppState => {
  const now = new Date();
  const iso = (daysAgo: number, hoursAgo = 0) => new Date(now.getTime() - (daysAgo * 24 + hoursAgo) * 60 * 60 * 1000).toISOString();

  const drains: DrainRecord[] = [
    {
      id: 'DR-A',
      location: 'Ward 12, Hospital Road',
      ward: 'Ward 12',
      reason: 'Partial blockage near critical hospital access',
      status: 'Cleaning Recommended',
      priority: 80,
      consequence: 1,
      catchment: 1,
      visibleBlockage: 50,
      condition: 'Partially blocked',
      evidenceStatus: 'Photo review complete',
      lastObservation: iso(1, 2),
      workStatus: 'Ready for assignment',
      issueType: 'Partial Blockage',
      mapPosition: [28.6469, 77.4316],
      lastUpdated: iso(1, 2),
    },
    {
      id: 'DR-B',
      location: 'Ward 12, Shanti Nagar',
      ward: 'Ward 12',
      reason: 'Severe visible blockage in a residential area',
      status: 'Pending Review',
      priority: 76.25,
      consequence: 0.4,
      catchment: 0.75,
      visibleBlockage: 100,
      condition: 'Severe blockage',
      evidenceStatus: 'After photo submitted',
      lastObservation: iso(0, 4),
      assignedCrew: 'Crew Alpha',
      workStatus: 'Completion claim submitted',
      issueType: 'Blocked Drain',
      mapPosition: [28.6412, 77.428],
      lastUpdated: iso(0, 4),
    },
    {
      id: 'DR-C',
      location: 'Ward 12, Central Underpass',
      ward: 'Ward 12',
      reason: 'Potentially high-consequence waterlogging location with insufficient current evidence',
      status: 'Inspection Required',
      priority: 81,
      consequence: 0.8,
      catchment: 0.6,
      evidenceUncertainty: 1,
      condition: 'Evidence uncertain',
      evidenceStatus: 'Awaiting field inspection',
      lastObservation: iso(2, 5),
      workStatus: 'Inspection queued',
      issueType: 'Waterlogging',
      mapPosition: [28.6462, 77.4362],
      lastUpdated: iso(2, 5),
    },
    {
      id: 'DR-D',
      location: 'Ward 12, Green Lane',
      ward: 'Ward 12',
      reason: 'Visible blockage but lower documented consequence',
      status: 'Cleaning Recommended',
      priority: 63.6,
      consequence: 0.3,
      catchment: 0.46,
      visibleBlockage: 100,
      condition: 'Visible blockage',
      evidenceStatus: 'Usable evidence available',
      lastObservation: iso(1, 9),
      workStatus: 'Scheduled',
      issueType: 'Blocked Drain',
      mapPosition: [28.6388, 77.4269],
      lastUpdated: iso(1, 9),
    },
    {
      id: 'DR-E',
      location: 'Ward 12, Park Lane',
      ward: 'Ward 12',
      reason: 'Latest observation does not show visible blockage; future problems remain possible',
      status: 'Monitoring',
      priority: 18,
      consequence: 0.2,
      catchment: 0.42,
      condition: 'Visually clear',
      evidenceStatus: 'Recent usable image - clear',
      lastObservation: iso(0, 1),
      workStatus: 'Monitoring',
      issueType: 'Uncertain Condition',
      mapPosition: [28.6405, 77.422],
      lastUpdated: iso(0, 1),
    },
  ];

  const reports: ReportRecord[] = [
    {
      id: 'RPT-1001',
      drainId: 'DR-A',
      reporterName: 'Citizen relay team',
      issueType: 'Partial Blockage',
      ward: 'Ward 12',
      location: 'Hospital Road',
      description: 'Blocked inlet by debris near ambulance route.',
      urgent: true,
      submittedAt: iso(2, 1),
      priority: 80,
      reasons: ['Visible blockage estimate 50%', 'Catchment proxy 1.00', 'Hospital access consequence factor'],
      status: 'Open',
    },
    {
      id: 'RPT-1002',
      drainId: 'DR-B',
      reporterName: 'Resident',
      issueType: 'Blocked Drain',
      ward: 'Ward 12',
      location: 'Shanti Nagar',
      description: 'Standing water after a brief storm.',
      urgent: false,
      submittedAt: iso(4, 7),
      priority: 76.25,
      reasons: ['Severe blockage estimate 100%', 'Low but relevant residential consequence'],
      status: 'Open',
    },
  ];

  const activities: ActivityEntry[] = [
    {
      id: createId('ACT'),
      title: 'DR-B evidence review opened',
      detail: 'After-photo flagged for a location mismatch review.',
      timestamp: iso(0, 2),
      severity: 'warning',
    },
    {
      id: createId('ACT'),
      title: 'Crew assignment logged',
      detail: 'Crew Alpha assigned to DR-A cleaning task.',
      timestamp: iso(1, 1),
      severity: 'success',
    },
    {
      id: createId('ACT'),
      title: 'Synthetic report triaged',
      detail: 'New citizen report generated a provisional priority score.',
      timestamp: iso(2, 3),
      severity: 'info',
    },
  ];

  const outcomes: OutcomeRecord[] = [
    {
      id: createId('OUT'),
      drainId: 'DR-A',
      beforeCondition: 'Blocked around the inlet; water collected at the hospital entry edge.',
      afterCondition: 'Visually clear after cleaning; flow returned to normal.',
      postRainObservation: 'Waterlogging reduced after the last rain event.',
      outcome: 'Resolved',
      recommendation: 'Continue routine spot checks during monsoon periods.',
      timestamp: iso(0, 8),
    },
    {
      id: createId('OUT'),
      drainId: 'DR-C',
      beforeCondition: 'Evidence incomplete; underpass waterlogging remained uncertain.',
      afterCondition: 'Flooding persisted after rainfall despite limited visible blockage evidence.',
      postRainObservation: 'Waterlogging persists after rainfall; root cause requires further investigation.',
      outcome: 'Persisted',
      recommendation: 'Investigate downstream capacity, runoff, slope, or connected drainage infrastructure.',
      timestamp: iso(1, 5),
    },
  ];

  return { drains, reports, activities, outcomes };
};

const getStatusColor = (status: DrainStatus) => {
  switch (status) {
    case 'Cleaning Recommended':
    case 'Assigned':
      return 'bg-red-100 text-red-700 border-red-200';
    case 'Inspection Required':
    case 'Pending Review':
      return 'bg-amber-100 text-amber-700 border-amber-200';
    case 'Monitoring':
    case 'Reviewed':
      return 'bg-emerald-100 text-emerald-700 border-emerald-200';
    case 'Rework Required':
      return 'bg-rose-100 text-rose-700 border-rose-200';
    default:
      return 'bg-slate-100 text-slate-700 border-slate-200';
  }
};

const getOutcomeColor = (outcome: OutcomeType) => {
  switch (outcome) {
    case 'Resolved':
      return 'bg-emerald-100 text-emerald-700';
    case 'Partially Resolved':
      return 'bg-amber-100 text-amber-700';
    case 'Persisted':
      return 'bg-red-100 text-red-700';
    default:
      return 'bg-slate-100 text-slate-700';
  }
};

const getPriorityColor = (score: number) => {
  if (score >= 75) return 'text-red-600';
  if (score >= 60) return 'text-amber-600';
  return 'text-emerald-600';
};

const getMapColor = (status: DrainStatus) => {
  if (status === 'Cleaning Recommended' || status === 'Assigned' || status === 'Rework Required') return '#ef4444';
  if (status === 'Inspection Required' || status === 'Pending Review') return '#f59e0b';
  if (status === 'Monitoring' || status === 'Reviewed') return '#10b981';
  return '#0f172a';
};

const buildPriorityReason = (issueType: string, urgent: boolean) => {
  const base = {
    'Blocked Drain': 72,
    'Partial Blockage': 66,
    Waterlogging: 74,
    Overflow: 80,
    'Uncertain Condition': 58,
  } as Record<string, number>;

  const score = Math.min(99, base[issueType] ?? 60 + (urgent ? 12 : 0));
  const reasons = [
    `${issueType} is a live civic asset risk.`,
    urgent ? 'Urgent status adds an escalation factor.' : 'Routine verification continues on the standard queue.',
    'Demo assessment uses synthetic scoring and is not a field-validated model.',
  ];
  return { score, reasons };
};

function App() {
  return (
    <BrowserRouter>
      <DrainRankApp />
    </BrowserRouter>
  );
}

function DrainRankApp() {
  const navigate = useNavigate();
  const [appState, setAppState] = useState<AppState>(() => {
    const savedValue = window.localStorage.getItem(STORAGE_KEY);
    if (savedValue) {
      try {
        const parsed = JSON.parse(savedValue) as Partial<AppState>;
        if (Array.isArray(parsed.drains) && Array.isArray(parsed.reports) && Array.isArray(parsed.activities) && Array.isArray(parsed.outcomes)) {
          return parsed as AppState;
        }
      } catch {
        window.localStorage.removeItem(STORAGE_KEY);
      }
    }
    return createSeedData();
  });
  const [toast, setToast] = useState<string | null>(null);
  const [submittedReportId, setSubmittedReportId] = useState<string | null>(null);
  const [demoHighlight, setDemoHighlight] = useState<string | null>(null);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(appState));
  }, [appState]);

  useEffect(() => {
    if (!toast) return;
    const timeout = window.setTimeout(() => setToast(null), 2600);
    return () => window.clearTimeout(timeout);
  }, [toast]);

  const addActivity = (title: string, detail: string, severity: ActivitySeverity = 'info') => {
    setAppState((previous) => ({
      ...previous,
      activities: [
        {
          id: createId('ACT'),
          title,
          detail,
          timestamp: new Date().toISOString(),
          severity,
        },
        ...previous.activities,
      ].slice(0, 12),
    }));
  };

  const updateDrainById = (drainId: string, nextState: Partial<DrainRecord> | ((previous: DrainRecord) => DrainRecord)) => {
    setAppState((previous) => ({
      ...previous,
      drains: previous.drains.map((drain) => {
        if (drain.id !== drainId) return drain;
        const nextDrain = typeof nextState === 'function' ? nextState(drain) : { ...drain, ...nextState };
        return nextDrain;
      }),
    }));
  };

  const submitCitizenReport = (form: ReportForm) => {
    const assessment = buildPriorityReason(form.issueType, form.urgent);
    const reportId = createId('RPT');
    const fullDrainId = `DR-${String(Math.floor(Math.random() * 999 + 1)).padStart(3, '0')}`;
    const syntheticDrain: DrainRecord = {
      id: fullDrainId,
      location: form.location || `${form.ward}, ${form.location || 'New report area'}`,
      ward: form.ward,
      reason: `${form.issueType} reported in ${form.location || 'the ward'} with ${form.urgent ? 'urgent civic priority' : 'standard review priority'}.`,
      status: form.urgent ? 'Cleaning Recommended' : 'Monitoring',
      priority: assessment.score,
      consequence: 0.7,
      catchment: 0.8,
      visibleBlockage: form.issueType === 'Blocked Drain' ? 85 : form.issueType === 'Partial Blockage' ? 52 : 35,
      evidenceUncertainty: form.issueType === 'Uncertain Condition' ? 1 : 0.4,
      condition: form.issueType === 'Waterlogging' ? 'Standing water observed' : 'New report received',
      evidenceStatus: 'Report submitted; awaiting verification',
      lastObservation: new Date().toISOString(),
      issueType: form.issueType,
      mapPosition: [28.642 + Math.random() * 0.03, 77.423 + Math.random() * 0.04],
      lastUpdated: new Date().toISOString(),
    };

    const report: ReportRecord = {
      id: reportId,
      drainId: fullDrainId,
      reporterName: form.reporterName || 'Anonymous citizen',
      issueType: form.issueType,
      ward: form.ward,
      location: form.location,
      description: form.description,
      urgent: form.urgent,
      photo: form.photo,
      submittedAt: new Date().toISOString(),
      priority: assessment.score,
      reasons: assessment.reasons,
      status: 'Open',
    };

    setAppState((previous) => ({
      ...previous,
      drains: [syntheticDrain, ...previous.drains],
      reports: [report, ...previous.reports],
      activities: [
        {
          id: createId('ACT'),
          title: 'Citizen report submitted',
          detail: `${reportId} created for ${form.location}.`,
          timestamp: new Date().toISOString(),
          severity: 'info' as const,
        },
        ...previous.activities,
      ].slice(0, 12),
    }));
    setSubmittedReportId(reportId);
    setToast('New report added to the municipal dashboard.');
    navigate('/report');
  };

  const handleInspectionSubmit = (payload: InspectionForm) => {
    const status: DrainStatus = payload.observedCondition === 'Visually Clear' ? 'Monitoring' : payload.estimatedBlockage >= 80 ? 'Cleaning Recommended' : 'Inspection Required';
    updateDrainById(payload.drainId, (drain) => ({
      ...drain,
      status,
      visibleBlockage: payload.estimatedBlockage,
      condition: payload.observedCondition,
      evidenceStatus: 'Inspection complete',
      lastObservation: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
      reason: payload.notes || drain.reason,
      workStatus: status === 'Monitoring' ? 'Monitoring after inspection' : 'Awaiting queue update',
    }));
    addActivity('Inspection submitted', `Updated ${payload.drainId} with a ${payload.observedCondition.toLowerCase()} evaluation.`, 'success');
    setToast('Inspection saved and queue updated.');
  };

  const handleCrewAssignment = (drainId: string, crew: string, completionTime: string, note: string) => {
    updateDrainById(drainId, (drain) => ({
      ...drain,
      status: 'Assigned',
      assignedCrew: crew,
      workStatus: 'Work assigned',
      reason: note || drain.reason,
      lastUpdated: new Date().toISOString(),
    }));
    addActivity('Crew assignment recorded', `${crew} assigned to ${drainId} for ${completionTime}.`, 'success');
    setToast(`${crew} assigned to ${drainId}.`);
  };

  const handleEvidenceAction = (drainId: string, action: 'Accept' | 'Request Rework' | 'Flag Location Mismatch', details: string) => {
    updateDrainById(drainId, (drain) => {
      if (action === 'Accept') {
        return {
          ...drain,
          status: 'Monitoring',
          evidenceStatus: 'Reviewed and accepted',
          workStatus: 'Accepted after evidence review',
          lastUpdated: new Date().toISOString(),
        };
      }
      if (action === 'Request Rework') {
        return {
          ...drain,
          status: 'Rework Required',
          evidenceStatus: 'Rework required',
          workStatus: 'Returned to cleaning queue',
          lastUpdated: new Date().toISOString(),
        };
      }
      return {
        ...drain,
        status: 'Pending Review',
        evidenceStatus: 'Location mismatch flagged',
        workStatus: 'Review paused pending clarification',
        lastUpdated: new Date().toISOString(),
      };
    });
    const actionTitle = action === 'Accept' ? 'Evidence accepted' : action === 'Request Rework' ? 'Rework requested' : 'Location mismatch flagged';
    addActivity(actionTitle, `${drainId} — ${details}`, action === 'Accept' ? 'success' : 'warning');
    setToast(`${actionTitle} for ${drainId}.`);
  };

  const handlePostRainObservation = (payload: { drainId: string; beforeCondition: string; afterCondition: string; outcome: OutcomeType; recommendation: string; postRainObservation: string }) => {
    const newOutcome: OutcomeRecord = {
      id: createId('OUT'),
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
          id: createId('ACT'),
          title: 'Post-rain outcome added',
          detail: `${payload.drainId} updated with a ${payload.outcome.toLowerCase()} outcome record.`,
          timestamp: new Date().toISOString(),
          severity: 'info' as const,
        },
        ...previous.activities,
      ].slice(0, 12),
    }));
    setToast('Outcome observation saved and dashboard updated.');
  };

  const resetDemoData = () => {
    setAppState(createSeedData());
    setSubmittedReportId(null);
    setDemoHighlight(null);
    setToast('Demo data restored.');
  };

  const clearLocalData = () => {
    window.localStorage.removeItem(STORAGE_KEY);
    setAppState(createSeedData());
    setSubmittedReportId(null);
    setDemoHighlight(null);
    setToast('Local data cleared and seeded demo restored.');
  };

  const runDemoScenario = () => {
    setDemoHighlight('DR-A');
    navigate('/overview');
    setToast('Demo mode: DR-A highlighted for high-priority cleaning review.');
  };

  const totalDrains = appState.drains.length;
  const openIncidents = appState.drains.filter((drain) => drain.status !== 'Monitoring' && drain.status !== 'Reviewed').length;
  const cleaningRecommended = appState.drains.filter((drain) => drain.status === 'Cleaning Recommended' || drain.status === 'Assigned').length;
  const inspectionRequired = appState.drains.filter((drain) => drain.status === 'Inspection Required' || drain.status === 'Pending Review').length;
  const pendingEvidence = appState.drains.filter((drain) => drain.status === 'Pending Review').length;
  const wardOptions = ['All', ...new Set(appState.drains.map((drain) => drain.ward))];

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-panel">
          <div className="brand-mark">D</div>
          <div>
            <div className="brand-name">DrainRank</div>
            <div className="brand-subtitle">From Citizen Report to Verified Outcome</div>
          </div>
        </div>

        <nav className="nav-stack">
          {navItems.map(({ label, path, icon: Icon }) => (
            <NavLink
              key={path}
              to={path}
              className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
            >
              <Icon size={16} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <div>
            <div className="eyebrow">Synthetic civic operations demo</div>
            <h1>Municipal Drain Intelligence</h1>
          </div>
          <div className="topbar-actions">
            <div className="demo-badge">Demo Mode</div>
            <button type="button" className="btn-primary" onClick={runDemoScenario}>
              Run Demo Scenario
            </button>
          </div>
        </header>

        <Routes>
          <Route
            path="/"
            element={<Navigate to="/overview" replace />}
          />

          <Route
            path="/overview"
            element={
              <OverviewPage
                drains={appState.drains}
                activities={appState.activities}
                totalDrains={totalDrains}
                openIncidents={openIncidents}
                cleaningRecommended={cleaningRecommended}
                inspectionRequired={inspectionRequired}
                pendingEvidence={pendingEvidence}
                navigate={navigate}
                highlightId={demoHighlight}
              />
            }
          />

          <Route
            path="/map"
            element={<MapPage drains={appState.drains} />}
          />

          <Route
            path="/complaints"
            element={<ComplaintsPage reports={appState.reports} drains={appState.drains} />}
          />

          <Route
            path="/report"
            element={<ReportPage onSubmit={submitCitizenReport} submittedReportId={submittedReportId} />}
          />

          <Route
            path="/inspection"
            element={<InspectionQueuePage drains={appState.drains} onSubmit={handleInspectionSubmit} />}
          />

          <Route
            path="/cleaning"
            element={<CleaningQueuePage drains={appState.drains} onAssign={handleCrewAssignment} />}
          />

          <Route
            path="/work-orders"
            element={<WorkOrdersPage drains={appState.drains} />}
          />

          <Route
            path="/monitoring"
            element={<MonitoringPage drains={appState.drains} onRecordObservation={handlePostRainObservation} />}
          />

          <Route
            path="/evidence"
            element={<EvidenceReviewPage drains={appState.drains} onAction={handleEvidenceAction} />}
          />

          <Route
            path="/outcomes"
            element={<OutcomePage drains={appState.drains} outcomes={appState.outcomes} onAddOutcome={handlePostRainObservation} />}
          />

          <Route
            path="/reports"
            element={<ReportsPage drains={appState.drains} reports={appState.reports} outcomes={appState.outcomes} wardOptions={wardOptions} />}
          />

          <Route
            path="/administration"
            element={<AdministrationPage onReset={resetDemoData} onClear={clearLocalData} />}
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
  navigate,
}: {
  label: string;
  value: number | string;
  route: string;
  accent: string;
  navigate: (path: string) => void;
}) {
  return (
    <button type="button" className={`metric-card ${accent}`} onClick={() => navigate(route)}>
      <div className="metric-label">{label}</div>
      <div className="metric-value">{value}</div>
      <div className="metric-link">
        View queue <ChevronRight size={14} />
      </div>
    </button>
  );
}

function OverviewPage({
  drains,
  activities,
  totalDrains,
  openIncidents,
  cleaningRecommended,
  inspectionRequired,
  pendingEvidence,
  navigate,
  highlightId,
}: {
  drains: DrainRecord[];
  activities: ActivityEntry[];
  totalDrains: number;
  openIncidents: number;
  cleaningRecommended: number;
  inspectionRequired: number;
  pendingEvidence: number;
  navigate: (path: string) => void;
  highlightId: string | null;
}) {
  const priorityDistribution = [
    { name: 'Critical', value: drains.filter((drain) => drain.priority >= 75).length },
    { name: 'Elevated', value: drains.filter((drain) => drain.priority >= 60 && drain.priority < 75).length },
    { name: 'Monitoring', value: drains.filter((drain) => drain.priority < 60).length },
  ];

  const statusDistribution = [
    { name: 'Cleaning', value: drains.filter((drain) => drain.status.includes('Cleaning') || drain.status === 'Assigned').length },
    { name: 'Inspection', value: drains.filter((drain) => drain.status.includes('Inspection') || drain.status === 'Pending Review').length },
    { name: 'Monitoring', value: drains.filter((drain) => drain.status === 'Monitoring' || drain.status === 'Reviewed').length },
  ];

  const topIncidents = [...drains].sort((a, b) => b.priority - a.priority).slice(0, 4);

  return (
    <div className="page-stack">
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <MetricCard label="Total Drains" value={totalDrains} route="/map" accent="teal" navigate={navigate} />
        <MetricCard label="Open Incidents" value={openIncidents} route="/inspection" accent="amber" navigate={navigate} />
        <MetricCard label="Cleaning Recommended" value={cleaningRecommended} route="/cleaning" accent="red" navigate={navigate} />
        <MetricCard label="Inspection Required" value={inspectionRequired} route="/inspection" accent="amber" navigate={navigate} />
        <MetricCard label="Pending Evidence Reviews" value={pendingEvidence} route="/evidence" accent="slate" navigate={navigate} />
      </div>

      <div className="cards-grid two-col">
        <div className="panel">
          <div className="panel-header">
            <h2>Priority distribution</h2>
            <span className="panel-note">Synthetic scoring only</span>
          </div>
          <div className="chart-wrap small">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={priorityDistribution}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis dataKey="name" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="value" radius={[10, 10, 0, 0]} fill="#0f766e" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="panel">
          <div className="panel-header">
            <h2>Task status</h2>
            <span className="panel-note">Live queue mix</span>
          </div>
          <div className="chart-wrap small">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={statusDistribution} dataKey="value" nameKey="name" innerRadius={44} outerRadius={74} paddingAngle={4}>
                  {statusDistribution.map((entry, index) => (
                    <Cell key={entry.name} fill={['#0f766e', '#f59e0b', '#10b981'][index % 3]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      <div className="cards-grid three-col">
        <div className="panel span-2">
          <div className="panel-header">
            <h2>Highest-priority incidents</h2>
            <button type="button" className="btn-secondary" onClick={() => navigate('/cleaning')}>
              Open cleaning queue
            </button>
          </div>
          <div className="stack-list">
            {topIncidents.map((drain) => (
              <button
                type="button"
                key={drain.id}
                className={`priority-item ${highlightId === drain.id ? 'highlighted' : ''}`}
                onClick={() => navigate('/map')}
              >
                <div>
                  <div className="meta-row">
                    <strong>{drain.id}</strong>
                    <span className={`status-chip ${getStatusColor(drain.status)}`}>{drain.status}</span>
                  </div>
                  <p>{drain.location}</p>
                </div>
                <span className={`priority-score ${getPriorityColor(drain.priority)}`}>{drain.priority.toFixed(2)}</span>
              </button>
            ))}
          </div>
        </div>

        <div className="panel">
          <div className="panel-header">
            <h2>Ward map</h2>
            <span className="panel-note">Synthetic ward layout</span>
          </div>
          <div className="mini-map">
            <div className="map-zone map-zone-1" />
            <div className="map-zone map-zone-2" />
            <div className="map-zone map-zone-3" />
            <div className="map-marker marker-red" />
            <div className="map-marker marker-amber" />
            <div className="map-marker marker-teal" />
            <div className="map-label label-a">DR-A</div>
            <div className="map-label label-b">DR-B</div>
            <div className="map-label label-c">DR-C</div>
          </div>
          <button type="button" className="btn-secondary full-width" onClick={() => navigate('/map')}>Open map view</button>
        </div>
      </div>

      <div className="panel panel-full">
        <div className="panel-header">
          <h2>Recent activity timeline</h2>
          <button type="button" className="btn-secondary" onClick={() => navigate('/reports')}>
            See reports
          </button>
        </div>
        <div className="timeline">
          {activities.map((item) => (
            <div key={item.id} className="timeline-item">
              <span className={`dot ${item.severity}`} />
              <div>
                <div className="timeline-title">{item.title}</div>
                <div className="timeline-detail">{item.detail}</div>
              </div>
              <div className="timeline-time">{formatDate(item.timestamp)}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="cta-row">
        <button type="button" className="btn-primary" onClick={() => navigate('/report')}>
          Create Report
        </button>
      </div>
    </div>
  );
}

function MapPage({ drains }: { drains: DrainRecord[] }) {
  const [selectedId, setSelectedId] = useState<string>('DR-A');
  const selectedDrain = drains.find((drain) => drain.id === selectedId) ?? drains[0];

  return (
    <div className="page-stack">
      <div className="cards-grid two-col">
        <div className="panel span-2">
          <div className="panel-header">
            <h2>Ward 12 map</h2>
            <span className="panel-note">Synthetic locations • no precise geocodes</span>
          </div>
          <div className="map-container">
            <MapContainer center={[28.643, 77.43]} zoom={13} scrollWheelZoom={false} className="leaflet-map">
              <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
              {drains.map((drain) => (
                <CircleMarker
                  key={drain.id}
                  center={drain.mapPosition}
                  radius={drain.status === 'Monitoring' ? 9 : 12}
                  pathOptions={{ color: getMapColor(drain.status), fillColor: getMapColor(drain.status), fillOpacity: 0.8 }}
                  eventHandlers={{ click: () => setSelectedId(drain.id) }}
                />
              ))}
            </MapContainer>
          </div>
        </div>

        <div className="panel">
          <div className="panel-header">
            <h2>Drain detail</h2>
            <span className="panel-note">{selectedDrain.id}</span>
          </div>
          <div className="detail-card">
            <div className="meta-row">
              <strong>{selectedDrain.id}</strong>
              <span className={`status-chip ${getStatusColor(selectedDrain.status)}`}>{selectedDrain.status}</span>
            </div>
            <div className="detail-stack">
              <div><span className="label">Location</span><p>{selectedDrain.location}</p></div>
              <div><span className="label">Current condition</span><p>{selectedDrain.condition}</p></div>
              <div><span className="label">Priority score</span><p>{selectedDrain.priority.toFixed(2)}</p></div>
              <div><span className="label">Score explanation</span><p>{selectedDrain.reason}</p></div>
              <div><span className="label">Last observation</span><p>{formatDate(selectedDrain.lastObservation)}</p></div>
              <div><span className="label">Assigned crew</span><p>{selectedDrain.assignedCrew ?? 'Not assigned yet'}</p></div>
            </div>
            <div className="button-row">
              <button type="button" className="btn-primary" onClick={() => window.alert(`${selectedDrain.id} opened for details review.`)}>Open action</button>
              <button type="button" className="btn-secondary" onClick={() => setSelectedId(selectedDrain.id)}>
                Refresh
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ReportPage({ onSubmit, submittedReportId }: { onSubmit: (form: ReportForm) => void; submittedReportId: string | null }) {
  const [form, setForm] = useState<ReportForm>({
    reporterName: '',
    issueType: 'Blocked Drain',
    ward: 'Ward 12',
    location: 'Hospital Road',
    description: '',
    urgent: false,
  });
  const [photoPreview, setPhotoPreview] = useState<string | undefined>();

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!form.location || !form.description || !form.ward) {
      window.alert('Please provide the required location, ward, and description fields.');
      return;
    }
    onSubmit({ ...form, photo: photoPreview });
    setForm({ reporterName: '', issueType: 'Blocked Drain', ward: 'Ward 12', location: '', description: '', urgent: false });
    setPhotoPreview(undefined);
  };

  const handlePhotoUpload = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => setPhotoPreview(String(reader.result ?? ''));
    reader.readAsDataURL(file);
  };

  if (submittedReportId) {
    return (
      <div className="page-stack narrow">
        <div className="panel success-panel">
          <div className="success-icon"><CheckCheck size={28} /></div>
          <h2>Citizen report submitted</h2>
          <p>Report ID: <strong>{submittedReportId}</strong></p>
          <p className="muted">Demo assessment uses synthetic rules and the image AI is not connected. This is a civic-tech prototype, not a trained model.</p>
          <button type="button" className="btn-primary" onClick={() => window.location.hash = '#/overview'}>Return to dashboard</button>
        </div>
      </div>
    );
  }

  return (
    <div className="page-stack narrow">
      <div className="panel">
        <div className="panel-header">
          <h2>Report a Problem</h2>
          <button type="button" className="btn-secondary" onClick={() => setForm((previous) => ({ ...previous, ward: 'Ward 12', location: 'Hospital Road' }))}>
            Use demo location
          </button>
        </div>

        <form onSubmit={handleSubmit} className="form-grid">
          <label>
            Reporter name (optional)
            <input value={form.reporterName} onChange={(event) => setForm((previous) => ({ ...previous, reporterName: event.target.value }))} />
          </label>

          <label>
            Issue type
            <select value={form.issueType} onChange={(event) => setForm((previous) => ({ ...previous, issueType: event.target.value }))}>
              <option>Blocked Drain</option>
              <option>Partial Blockage</option>
              <option>Waterlogging</option>
              <option>Overflow</option>
              <option>Uncertain Condition</option>
            </select>
          </label>

          <label>
            Ward
            <input value={form.ward} onChange={(event) => setForm((previous) => ({ ...previous, ward: event.target.value }))} />
          </label>

          <label>
            Location or landmark
            <input value={form.location} onChange={(event) => setForm((previous) => ({ ...previous, location: event.target.value }))} required />
          </label>

          <label className="full-width">
            Description
            <textarea value={form.description} onChange={(event) => setForm((previous) => ({ ...previous, description: event.target.value }))} rows={5} required />
          </label>

          <label className="full-width">
            Photo upload
            <input type="file" accept="image/*" onChange={handlePhotoUpload} />
          </label>

          {photoPreview ? (
            <div className="photo-preview full-width">
              <img src={photoPreview} alt="Report preview" />
              <p>Demo assessment — image AI not connected.</p>
            </div>
          ) : (
            <div className="demo-photo-note full-width">Demo assessment — image AI not connected.</div>
          )}

          <label className="checkbox-row full-width">
            <input type="checkbox" checked={form.urgent} onChange={(event) => setForm((previous) => ({ ...previous, urgent: event.target.checked }))} />
            This problem is urgent
          </label>

          <div className="button-row full-width">
            <button type="submit" className="btn-primary">Submit report</button>
          </div>
        </form>
      </div>
    </div>
  );
}

function InspectionQueuePage({ drains, onSubmit }: { drains: DrainRecord[]; onSubmit: (payload: InspectionForm) => void }) {
  const [filterWard, setFilterWard] = useState('All');
  const [filterStatus, setFilterStatus] = useState('All');
  const [search, setSearch] = useState('');
  const [sortMode, setSortMode] = useState<'priority-desc' | 'priority-asc'>('priority-desc');
  const [activeDrainId, setActiveDrainId] = useState<string | null>(null);

  const queue = useMemo(() => {
    return drains
      .filter((drain) => drain.status === 'Inspection Required' || drain.status === 'Pending Review')
      .filter((drain) => filterWard === 'All' || drain.ward === filterWard)
      .filter((drain) => filterStatus === 'All' || drain.status === filterStatus)
      .filter((drain) => drain.location.toLowerCase().includes(search.toLowerCase()) || drain.id.toLowerCase().includes(search.toLowerCase()))
      .sort((a, b) => sortMode === 'priority-desc' ? b.priority - a.priority : a.priority - b.priority);
  }, [drains, filterWard, filterStatus, search, sortMode]);

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <h2>Inspection queue</h2>
          <span className="panel-note">Evidence gaps and uncertain conditions</span>
        </div>

        <div className="toolbar">
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search location or drain ID" />
          <select value={filterWard} onChange={(event) => setFilterWard(event.target.value)}>
            <option value="All">All wards</option>
            <option value="Ward 12">Ward 12</option>
          </select>
          <select value={filterStatus} onChange={(event) => setFilterStatus(event.target.value)}>
            <option value="All">All statuses</option>
            <option value="Inspection Required">Inspection Required</option>
            <option value="Pending Review">Pending Review</option>
          </select>
          <select value={sortMode} onChange={(event) => setSortMode(event.target.value as 'priority-desc' | 'priority-asc')}>
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
                  <td className={getPriorityColor(drain.priority)}>{drain.priority.toFixed(2)}</td>
                  <td>
                    <button type="button" className="btn-secondary" onClick={() => setActiveDrainId(drain.id)}>
                      Start Inspection
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {activeDrainId ? (
        <InspectionModal
          drain={drains.find((drain) => drain.id === activeDrainId)!}
          onClose={() => setActiveDrainId(null)}
          onSubmit={(payload) => {
            onSubmit(payload);
            setActiveDrainId(null);
          }}
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
  const [observedCondition, setObservedCondition] = useState('Visually Clear');
  const [estimatedBlockage, setEstimatedBlockage] = useState<number>(drain.visibleBlockage ?? 40);
  const [notes, setNotes] = useState('');
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
          <button type="button" className="btn-secondary" onClick={onClose}>Close</button>
        </div>

        <div className="form-grid">
          <label>
            Observed condition
            <select value={observedCondition} onChange={(event) => setObservedCondition(event.target.value)}>
              <option>Visually Clear</option>
              <option>Partial Blockage</option>
              <option>Severe Blockage</option>
              <option>Waterlogging Observed</option>
              <option>Unknown</option>
            </select>
          </label>

          <label>
            Estimated blockage percentage
            <input type="number" value={estimatedBlockage} min={0} max={100} onChange={(event) => setEstimatedBlockage(Number(event.target.value))} />
          </label>

          <label className="full-width">
            Notes
            <textarea rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} />
          </label>

          <label className="full-width">
            Upload inspection photo
            <input type="file" accept="image/*" onChange={(event) => {
              const file = event.target.files?.[0];
              if (!file) return;
              const reader = new FileReader();
              reader.onload = () => setPhoto(String(reader.result ?? ''));
              reader.readAsDataURL(file);
            }} />
          </label>

          <div className="button-row full-width">
            <button type="button" className="btn-primary" onClick={submit}>Submit inspection</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function CleaningQueuePage({ drains, onAssign }: { drains: DrainRecord[]; onAssign: (drainId: string, crew: string, completionTime: string, note: string) => void }) {
  const [selectedDrainId, setSelectedDrainId] = useState<string | null>(null);
  const cleaningDrains = drains.filter((drain) => drain.status === 'Cleaning Recommended' || drain.status === 'Assigned' || drain.status === 'Rework Required');

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
                  <td className={getPriorityColor(drain.priority)}>{drain.priority.toFixed(2)}</td>
                  <td><span className={`status-chip ${getStatusColor(drain.status)}`}>{drain.status}</span></td>
                  <td>{drain.assignedCrew ?? 'Unassigned'}</td>
                  <td>
                    <button type="button" className="btn-secondary" onClick={() => setSelectedDrainId(drain.id)}>
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
  onAssign: (drainId: string, crew: string, completionTime: string, note: string) => void;
}) {
  const [crew, setCrew] = useState('Crew Alpha');
  const [completionTime, setCompletionTime] = useState('Today 16:00');
  const [note, setNote] = useState('');

  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="panel-header">
          <h2>Assign crew — {drainId}</h2>
          <button type="button" className="btn-secondary" onClick={onClose}>Close</button>
        </div>

        <div className="form-grid">
          <label>
            Crew
            <select value={crew} onChange={(event) => setCrew(event.target.value)}>
              <option>Crew Alpha</option>
              <option>Crew Bravo</option>
              <option>Crew Charlie</option>
            </select>
          </label>

          <label>
            Target completion time
            <input value={completionTime} onChange={(event) => setCompletionTime(event.target.value)} />
          </label>

          <label className="full-width">
            Optional note
            <textarea rows={3} value={note} onChange={(event) => setNote(event.target.value)} />
          </label>

          <div className="button-row full-width">
            <button type="button" className="btn-primary" onClick={() => { onAssign(drainId, crew, completionTime, note); onClose(); }}>
              Save assignment
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function MonitoringPage({ drains, onRecordObservation }: { drains: DrainRecord[]; onRecordObservation: (payload: { drainId: string; beforeCondition: string; afterCondition: string; outcome: OutcomeType; recommendation: string; postRainObservation: string }) => void }) {
  const [selectedDrainId, setSelectedDrainId] = useState<string | null>(null);
  const monitoringDrains = drains.filter((drain) => drain.status === 'Monitoring' || drain.status === 'Reviewed');

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <h2>Monitoring</h2>
          <span className="panel-note">Latest usable observations show visual clearance</span>
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
                  <td><span className={`status-chip ${getStatusColor(drain.status)}`}>{drain.status}</span></td>
                  <td>
                    <button type="button" className="btn-secondary" onClick={() => setSelectedDrainId(drain.id)}>
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

function ObservationModal({
  drainId,
  onClose,
  onSave,
}: {
  drainId: string;
  onClose: () => void;
  onSave: (payload: { drainId: string; beforeCondition: string; afterCondition: string; outcome: OutcomeType; recommendation: string; postRainObservation: string }) => void;
}) {
  const [beforeCondition, setBeforeCondition] = useState('Clear after maintenance');
  const [afterCondition, setAfterCondition] = useState('No visible blockage');
  const [outcome, setOutcome] = useState<OutcomeType>('Resolved');
  const [recommendation, setRecommendation] = useState('Continue routine checks.');
  const [postRainObservation, setPostRainObservation] = useState('Waterlogging reduced after rainfall.');

  return (
    <div className="modal-backdrop">
      <div className="modal-card">
        <div className="panel-header">
          <h2>Record observation — {drainId}</h2>
          <button type="button" className="btn-secondary" onClick={onClose}>Close</button>
        </div>

        <div className="form-grid">
          <label>
            Before condition
            <input value={beforeCondition} onChange={(event) => setBeforeCondition(event.target.value)} />
          </label>
          <label>
            After condition
            <input value={afterCondition} onChange={(event) => setAfterCondition(event.target.value)} />
          </label>
          <label>
            Outcome category
            <select value={outcome} onChange={(event) => setOutcome(event.target.value as OutcomeType)}>
              <option>Resolved</option>
              <option>Partially Resolved</option>
              <option>Persisted</option>
              <option>Not Observed</option>
            </select>
          </label>
          <label className="full-width">
            Post-rain observation
            <textarea rows={3} value={postRainObservation} onChange={(event) => setPostRainObservation(event.target.value)} />
          </label>
          <label className="full-width">
            Recommendation
            <textarea rows={3} value={recommendation} onChange={(event) => setRecommendation(event.target.value)} />
          </label>
          <div className="button-row full-width">
            <button type="button" className="btn-primary" onClick={() => { onSave({ drainId, beforeCondition, afterCondition, outcome, recommendation, postRainObservation }); onClose(); }}>Save observation</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function EvidenceReviewPage({ drains, onAction }: { drains: DrainRecord[]; onAction: (drainId: string, action: 'Accept' | 'Request Rework' | 'Flag Location Mismatch', details: string) => void }) {
  const reviewQueue = drains.filter((drain) => drain.status === 'Pending Review' || drain.status === 'Rework Required');

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
    <div className="page-stack">
      {reviewQueue.map((drain) => (
        <div key={drain.id} className="panel evidence-card">
          <div className="panel-header">
            <h2>{drain.id}</h2>
            <span className={`status-chip ${getStatusColor(drain.status)}`}>{drain.status}</span>
          </div>

          <div className="evidence-grid">
            <div className="evidence-image placeholder">Before image</div>
            <div className="evidence-image placeholder">After image</div>
          </div>

          <div className="evidence-meta-list">
            <div><span>Location</span><strong>{drain.location}</strong></div>
            <div><span>Submitted timestamp</span><strong>{formatDate(drain.lastObservation)}</strong></div>
            <div><span>Work notes</span><strong>{drain.reason}</strong></div>
            <div><span>Evidence status</span><strong>{drain.evidenceStatus}</strong></div>
            <div><span>Reviewer notes</span><strong>Location mismatch review is flagged for checking the field trace.</strong></div>
          </div>

          <div className="button-row">
            <button type="button" className="btn-primary" onClick={() => {
              const confirmed = window.confirm(`Accept evidence for ${drain.id}?`);
              if (confirmed) onAction(drain.id, 'Accept', 'Accepted after review.');
            }}>Accept Evidence</button>
            <button type="button" className="btn-secondary" onClick={() => onAction(drain.id, 'Request Rework', 'Rework requested because evidence quality is insufficient.')}>Request Rework</button>
            <button type="button" className="btn-secondary alt" onClick={() => onAction(drain.id, 'Flag Location Mismatch', 'Location mismatch warning: field evidence did not match the assigned drain location.')}>Flag Location Mismatch</button>
          </div>
        </div>
      ))}
    </div>
  );
}

function OutcomePage({ drains, outcomes, onAddOutcome }: { drains: DrainRecord[]; outcomes: OutcomeRecord[]; onAddOutcome: (payload: { drainId: string; beforeCondition: string; afterCondition: string; outcome: OutcomeType; recommendation: string; postRainObservation: string }) => void }) {
  const [selectedDrainId, setSelectedDrainId] = useState('DR-A');

  return (
    <div className="page-stack">
      <div className="cards-grid two-col">
        {outcomes.map((outcome) => {
          const drain = drains.find((item) => item.id === outcome.drainId) ?? drains[0];
          return (
            <div key={outcome.id} className="panel outcome-card">
              <div className="panel-header">
                <h2>{outcome.drainId}</h2>
                <span className={`status-chip ${getOutcomeColor(outcome.outcome)}`}>{outcome.outcome}</span>
              </div>
              <div className="outcome-grid">
                <div><span>Before</span><p>{outcome.beforeCondition}</p></div>
                <div><span>After</span><p>{outcome.afterCondition}</p></div>
                <div><span>Post-rain</span><p>{outcome.postRainObservation}</p></div>
                <div><span>Recommendation</span><p>{outcome.recommendation}</p></div>
              </div>
              <div className="muted small">{drain.location}</div>
            </div>
          );
        })}
      </div>

      <div className="panel">
        <div className="panel-header">
          <h2>Add post-rain observation</h2>
          <span className="panel-note">Observed outcomes are not proof of causality</span>
        </div>
        <div className="form-grid">
          <label>
            Drain ID
            <select value={selectedDrainId} onChange={(event) => setSelectedDrainId(event.target.value)}>
              {drains.map((drain) => (
                <option key={drain.id} value={drain.id}>{drain.id}</option>
              ))}
            </select>
          </label>
        </div>
        <div className="button-row">
          <button type="button" className="btn-primary" onClick={() => onAddOutcome({
            drainId: selectedDrainId,
            beforeCondition: 'Maintenance was completed and the drain was reviewed.',
            afterCondition: 'Current state observed after rainfall.',
            outcome: 'Partially Resolved',
            recommendation: 'Continue monitoring and inspect downstream assets.',
            postRainObservation: 'Water level remains elevated after the last rainfall event.',
          })}>Add observation</button>
        </div>
      </div>
    </div>
  );
}

function ComplaintsPage({ reports, drains }: { reports: ReportRecord[]; drains: DrainRecord[] }) {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('All');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const filteredReports = reports.filter((report) => {
    const matchesSearch = `${report.id} ${report.location} ${report.issueType} ${report.drainId}`.toLowerCase().includes(search.toLowerCase());
    return matchesSearch && (status === 'All' || report.status === status);
  });
  const selectedReport = reports.find((report) => report.id === selectedId);
  const selectedDrain = selectedReport ? drains.find((drain) => drain.id === selectedReport.drainId) : undefined;

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Complaints &amp; incidents</h2>
            <p className="panel-note">Review incoming reports, group duplicates, and decide the next operational action.</p>
          </div>
          <span className="demo-badge">Synthetic reports</span>
        </div>
        <div className="toolbar">
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search report, location, issue, or drain ID" />
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
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
                  <td><strong>{report.id}</strong><br /><span className="muted">{report.drainId}</span></td>
                  <td>{report.issueType}<br /><span className="muted">{report.location}</span></td>
                  <td>{formatDate(report.submittedAt)}</td>
                  <td>{report.urgent ? <span className="status-chip bg-red-100 text-red-700 border-red-200">Urgent</span> : 'Standard'}</td>
                  <td>{report.photo ? 'Photo attached' : 'Description only'}</td>
                  <td>{report.status}</td>
                  <td><button type="button" className="btn-secondary" onClick={() => setSelectedId(report.id)}>Review</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          {filteredReports.length === 0 ? <div className="empty-state"><Search size={24} /><h2>No matching reports</h2><p className="muted">Try a different search or status filter.</p></div> : null}
        </div>
      </div>
      {selectedReport ? (
        <div className="panel">
          <div className="panel-header">
            <h2>Report review — {selectedReport.id}</h2>
            <button type="button" className="btn-secondary" onClick={() => setSelectedId(null)}>Close</button>
          </div>
          <div className="outcome-grid">
            <div><span>Report description</span><p>{selectedReport.description}</p></div>
            <div><span>Linked asset</span><p>{selectedDrain ? `${selectedDrain.id} · ${selectedDrain.location}` : 'No matching drain record'}</p></div>
            <div><span>Priority context</span><p>{selectedReport.reasons.join(' · ')}</p></div>
            <div><span>Human decision</span><p>Complaint volume is supporting context; authorised staff should confirm the operational action.</p></div>
          </div>
          <div className="button-row">
            <button type="button" className="btn-primary" onClick={() => window.alert(`Inspection recommendation recorded for ${selectedReport.id}.`)}>Recommend inspection</button>
            <button type="button" className="btn-secondary" onClick={() => window.alert(`Duplicate review opened for ${selectedReport.id}.`)}>Mark possible duplicate</button>
            <button type="button" className="btn-secondary" onClick={() => window.alert(`Triage note opened for ${selectedReport.id}.`)}>Add triage note</button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function WorkOrdersPage({ drains }: { drains: DrainRecord[] }) {
  const [status, setStatus] = useState('All');
  const workOrders = drains.filter((drain) => drain.workStatus || drain.assignedCrew);
  const filtered = workOrders.filter((drain) => status === 'All' || (drain.workStatus ?? '').includes(status));

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <div>
            <h2>Work orders</h2>
            <p className="panel-note">Assignment and completion lifecycle for field operations. Crew assignment is simulated in this demo.</p>
          </div>
          <button type="button" className="btn-primary" onClick={() => window.alert('Create work order flow is ready to connect to an incident or priority item.')}>Create work order</button>
        </div>
        <div className="toolbar">
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option>All</option>
            <option>Assigned</option>
            <option>Inspection</option>
            <option>Cleaning</option>
            <option>Monitoring</option>
            <option>Review</option>
          </select>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Work order</th>
                <th>Drain / task</th>
                <th>Priority</th>
                <th>Crew</th>
                <th>Status</th>
                <th>Last updated</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((drain) => (
                <tr key={drain.id}>
                  <td><strong>WO-{drain.id}</strong><br /><span className="muted">{drain.issueType}</span></td>
                  <td>{drain.id}<br /><span className="muted">{drain.location}</span></td>
                  <td className={getPriorityColor(drain.priority)}>{drain.priority.toFixed(2)}</td>
                  <td>{drain.assignedCrew ?? 'Unassigned'}</td>
                  <td><span className={`status-chip ${getStatusColor(drain.status)}`}>{drain.workStatus ?? drain.status}</span></td>
                  <td>{formatDate(drain.lastUpdated)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length === 0 ? <div className="empty-state"><ClipboardList size={24} /><h2>No matching work orders</h2><p className="muted">Create one from a queue item or incident.</p></div> : null}
        </div>
      </div>
    </div>
  );
}

function ReportsPage({ drains, reports, wardOptions }: { drains: DrainRecord[]; reports: ReportRecord[]; outcomes?: OutcomeRecord[]; wardOptions: string[] }) {
  const [wardFilter, setWardFilter] = useState('All');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  const filteredReports = reports.filter((report) => {
    if (wardFilter !== 'All' && report.ward !== wardFilter) return false;
    if (startDate && new Date(report.submittedAt) < new Date(startDate)) return false;
    if (endDate && new Date(report.submittedAt) > new Date(endDate)) return false;
    return true;
  });

  const exportCsv = () => {
    const rows = [
      ['Drain ID', 'Reporter', 'Issue Type', 'Ward', 'Location', 'Priority', 'Submitted At'],
      ...filteredReports.map((report) => [report.drainId, report.reporterName, report.issueType, report.ward, report.location, report.priority, report.submittedAt]),
    ];
    const csv = rows.map((row) => row.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'drainrank-demo-report.csv';
    link.click();
    URL.revokeObjectURL(url);
  };

  const issueTypeCounts = ['Blocked Drain', 'Partial Blockage', 'Waterlogging', 'Overflow', 'Uncertain Condition'].map((issueType) => ({
    name: issueType,
    value: reports.filter((report) => report.issueType === issueType).length,
  }));

  const comparisonChart = [
    { name: 'Cleaning', value: drains.filter((drain) => drain.status.includes('Cleaning') || drain.status === 'Assigned').length },
    { name: 'Inspection', value: drains.filter((drain) => drain.status.includes('Inspection') || drain.status === 'Pending Review').length },
  ];

  return (
    <div className="page-stack">
      <div className="panel">
        <div className="panel-header">
          <h2>Reports</h2>
          <button type="button" className="btn-primary" onClick={exportCsv}>Export CSV</button>
        </div>

        <div className="toolbar">
          <select value={wardFilter} onChange={(event) => setWardFilter(event.target.value)}>
            <option value="All">All wards</option>
            {wardOptions.filter((option) => option !== 'All').map((option) => (
              <option key={option} value={option}>{option}</option>
            ))}
          </select>
          <input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} />
          <input type="date" value={endDate} onChange={(event) => setEndDate(event.target.value)} />
        </div>

        <div className="cards-grid two-col">
          <div className="panel">
            <div className="panel-header">
              <h2>Reports by issue type</h2>
            </div>
            <div className="chart-wrap small">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={issueTypeCounts}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="name" />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]} fill="#0f766e" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="panel">
            <div className="panel-header">
              <h2>Cleaning vs inspection tasks</h2>
            </div>
            <div className="chart-wrap small">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={comparisonChart}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                  <XAxis dataKey="name" />
                  <YAxis allowDecimals={false} />
                  <Tooltip />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]} fill="#f59e0b" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        <div className="table-wrap">
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
      </div>
    </div>
  );
}

function AdministrationPage({ onReset, onClear }: { onReset: () => void; onClear: () => void }) {
  return (
    <div className="page-stack narrow">
      <div className="panel settings-panel">
        <div className="panel-header">
          <div>
            <h2>Administration</h2>
            <p className="panel-note">Demo-only configuration and role labels; this prototype does not provide production access control.</p>
          </div>
          <UsersRound size={22} color="#0f766e" />
        </div>
        <div className="detail-stack">
          <div><span className="label">Current role</span><p>Ward Officer · demo role</p></div>
          <div><span className="label">Ward scope</span><p>Ward 12 · synthetic operating scope</p></div>
          <div><span className="label">Crew directory</span><p>Crew Alpha, Crew Bravo, Crew Charlie</p></div>
          <div><span className="label">Priority model</span><p>Provisional formula with visible score explanations; not operationally validated.</p></div>
        </div>
        <div className="stack-list">
          <button type="button" className="btn-secondary" onClick={() => {
            if (window.confirm('Reset the demo data back to the initial synthetic scenario?')) onReset();
          }}>
            <RefreshCw size={16} /> Reset Demo Data
          </button>
          <button type="button" className="btn-secondary" onClick={() => {
            if (window.confirm('Restore the seeded scenario?')) onReset();
          }}>
            <CheckCheck size={16} /> Restore Seeded Scenario
          </button>
          <button type="button" className="btn-secondary alt" onClick={() => {
            if (window.confirm('Clear all local data? This will restore the seeded scenario.')) onClear();
          }}>
            <Trash2 size={16} /> Clear Local Data
          </button>
        </div>
      </div>
    </div>
  );
}

export default App;
