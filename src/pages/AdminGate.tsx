import GateScreen from '../components/GateScreen';
import { AdminDashboardView } from '../components/admin/AdminDashboardView';

// Admin gate (single-operator law): unfriendly-to-robots wrapper
// around the shared gate machinery in src/lib/gate.ts. The dashboard
// touches real database bridges, so the route itself must not be
// free. Real protection summary lives in DEPLOY.md (WAF rate rule +
// bridge binding); this gate is honest friction on a static host.
const GATE_HASH =
  (import.meta.env.VITE_ADMIN_PASSWORD_SHA as string | undefined)?.toLowerCase() || '';

export default function AdminGate() {
  return (
    <GateScreen
      sessionKey="syn_admin_ok"
      gateHash={GATE_HASH}
      envVarName="VITE_ADMIN_PASSWORD_SHA"
      headline="Operator access"
      blurb="Restricted ops tooling. Enter the operator key to proceed."
    >
      <AdminDashboardView />
    </GateScreen>
  );
}
