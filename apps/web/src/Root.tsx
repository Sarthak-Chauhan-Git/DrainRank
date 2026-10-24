import { lazy, Suspense } from "react";
import DebugDashboard from "./DebugDashboard";

const ProtectedDashboard = lazy(() => import("./ProtectedDashboard"));
const isDebugRoute = window.location.pathname.replace(/\/+$/, "") === "/debug";

export default function Root() {
  if (isDebugRoute) return <DebugDashboard />;
  return (
    <Suspense fallback={<main className="backend-gate">Loading dashboard…</main>}>
      <ProtectedDashboard />
    </Suspense>
  );
}
