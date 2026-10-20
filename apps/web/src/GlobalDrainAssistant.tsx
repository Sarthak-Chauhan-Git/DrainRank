import { useMemo, useState, type FormEvent } from "react";
import { BrainCircuit, MessageCircle, Send, X } from "lucide-react";
import {
  analyzeDrainRecords,
  answerDrainRankQuestion,
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

export default function GlobalDrainAssistant({
  drains,
  reports,
  outcomes,
}: GlobalDrainAssistantProps) {
  const [open, setOpen] = useState(false);
  const [question, setQuestion] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      role: "assistant",
      text: "Ask about drainage case priorities, history, evidence, or overdue work. I can only help with DrainRank work.",
    },
  ]);
  const snapshot = useMemo(
    () => analyzeDrainRecords(drains, reports, outcomes),
    [drains, reports, outcomes],
  );

  const submitQuestion = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const value = question.trim();
    if (!value) return;
    setMessages((previous) => [
      ...previous,
      { role: "user", text: value },
      { role: "assistant", text: answerDrainRankQuestion(value, snapshot.cases) },
    ]);
    setQuestion("");
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
              <small>Work-only · local records</small>
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
                {message.text}
              </div>
            ))}
          </div>
          <form className="global-assistant-form" onSubmit={submitQuestion}>
            <input
              aria-label="Ask a DrainRank work question"
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Ask about a drain or work item…"
              value={question}
            />
            <button
              aria-label="Send question"
              disabled={!question.trim()}
              type="submit"
            >
              <Send size={16} />
            </button>
          </form>
          <p className="global-assistant-note">
            Personal and unrelated requests are refused. No external AI service is connected.
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
