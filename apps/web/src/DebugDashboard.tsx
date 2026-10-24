import { useState } from "react";
import type { FormEvent } from "react";
import {
  advanceDebugReport,
  type DebugAction,
  type DebugReport,
  type DebugStage,
} from "./debugWorkflow";
import "./DebugDashboard.css";

const DEMO_PIN = "12345678";

const stageLabels: Record<DebugStage, string> = {
  inspection_required: "Inspection required",
  cleaning_required: "Cleaning required",
  awaiting_verification: "Awaiting supervisor verification",
  verified: "Verified",
};

export default function DebugDashboard() {
  const [unlocked, setUnlocked] = useState(false);
  const [pin, setPin] = useState("");
  const [pinError, setPinError] = useState("");
  const [reports, setReports] = useState<DebugReport[]>([]);
  const [page, setPage] = useState("Citizen report");
  const [reporter, setReporter] = useState("");
  const [location, setLocation] = useState("");
  const [issue, setIssue] = useState("Blocked drain");
  const [description, setDescription] = useState("");
  const [adminPassword, setAdminPassword] = useState("");
  const [adminUnlocked, setAdminUnlocked] = useState(false);
  const [adminError, setAdminError] = useState("");
  const [reportNumber, setReportNumber] = useState(1);

  const updateReport = (id: string, action: DebugAction) => {
    setReports((current) =>
      current.map((report) =>
        report.id === id ? advanceDebugReport(report, action) : report,
      ),
    );
  };

  const unlock = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pin === DEMO_PIN) {
      setUnlocked(true);
      setPinError("");
    } else {
      setPinError("Incorrect demo PIN. Try the testing PIN shown below.");
    }
  };

  const submitReport = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const id = `DBG-${String(reportNumber).padStart(3, "0")}`;
    setReportNumber((number) => number + 1);
    setReports((current) => [
      {
        id,
        reporter: reporter.trim(),
        location: location.trim(),
        issue,
        description: description.trim(),
        stage: "inspection_required",
        credits: 0,
      },
      ...current,
    ]);
    setReporter("");
    setLocation("");
    setDescription("");
    setPage("Inspection queue");
  };

  const runAdminAction = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (adminPassword !== DEMO_PIN) {
      setAdminError("Incorrect local debug password.");
      return;
    }
    setAdminUnlocked(true);
    setAdminError("");
    setAdminPassword("");
  };

  const seedSample = () => {
    const id = `DBG-${String(reportNumber).padStart(3, "0")}`;
    setReportNumber((number) => number + 1);
    setReports([
      {
        id,
        reporter: "Demo resident",
        location: "Market Road, Ward 4",
        issue: "Blocked drain",
        description: "Leaves and silt are slowing the water flow.",
        stage: "inspection_required",
        credits: 0,
      },
    ]);
    setPage("Citizen report");
  };

  if (!unlocked) {
    return (
      <main className="debug-login-wrap">
        <form className="debug-login" onSubmit={unlock}>
          <div className="debug-brand-mark" aria-hidden="true">
            SP
          </div>
          <p className="debug-eyebrow">Offline workflow preview</p>
          <h1>Swachh Pravah Debug</h1>
          <p>
            Enter the demo PIN to explore a local-only citizen-to-supervisor
            workflow.
          </p>
          <label htmlFor="debug-pin">Demo PIN</label>
          <input
            autoComplete="off"
            id="debug-pin"
            inputMode="numeric"
            onChange={(event) => setPin(event.target.value)}
            type="password"
            value={pin}
          />
          {pinError ? <p className="debug-error" role="alert">{pinError}</p> : null}
          <button className="debug-button debug-button-primary" type="submit">
            Open debug dashboard
          </button>
          <p className="debug-warning">
            Testing only — PIN <strong>12345678</strong> is public and is not
            security.
          </p>
          <p className="debug-storage-note">
            No Supabase configuration is needed. This preview uses memory only;
            nothing is saved or sent.
          </p>
        </form>
      </main>
    );
  }

  const queueFor = (stage: DebugStage) =>
    reports.filter((report) => report.stage === stage);
  const completedCredits = reports.reduce(
    (sum, report) => sum + report.credits,
    0,
  );

  const stageAction: Partial<
    Record<DebugStage, { label: string; action: DebugAction }>
  > = {
    inspection_required: {
      label: "Inspect: cleaning required",
      action: "inspect",
    },
    cleaning_required: { label: "Mark cleaning complete", action: "clean" },
    awaiting_verification: {
      label: "Verify and award 100 credits",
      action: "verify",
    },
  };

  const reportCard = (report: DebugReport) => {
    const nextStep = stageAction[report.stage];
    return (
      <article className="debug-report-card" key={report.id}>
        <div className="debug-report-heading">
          <div>
            <span className="debug-report-id">{report.id}</span>
            <h3>{report.issue}</h3>
          </div>
          <span className={`debug-status debug-status-${report.stage}`}>
            {stageLabels[report.stage]}
          </span>
        </div>
        <p className="debug-report-location">{report.location}</p>
        <p>{report.description || "No additional details provided."}</p>
        <dl className="debug-report-details">
          <div><dt>Citizen</dt><dd>{report.reporter}</dd></div>
          <div><dt>Credits</dt><dd>{report.credits}</dd></div>
        </dl>
        {nextStep ? (
          <button
            className="debug-button debug-button-primary"
            onClick={() => updateReport(report.id, nextStep.action)}
            type="button"
          >
            {nextStep.label}
          </button>
        ) : (
          <p className="debug-verified-note">Supervisor verified · {report.credits} credits awarded</p>
        )}
      </article>
    );
  };

  return (
    <div className="debug-shell">
      <aside className="debug-sidebar">
        <div className="debug-brand">
          <div className="debug-brand-mark" aria-hidden="true">SP</div>
          <div>
            <strong>Swachh Pravah</strong>
            <span>Offline debug mode</span>
          </div>
        </div>
        <nav aria-label="Debug dashboard pages">
          {[
            "Citizen report",
            "Inspection queue",
            "Cleaning queue",
            "Supervisor verification",
            "Administration",
          ].map((label) => (
            <button
              aria-current={page === label ? "page" : undefined}
              className={`debug-nav-item ${page === label ? "active" : ""}`}
              key={label}
              onClick={() => setPage(label)}
              type="button"
            >
              {label}
              {label === "Inspection queue" ? (
                <span>{queueFor("inspection_required").length}</span>
              ) : null}
              {label === "Cleaning queue" ? (
                <span>{queueFor("cleaning_required").length}</span>
              ) : null}
            </button>
          ))}
        </nav>
        <div className="debug-sidebar-footer">
          <span>In-memory session</span>
          <button
            className="debug-button debug-button-quiet"
            onClick={() => {
              setUnlocked(false);
              setReports([]);
              setReportNumber(1);
              setAdminUnlocked(false);
              setAdminPassword("");
              setPage("Citizen report");
            }}
            type="button"
          >
            Lock and clear session
          </button>
        </div>
      </aside>

      <main className="debug-main">
        <header className="debug-topbar">
          <div>
            <p className="debug-eyebrow">DrainRank · testing environment</p>
            <h1>{page}</h1>
          </div>
          <div className="debug-topbar-metric">
            <span>Supervisor credits</span>
            <strong>{completedCredits}</strong>
          </div>
        </header>

        <div className="debug-banner" role="note">
          <strong>Testing only — not security.</strong> This /debug dashboard
          bypasses AuthGate and uses in-memory data only. It makes no backend
          requests and does not use browser storage.
        </div>

        {page === "Citizen report" ? (
          <section className="debug-content">
            <div className="debug-intro">
              <h2>Submit a citizen report</h2>
              <p>Reports entered here flow through the local inspection, cleaning, and verification queues.</p>
            </div>
            <form className="debug-panel debug-report-form" onSubmit={submitReport}>
              <label>
                Citizen name
                <input
                  onChange={(event) => setReporter(event.target.value)}
                  required
                  value={reporter}
                />
              </label>
              <label>
                Drain location
                <input
                  onChange={(event) => setLocation(event.target.value)}
                  placeholder="Street, ward, or landmark"
                  required
                  value={location}
                />
              </label>
              <label>
                Issue
                <select onChange={(event) => setIssue(event.target.value)} value={issue}>
                  <option>Blocked drain</option>
                  <option>Waterlogging</option>
                  <option>Damaged cover</option>
                  <option>Overflow</option>
                </select>
              </label>
              <label>
                Description
                <textarea
                  onChange={(event) => setDescription(event.target.value)}
                  placeholder="Describe what you observed"
                  rows={4}
                  value={description}
                />
              </label>
              <button className="debug-button debug-button-primary" type="submit">
                Submit report to inspection
              </button>
            </form>
          </section>
        ) : null}

        {page === "Inspection queue" ? (
          <QueuePage
            description="New citizen reports wait here for a field inspection."
            empty="No reports waiting for inspection. Submit one from Citizen report."
            reports={queueFor("inspection_required")}
            renderReport={reportCard}
            title="Inspection queue"
          />
        ) : null}

        {page === "Cleaning queue" ? (
          <QueuePage
            description="Inspection-confirmed reports move here for a cleaning crew."
            empty="No reports waiting for cleaning. Complete an inspection first."
            reports={queueFor("cleaning_required")}
            renderReport={reportCard}
            title="Cleaning queue"
          />
        ) : null}

        {page === "Supervisor verification" ? (
          <section className="debug-content">
            <div className="debug-intro">
              <h2>Supervisor verification</h2>
              <p>Review completed work and award local demo credits only after verification.</p>
            </div>
            <ReportList
              empty="No completed cleaning work is waiting for verification."
              reports={queueFor("awaiting_verification")}
              renderReport={reportCard}
            />
            <div className="debug-panel debug-credit-summary">
              <span>Total demo credits awarded</span>
              <strong>{completedCredits}</strong>
              <small>Credits exist only in this page session.</small>
            </div>
            <ReportList
              empty="No reports have been verified yet."
              reports={queueFor("verified")}
              renderReport={reportCard}
            />
          </section>
        ) : null}

        {page === "Administration" ? (
          <section className="debug-content">
            <div className="debug-intro">
              <h2>Administration</h2>
              <p>Local debug controls are separate from the real municipal dashboard and only affect this temporary session.</p>
            </div>
            <div className="debug-panel">
              <h3>Local debug controls</h3>
              {!adminUnlocked ? (
                <form className="debug-admin-form" onSubmit={runAdminAction}>
                  <p>Enter the debug password to reveal reset and sample controls.</p>
                  <label>
                    Debug password
                    <input
                      autoComplete="off"
                      onChange={(event) => setAdminPassword(event.target.value)}
                      type="password"
                      value={adminPassword}
                    />
                  </label>
                  {adminError ? <p className="debug-error" role="alert">{adminError}</p> : null}
                  <button className="debug-button debug-button-primary" type="submit">
                    Unlock local controls
                  </button>
                </form>
              ) : (
                <div className="debug-admin-controls">
                  <p className="debug-warning">
                    These controls do not change app data, Supabase, or browser
                    storage. Reloading or leaving the page discards the session.
                  </p>
                  <div className="debug-control-buttons">
                    <button className="debug-button debug-button-primary" onClick={seedSample} type="button">
                      Load sample citizen report
                    </button>
                    <button
                      className="debug-button debug-button-danger"
                      onClick={() => {
                        setReports([]);
                        setReportNumber(1);
                      }}
                      type="button"
                    >
                      Clear all local debug data
                    </button>
                    <button
                      className="debug-button debug-button-quiet"
                      onClick={() => setAdminUnlocked(false)}
                      type="button"
                    >
                      Lock controls
                    </button>
                  </div>
                  <p>{reports.length} local report(s) · {completedCredits} demo credits</p>
                </div>
              )}
            </div>
          </section>
        ) : null}
      </main>
    </div>
  );
}

function QueuePage({
  title,
  description,
  empty,
  reports,
  renderReport,
}: {
  title: string;
  description: string;
  empty: string;
  reports: DebugReport[];
  renderReport: (report: DebugReport) => React.ReactNode;
}) {
  return (
    <section className="debug-content">
      <div className="debug-intro">
        <h2>{title}</h2>
        <p>{description}</p>
      </div>
      <ReportList empty={empty} reports={reports} renderReport={renderReport} />
    </section>
  );
}

function ReportList({
  reports,
  empty,
  renderReport,
}: {
  reports: DebugReport[];
  empty: string;
  renderReport: (report: DebugReport) => React.ReactNode;
}) {
  if (!reports.length) return <div className="debug-empty">{empty}</div>;
  return <div className="debug-report-list">{reports.map(renderReport)}</div>;
}
