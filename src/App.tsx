import React, { useState, useEffect } from 'react';
import { PortalHeader, PortalMode } from './components/PortalHeader';
import { GodotClientView } from './components/wasm/GodotClientView';
import { AdminDashboardView } from './components/admin/AdminDashboardView';

// Synmergia Web Portal — two surfaces only (wasm-first workflow):
//   1. Godot WASM: the real game client, served from /web/.
//   2. Admin & Ops: bridge-backed GM/monitoring tooling.
// The legacy 2D companion client (GameCanvas + WebSocket mirror +
// bridge telemetry) was removed as tech debt; the bridge service stays
// because the admin dashboard is the one honest consumer of it.
export default function App() {
  const [portalMode, setPortalMode] = useState<PortalMode>('wasm');
  const [crossOriginIsolated, setCrossOriginIsolated] = useState<boolean>(false);

  useEffect(() => {
    setCrossOriginIsolated(typeof window !== 'undefined' && Boolean(window.crossOriginIsolated));
  }, []);

  return (
    <div
      id="synmergia-root"
      className="relative w-screen h-screen overflow-hidden bg-slate-950 font-sans select-none flex flex-col"
    >
      <PortalHeader
        currentMode={portalMode}
        onSelectMode={setPortalMode}
        crossOriginIsolated={crossOriginIsolated}
      />

      {portalMode === 'wasm' && <GodotClientView />}
      {portalMode === 'admin' && <AdminDashboardView />}
    </div>
  );
}
