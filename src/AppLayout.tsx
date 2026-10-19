import { AppRoutes } from './App';

// AppLayout (prestruct law): NO BrowserRouter here, ever. The prerender
// script ssrLoadModule()s this file and wraps <AppLayout /> in a
// StaticRouter; the browser entry (main.tsx -> App) supplies the
// BrowserRouter. This split guarantees a single react-router-dom
// instance through Vite's unified SSR module registry — the exact
// failure mode prestruct's AGENTS.md documents (two router contexts
// silently render every route as '/').
export default function AppLayout() {
  return <AppRoutes />;
}
