import {
  BrowserRouter,
  Routes,
  Route,
  useLocation,
} from 'react-router-dom';
import { useEffect, useRef } from 'react';
import { mountIslands } from 'prestruct/islands';
import { islands } from './AppIslands';
import { routeTitle } from './lib/routeMeta';

import SiteLayout from './components/SiteLayout';
import LanderPage from './pages/LanderPage';
import PlayPage from './pages/PlayPage';
import CodexPage from './pages/CodexPage';
import ExperiencesPage from './pages/ExperiencesPage';
import LorePage from './pages/LorePage';
import OpenSourcePage from './pages/OpenSourcePage';
import PrivacyPage from './pages/PrivacyPage';
import TermsPage from './pages/TermsPage';
import RulesPage from './pages/RulesPage';
import AccessibilityPage from './pages/AccessibilityPage';
import AgentsPage from './pages/AgentsPage';
import NotFoundPage from './pages/NotFoundPage';
import AdminGate from './pages/AdminGate';

// ===== SSR-safe layer (imports cleanly under the prerender's
// StaticRouter; no BrowserRouter inside) =====

function ScrollToTop() {
  const location = useLocation();
  const isFirst = useRef(true);
  useEffect(() => {
    if (typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
    }
    // Announce the new route to assistive tech: update the document title
    // (WCAG 2.4.2 Page Titled) and move focus to the main landmark so the
    // next Tab starts in the new content (WCAG 2.4.3 Focus Order). Skipped
    // on the first render so a fresh page load keeps its natural focus.
    if (typeof document !== 'undefined') {
      document.title = routeTitle(location.pathname);
      if (!isFirst.current) {
        const main = document.getElementById('main');
        if (main) main.focus({ preventScroll: true });
      }
    }
    isFirst.current = false;
    // Scan after every route change, including the first client render.
    // mountIslands is idempotent (WeakSet), so this is safe alongside the
    // post-unlock scan in PlayPage.
    const t = setTimeout(() => mountIslands(islands), 0);
    return () => clearTimeout(t);
  }, [location.pathname]);
  return null;
}

export function AppRoutes() {
  return (
    <>
      <ScrollToTop />
      <Routes>
        <Route element={<SiteLayout />}>
          <Route path="/" element={<LanderPage />} />
          <Route path="/experiences" element={<ExperiencesPage />} />
          <Route path="/codex" element={<CodexPage />} />
          <Route path="/lore" element={<LorePage />} />
          <Route path="/opensource" element={<OpenSourcePage />} />
          <Route path="/play" element={<PlayPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="/rules" element={<RulesPage />} />
          <Route path="/accessibility" element={<AccessibilityPage />} />
          <Route path="/agents" element={<AgentsPage />} />
          <Route path="/admin" element={<AdminGate />} />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </>
  );
}

// ===== Client entry: BrowserRouter lives only in the browser. =====

export default function App() {
  return (
    <BrowserRouter>
      <AppRoutes />
    </BrowserRouter>
  );
}
