import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

const root = document.getElementById('root')!;
const app = (
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

// Prestruct marks prerendered shells with data-server-rendered="true". Hydrate
// those so the static HTML is reused; plain dev/SPA loads still create a root.
if (root.dataset.serverRendered === 'true') {
  ReactDOM.hydrateRoot(root, app);
} else {
  ReactDOM.createRoot(root).render(app);
}
