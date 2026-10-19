import { Link } from 'react-router-dom';

export default function NotFoundPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-24 text-center">
      <p className="text-xs tracking-[0.3em] uppercase text-accent/80 mb-4">Lost in the void</p>
      <h1 className="font-display text-4xl mb-4">404</h1>
      <p className="text-ink-soft mb-8">
        This page doesn't exist — the planet's faces are numbered and this
        isn't one of them.
      </p>
      <Link
        to="/"
        className="px-5 py-2.5 rounded-lg bg-accent text-paper font-semibold hover:bg-accent-deep transition-colors"
      >
        Back to the homelands
      </Link>
    </div>
  );
}
