// Terms page — grounded in the actual license reality: the game code
// is free and open source, the site is provided as-is, admin tooling
// is private. No fake ToS legalese; honest boundaries in plain text.
export default function TermsPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="font-display text-3xl mb-2">Terms of Use</h1>
      <p className="text-sm text-ink-soft mb-10">Last updated: October 19, 2026</p>

      <div className="space-y-8 text-sm leading-relaxed text-ink/90">
        <section>
          <h2 className="font-display text-xl mb-2">What this is</h2>
          <p>
            Synmergia is a free, open-source game by dhaupin and contributors.
            Playing it in your browser or downloading a build costs nothing and
            requires no account.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Your license to play</h2>
          <p>
            The game's source code is licensed under its open-source license
            (see the repository's LICENSE file) — you may play, study, modify,
            and share it within that license's terms. The site itself, its
            text, and its design are © dhaupin; you may quote or reference it
            with attribution.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Acceptable use</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Don't attack the hosting (rate-scraping builds, hammering the downloads, or abusing GitHub/Cloudflare/itch.io's platforms).</li>
            <li>Don't redistribute the game under a different name without following the license terms.</li>
            <li>Don't misrepresent your own forks as official Synmergia releases or affiliation with the project.</li>
          </ul>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Availability and changes</h2>
          <p>
            This is an in-development game. Features change, worlds may reset,
            and builds may be temporarily unavailable — that's the nature of
            following a live project. Nothing on this site is offered as a paid
            service, so there is nothing to refund.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">No warranty</h2>
          <p>
            The game and site are provided "as is," without warranty of any
            kind. To the extent permitted by law, neither dhaupin nor
            contributors are liable for damages arising from their use.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Admin tooling</h2>
          <p>
            Anything under /admin on this site is restricted operator
            tooling for running the game's services, not part of the public
            game. Unauthorized access is prohibited and we log nothing about
            you — meaning attempts are visible to the server operator alone.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Contact</h2>
          <p>
            Questions, disputes, or takedown requests:{' '}
            <a href="https://github.com/dhaupin/synmergia/issues" target="_blank" rel="noreferrer" className="text-accent hover:underline">
              github.com/dhaupin/synmergia/issues
            </a>.
          </p>
        </section>
      </div>
    </div>
  );
}
