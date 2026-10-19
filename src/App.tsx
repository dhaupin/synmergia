import {
  BrowserRouter,
  Routes,
  Route,
  useLocation,
} from 'react-router-dom';
import { useEffect } from 'react';

import SiteLayout from './components/SiteLayout';
import LanderPage from './pages/LanderPage';
import PlayPage from './pages/PlayPage';
import PrivacyPage from './pages/PrivacyPage';
import TermsPage from './pages/TermsPage';
import NotFoundPage from './pages/NotFoundPage';
import AdminGate from './pages/AdminGate';

// ===== SSR-safe layer (imports cleanly under the prerender's
// StaticRouter; no BrowserRouter inside) =====

function ScrollToTop() {
  const location = useLocation();
  useEffect(() => {
    if (typeof window !== 'undefined') {
      window.scrollTo({ top: 0, behavior: 'instant' as ScrollBehavior });
    }
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
          <Route path="/play" element={<PlayPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          <Route path="/terms" element={<TermsPage />} />
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
