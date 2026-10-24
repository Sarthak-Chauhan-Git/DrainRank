import App from "./App";
import AuthGate from "./AuthGate";

export default function ProtectedDashboard() {
  return (
    <AuthGate>
      <App />
    </AuthGate>
  );
}
