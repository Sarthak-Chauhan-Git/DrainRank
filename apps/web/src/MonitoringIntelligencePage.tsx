import { useMemo, useState } from "react";
import {
  Activity,
  AlertTriangle,
  Droplets,
  History,
  Sparkles,
  Waves,
} from "lucide-react";
import type { DrainRecord } from "./App";
import {
  analyzeDrainRecords,
  type DrainHistoryInput,
  type DrainIntelligenceInput,
  type DrainOutcomeInput,
} from "./intelligence";
import "./MonitoringIntelligence.css";

interface MonitoringIntelligencePageProps {
  drains: readonly DrainIntelligenceInput[];
  reports: readonly DrainHistoryInput[];
  outcomes: readonly DrainOutcomeInput[];
  onStatusChange: (drainId: string, status: DrainRecord["status"]) => void;
}

const statusOptions: DrainRecord["status"][] = [
  "Cleaning Recommended",
  "Inspection Required",
  "Monitoring",
  "Assigned",
  "Pending Review",
  "Reviewed",
  "Rework Required",
  "Resolved",
];

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Date unavailable"
    : date.toLocaleString([], { dateStyle: "medium", timeStyle: "short" });
}

function formatAssetLocation(ward: string, location: string) {
  const wardPrefix = `${ward}, `;
  return location.toLowerCase().startsWith(wardPrefix.toLowerCase())
    ? location.slice(wardPrefix.length)
    : location;
}

function getPriorityBand(score: number) {
  if (score >= 80) return "high";
  if (score >= 60) return "medium";
  return "low";
}

function MetricCard({
  label,
  value,
  detail,
  icon: Icon,
  alert = false,
}: {
  label: string;
  value: number;
  detail: string;
  icon: typeof Droplets;
  alert?: boolean;
}) {
  return (
    <article className={`intel-metric ${alert && value ? "is-alert" : ""}`}>
      <div className="intel-metric-icon">
        <Icon size={18} />
      </div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
        <small>{detail}</small>
      </div>
    </article>
  );
}

export default function MonitoringIntelligencePage({
  drains,
  reports,
  outcomes,
  onStatusChange,
}: MonitoringIntelligencePageProps) {
  const snapshot = useMemo(
    () => analyzeDrainRecords(drains, reports, outcomes),
    [drains, reports, outcomes],
  );
  const [selectedId, setSelectedId] = useState<string | null>(
    snapshot.cases[0]?.drain.id ?? null,
  );
  const selected = snapshot.cases.find(
    (item) => item.drain.id === selectedId,
  );

  return (
    <div className="page-stack monitoring-intelligence">
      <section className="intel-metrics" aria-label="Monitoring summary">
        <MetricCard
          label="Drain assets"
          value={snapshot.cases.length}
          detail="In the current local dataset"
          icon={Droplets}
        />
        <MetricCard
          label="Recurring issues"
          value={snapshot.recurringCount}
          detail="Linked complaints or persistent outcomes"
          icon={Activity}
        />
        <MetricCard
          label="High-priority cases"
          value={snapshot.cases.filter((item) => item.score >= 80).length}
          detail="Ranked score of 80 or higher"
          icon={Waves}
          alert
        />
        <MetricCard
          label="Overdue work"
          value={snapshot.overdueCount}
          detail="Past deadline and not resolved"
          icon={AlertTriangle}
          alert
        />
      </section>

      <section className="intel-workspace">
        <div className="intel-case-list panel">
          <div className="intel-section-heading">
            <div>
              <span className="intel-kicker">Prioritized queue</span>
              <h3>Drain cases</h3>
            </div>
            <span className="intel-live-tag">Ranked by score</span>
          </div>
          <div className="intel-case-items">
            {snapshot.cases.map((item, index) => (
              <button
                className={`intel-case-item ${selectedId === item.drain.id ? "selected" : ""}`}
                key={item.drain.id}
                onClick={() => setSelectedId(item.drain.id)}
                type="button"
              >
                <span className="intel-rank">{String(index + 1).padStart(2, "0")}</span>
                <span className="intel-case-main">
                  <strong>{item.drain.id}</strong>
                  <small>
                    {item.drain.ward} · {formatAssetLocation(item.drain.ward, item.drain.location)}
                  </small>
                  <span className="intel-case-flags">
                    {item.recurring ? <em>Recurring</em> : null}
                    {item.overdue ? <em className="overdue">Overdue</em> : null}
                    {item.awaitingReview ? <em className="review">Review</em> : null}
                  </span>
                </span>
                <span className={`intel-score priority-${getPriorityBand(item.score)}`}>
                  {item.score}
                </span>
              </button>
            ))}
            {!snapshot.cases.length ? (
              <p className="intel-empty">No drainage records are available.</p>
            ) : null}
          </div>
        </div>

        {selected ? (
          <article className="intel-case-detail panel">
            <div className="intel-detail-top">
              <div>
                <span className="intel-kicker">Priority case · {selected.drain.issueType}</span>
                <h3>{selected.drain.id}</h3>
                <p>{formatAssetLocation(selected.drain.ward, selected.drain.location)} · {selected.drain.ward}</p>
              </div>
              <div className={`intel-score-badge priority-${getPriorityBand(selected.score)}`}>
                <strong>{selected.score}<small>/100</small></strong>
                <span>PRIORITY</span>
              </div>
            </div>
            <div className="intel-status-row">
              <span className="intel-status">{selected.drain.status}</span>
              {selected.overdue ? <span className="intel-status is-overdue">Overdue follow-up</span> : null}
              {selected.recurring ? <span className="intel-status is-recurring">Recurring issue</span> : null}
            </div>

            <section className="intel-follow-up">
              <div className="intel-follow-up-header">
                <span className="intel-follow-up-icon"><Sparkles size={18} /></span>
                <div>
                  <span className="intel-kicker">Recommended follow-up</span>
                  <strong>Next operational action</strong>
                </div>
              </div>
              <p className="intel-follow-up-action">{selected.nextAction}</p>
              <div className="intel-follow-up-reasons">
                {selected.explanation
                  .filter((reason) => !reason.startsWith("Current operational priority"))
                  .map((reason) => (
                    <div key={reason}>
                      <span className="intel-reason-marker" />
                      <span>{reason}</span>
                    </div>
                ))}
              </div>
            </section>

            <div className="intel-detail-grid">
              <div>
                <span>Condition</span>
                <strong>{selected.drain.condition}</strong>
              </div>
              <div>
                <span>Evidence status</span>
                <strong>{selected.drain.evidenceStatus}</strong>
              </div>
              <div>
                <span>Complaint history</span>
                <strong>{selected.complaintCount} linked · {selected.priorOutcomeCount} outcomes</strong>
              </div>
              <div>
                <span>Visible blockage</span>
                <strong>{selected.drain.visibleBlockage == null ? "Not recorded" : `${selected.drain.visibleBlockage}%`}</strong>
              </div>
              <div>
                <span>Last field observation</span>
                <strong>{formatDate(selected.drain.lastObservation)}</strong>
              </div>
              <div>
                <span>Work deadline</span>
                <strong>{selected.drain.deadlineAt ? formatDate(selected.drain.deadlineAt) : "No deadline set"}</strong>
              </div>
            </div>

            <div className="intel-actions">
              <label className="intel-status-select">
                <span>Track status</span>
                <select
                  onChange={(event) =>
                    onStatusChange(
                      selected.drain.id,
                      event.target.value as DrainRecord["status"],
                    )
                  }
                  value={selected.drain.status}
                >
                  {statusOptions.map((status) => (
                    <option key={status}>{status}</option>
                  ))}
                </select>
              </label>
            </div>

            <div className="intel-history">
              <div className="intel-subheading">
                <History size={16} />
                <h4>Operational history</h4>
              </div>
              {selected.history.length || selected.outcomes.length ? (
                <ul>
                  {selected.history.slice(0, 3).map((entry, index) => (
                    <li key={`${entry.drainId}-${entry.submittedAt}-${index}`}>
                      <span className="intel-history-dot" />
                      <div>
                        <strong>Complaint · {entry.issueType}</strong>
                        <small>{formatDate(entry.submittedAt)} · {entry.status}</small>
                      </div>
                    </li>
                  ))}
                  {selected.outcomes.slice(0, 3).map((entry, index) => (
                    <li key={`${entry.drainId}-${entry.timestamp}-${index}`}>
                      <span className="intel-history-dot outcome" />
                      <div>
                        <strong>Outcome · {entry.outcome}</strong>
                        <small>{formatDate(entry.timestamp)} · {entry.recommendation}</small>
                      </div>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="intel-empty">No earlier complaints or outcome records are linked to this drain.</p>
              )}
            </div>
          </article>
        ) : (
          <article className="intel-case-detail panel intel-empty">
            Select a drainage case to view its assessment.
          </article>
        )}
      </section>
    </div>
  );
}
