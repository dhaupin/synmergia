// Privacy page — the honesty law in legal form. Every claim below is
// drawn from what the client code actually does (audited 2026-10-19):
// no accounts, no analytics, no cookies beyond engine storage, local
// saves only. If a future change violates a line here, the change or
// the page must move first.
export default function PrivacyPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="font-display text-3xl mb-2">Privacy Policy</h1>
      <p className="text-sm text-ink-soft mb-10">Last updated: October 19, 2026</p>

      <div className="space-y-8 text-sm leading-relaxed text-ink/90">
        <section>
          <h2 className="font-display text-xl mb-2">The short version</h2>
          <p>
            Synmergia collects nothing. There are no accounts, no analytics, no
            tracking pixels, no advertising, and no server-side profiles of
            players on this website. We can't sell what we don't have.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">What is stored on your device</h2>
          <p>
            The game engine (Godot compiled to WebAssembly) uses standard browser
            storage to keep your local game progress, graphics settings, and the
            downloaded game files (an engine binary and a content pack) so repeat
            visits load faster. This is functionally equivalent to cookies/local
            storage and lives entirely on your device. Clearing your browser's
            site data removes it and resets any local progress.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">What leaves your device</h2>
          <p>
            When you load the game, your browser downloads the game files from
            our host (Cloudflare and/or itch.io) and from GitHub, which serves
            the open-source code repository. Standard web infrastructure may log
            your IP address and request details for security and abuse
            prevention; we do not use those logs for advertising or profiling.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Third parties involved</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Cloudflare — hosts the website and game files (privacy: cloudflare.com/privacypolicy/)</li>
            <li>GitHub — hosts the open-source repository (privacy:docs.github.com/en/site-policy/privacy-policies)</li>
            <li>itch.io — may host a downloadable version of the game client (privacy: itch.io/docs/general/privacy)</li>
          </ul>
          <p className="mt-2">
            These providers process data under their own policies; we do not send
            them anything beyond your normal web requests.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Children</h2>
          <p>
            Synmergia is a general-audience game with no chat-based targeting and
            no data collection, but it is not directed at children under 13. If
            you are a parent with a concern, contact us and we will help.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Your rights</h2>
          <p>
            Because we collect nothing server-side, there is nothing to export
            or delete beyond what sits in your own browser — clear site data and
            you are fully forgotten. GDPR/CCPA regimes apply trivially: the data
            controller holds zero personal data.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Changes</h2>
          <p>
            If the game grows accounts, chat, or telemetry, this page changes
            with it — in this repo, reviewable as code. The updated date above
            moves only when the behavior moves.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Contact</h2>
          <p>
            Open an issue at{' '}
            <a href="https://github.com/dhaupin/synmergia/issues" target="_blank" rel="noreferrer" className="text-accent hover:underline">
              github.com/dhaupin/synmergia/issues
            </a>{' '}
            for any privacy question.
          </p>
        </section>
      </div>
    </div>
  );
}
