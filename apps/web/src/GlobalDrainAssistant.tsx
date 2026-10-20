import { useMemo, useState, type FormEvent } from "react";
import type { ReactNode } from "react";
import {
  BrainCircuit,
  MessageCircle,
  Send,
  Sparkles,
  X,
} from "lucide-react";
import {
  analyzeDrainRecords,
  type DrainHistoryInput,
  type DrainIntelligenceInput,
  type DrainOutcomeInput,
} from "./intelligence";
import "./GlobalDrainAssistant.css";

interface GlobalDrainAssistantProps {
  drains: readonly DrainIntelligenceInput[];
  reports: readonly DrainHistoryInput[];
  outcomes: readonly DrainOutcomeInput[];
}

interface ChatMessage {
  role: "assistant" | "user";
  text: string;
}

interface ChatApiResponse {
  answer?: string;
  error?: string;
}

function isChatApiResponse(value: unknown): value is ChatApiResponse {
  return (
    typeof value === "object" &&
    value !== null &&
    ("answer" in value || "error" in value)
  );
}

function renderInlineFormatting(line: string): ReactNode[] {
  return line.split(/(\*\*[^*]+\*\*)/g).map((part, index) =>
    part.startsWith("**") && part.endsWith("**") ? (
      <strong key={`bold-${index}`}>{part.slice(2, -2)}</strong>
    ) : (
      <span key={`text-${index}`}>{part}</span>
    ),
  );
}

function renderAssistantText(text: string) {
  const blocks: ReactNode[] = [];

  text.split(/\r?\n/).forEach((rawLine, index) => {
    const line = rawLine.trim();
    if (!line) return;

    const markdownHeading = line.match(/^#{1,3}\s+(.+)$/);
    const boldHeading = line.match(/^\*\*([^*]{1,80})\*\*:?\s*(.*)$/);
    const plainHeading = line.match(/^([A-Z][^:]{0,50}):\s*$/);

    if (markdownHeading || boldHeading || plainHeading) {
      const title =
        markdownHeading?.[1] ?? boldHeading?.[1] ?? plainHeading?.[1] ?? "";
      const remainder = boldHeading?.[2]?.trim();
      blocks.push(
        <div className="global-assistant-heading" key={`heading-${index}`}>
          <strong>{title.replace(/\*\*/g, "")}</strong>
        </div>,
      );
      if (remainder) {
        blocks.push(
          <div className="global-assistant-line" key={`heading-content-${index}`}>
            {renderInlineFormatting(remainder)}
          </div>,
        );
      }
      return;
    }

    const bullet = line.match(/^(?:[-*•]|\d+[.)])\s+(.+)$/);
    blocks.push(
      <div
        className={`global-assistant-line${bullet ? " is-list-item" : ""}`}
        key={`line-${index}`}
      >
        {renderInlineFormatting(bullet?.[1] ?? line)}
      </div>,
    );
  });

  return blocks;
}

export default function GlobalDrainAssistant({
  drains,
  reports,
  outcomes,
}: GlobalDrainAssistantProps) {
  const [open, setOpen] = useState(false);
  const [question, setQuestion] = useState("");
  const [loading, setLoading] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      role: "assistant",
      text: "Ask about case priorities, drainage history, inspections, or follow-up actions. Qwen3 only receives the sanitized DrainRank records needed to answer.",
    },
  ]);
  const snapshot = useMemo(
    () => analyzeDrainRecords(drains, reports, outcomes),
    [drains, reports, outcomes],
  );

  const submitQuestion = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const value = question.trim();
    if (!value || loading) return;
    setLoading(true);
    setQuestion("");
    setMessages((previous) => [...previous, { role: "user", text: value }]);

    try {
      const response = await fetch("/api/drainrank/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          question: value,
          totals: {
            drains: drains.length,
            reports: reports.length,
            outcomes: outcomes.length,
          },
          cases: snapshot.cases.map((item) => ({
            id: item.drain.id,
            ward: item.drain.ward,
            location: item.drain.location,
            score: item.score,
            priorityBase: Math.round(item.drain.priority),
            recurrenceAdjustment: item.score - Math.round(item.drain.priority),
            complaintCount: item.complaintCount,
            priorOutcomeCount: item.priorOutcomeCount,
            status: item.drain.status,
            issueType: item.drain.issueType,
            condition: item.drain.condition,
            evidenceStatus: item.drain.evidenceStatus,
            lastObservation: item.drain.lastObservation,
            deadlineAt: item.drain.deadlineAt ?? null,
            explanation: item.explanation,
            recommendedNextAction: item.nextAction,
            history: item.history.map((entry) => ({
              issueType: entry.issueType,
              status: entry.status,
              submittedAt: entry.submittedAt,
            })),
            outcomes: item.outcomes.map((entry) => ({
              outcome: entry.outcome,
              timestamp: entry.timestamp,
            })),
          })),
        }),
      });

      const result: unknown = await response.json();
      if (!isChatApiResponse(result)) {
        throw new Error(`DrainRank AI returned an unexpected response (HTTP ${response.status}).`);
      }
      if (!response.ok) {
        throw new Error(result.error ?? `DrainRank AI request failed (HTTP ${response.status}).`);
      }
      if (typeof result.answer !== "string" || !result.answer.trim()) {
        throw new Error("DrainRank AI returned an empty answer.");
      }
      setMessages((previous) => [
        ...previous,
        { role: "assistant", text: result.answer as string },
      ]);
    } catch (error) {
      const message =
        error instanceof Error
          ? error.message
          : "DrainRank AI request failed unexpectedly.";
      setMessages((previous) => [
        ...previous,
        {
          role: "assistant",
          text: `Unable to get a Qwen3 response. ${message}`,
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="global-drain-assistant">
      {open ? (
        <section
          aria-label="DrainRank work assistant"
          aria-modal="false"
          className="global-assistant-panel"
          role="dialog"
        >
          <header className="global-assistant-header">
            <div>
              <span><BrainCircuit size={16} /> DrainRank assistant</span>
              <small><Sparkles size={12} /> Qwen3 8B · local Ollama</small>
            </div>
            <button
              aria-label="Close DrainRank assistant"
              onClick={() => setOpen(false)}
              type="button"
            >
              <X size={18} />
            </button>
          </header>
          <div className="global-assistant-messages" aria-live="polite">
            {messages.map((message, index) => (
              <div
                className={`global-assistant-message ${message.role}`}
                key={`${message.role}-${index}`}
              >
                {message.role === "assistant"
                  ? renderAssistantText(message.text)
                  : message.text}
              </div>
            ))}
            {loading ? (
              <div className="global-assistant-message assistant" role="status">
                Qwen3 is analyzing the drainage records…
              </div>
            ) : null}
          </div>
          <form className="global-assistant-form" onSubmit={submitQuestion}>
            <input
              aria-label="Ask a DrainRank work question"
              disabled={loading}
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Ask about a drain or work item…"
              value={question}
            />
            <button
              aria-label="Send question"
              disabled={!question.trim() || loading}
              type="submit"
            >
              <Send size={16} />
            </button>
          </form>
          <p className="global-assistant-note">
            Personal and unrelated requests are refused. Only allowlisted work records are sent to Ollama on this device.
          </p>
        </section>
      ) : null}
      <button
        aria-expanded={open}
        aria-label={open ? "Close DrainRank assistant" : "Open DrainRank assistant"}
        className="global-assistant-trigger"
        onClick={() => setOpen((current) => !current)}
        type="button"
      >
        {open ? <X size={20} /> : <MessageCircle size={20} />}
        <span>{open ? "Close" : "Ask DrainRank"}</span>
      </button>
    </div>
  );
}
