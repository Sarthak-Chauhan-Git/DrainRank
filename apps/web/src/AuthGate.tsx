import { useEffect, useState } from "react";
import type { FormEvent, ReactNode } from "react";
import { DashboardSessionContext } from "./dashboardSession";
import { supabase, supabaseConfigurationError } from "./supabase";

type GateState =
  | { status: "loading" }
  | { status: "signed-out" }
  | { status: "authorized"; email: string }
  | { status: "denied"; message: string };

export default function AuthGate({ children }: { children: ReactNode }) {
  const [gate, setGate] = useState<GateState>({ status: "loading" });
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const client = supabase;

  const signOut = async () => {
    if (!client) return;
    try {
      const { error: signOutError } = await client.auth.signOut();
      if (signOutError) {
        setError(`Could not sign out: ${signOutError.message}`);
      }
    } catch (signOutError) {
      setError(`Could not sign out: ${String(signOutError)}`);
    }
  };

  useEffect(() => {
    if (!client) return;
    let active = true;
    let authCheck = 0;

    const authorizeSession = async (session: {
      user: { id: string; email?: string };
    } | null) => {
      const check = ++authCheck;
      if (!session) {
        if (active) setGate({ status: "signed-out" });
        return;
      }

      const { data, error: membershipError } = await client
        .from("dashboard_admins")
        .select("user_id")
        .eq("user_id", session.user.id)
        .maybeSingle();

      if (!active || check !== authCheck) return;
      if (membershipError) {
        setGate({
          status: "denied",
          message: `Could not verify dashboard access: ${membershipError.message}`,
        });
      } else if (!data) {
        setGate({
          status: "denied",
          message:
            "This account is not authorized for the municipal dashboard. Ask an administrator to grant dashboard access.",
        });
      } else {
        setGate({
          status: "authorized",
          email: session.user.email ?? "Signed-in administrator",
        });
      }
    };

    const { data } = client.auth.onAuthStateChange((_event, session) => {
      void authorizeSession(session);
    });

    void client.auth
      .getSession()
      .then(({ data: sessionData, error: sessionError }) => {
        if (sessionError) throw sessionError;
        return authorizeSession(sessionData.session);
      })
      .catch((sessionError: unknown) => {
        if (active) {
          setGate({
            status: "denied",
            message: `Could not restore the Supabase session: ${String(sessionError)}`,
          });
        }
      });

    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [client]);

  if (supabaseConfigurationError || !client) {
    return <GateMessage message={supabaseConfigurationError ?? "Supabase is unavailable."} />;
  }

  if (gate.status === "loading") {
    return (
      <GateMessage message="Connecting to the municipal backend…" busy />
    );
  }

  if (gate.status === "authorized") {
    return (
      <DashboardSessionContext.Provider value={{ email: gate.email }}>
        <div className="authenticated-shell">
          {error ? <p className="backend-error">{error}</p> : null}
          <div className="auth-session-bar">
            <span>{gate.email}</span>
            <button type="button" onClick={() => void signOut()}>
              Sign out
            </button>
          </div>
          {children}
        </div>
      </DashboardSessionContext.Provider>
    );
  }

  if (gate.status === "denied") {
    return (
      <GateMessage
        message={error ?? gate.message}
        action={
          <button
            type="button"
            className="btn-secondary"
            onClick={() => void signOut()}
          >
            Sign out
          </button>
        }
      />
    );
  }

  const signIn = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const { error: signInError } = await client.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (signInError) {
        setError(`Sign-in failed: ${signInError.message}`);
        return;
      }
      setPassword("");
    } catch (signInError) {
      setError(`Sign-in failed: ${String(signInError)}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="backend-gate">
      <form className="backend-login panel" onSubmit={signIn}>
        <h1>DrainRank dashboard</h1>
        <p>Sign in with your authorized municipal staff account.</p>
        <label>
          Official email
          <input
            autoComplete="username"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </label>
        <label>
          Password
          <input
            autoComplete="current-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>
        {error ? <p className="backend-error">{error}</p> : null}
        <button className="btn-primary" disabled={busy} type="submit">
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </main>
  );
}

function GateMessage({
  message,
  busy = false,
  action,
}: {
  message: string;
  busy?: boolean;
  action?: ReactNode;
}) {
  return (
    <main className="backend-gate">
      <section className="backend-login panel" aria-live="polite">
        {busy ? <div className="backend-spinner" aria-hidden="true" /> : null}
        <h1>DrainRank dashboard</h1>
        <p>{message}</p>
        {action}
      </section>
    </main>
  );
}
