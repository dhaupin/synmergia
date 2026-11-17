// Privacy page — the honesty law in legal form. Every claim below is
// drawn from what the code actually does: accounts are email-bound
// (guest play is retired), passwords are hashed, sessions record IP and
// user agent, and gameplay is monitored for exploits. No third-party
// analytics, advertising, or tracking pixels. If a future change
// violates a line here, the change or the page must move first.
export default function PrivacyPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="font-display text-3xl mb-2">Privacy Policy</h1>
      <p className="text-sm text-ink-soft mb-10">Last updated: November 17, 2026</p>

      <div className="space-y-8 text-sm leading-relaxed text-ink/90">
        <section>
          <h2 className="font-display text-xl mb-2">The short version</h2>
          <p>
            We run the game and its accounts. To do that we hold the minimum an
            account needs — your email, a display name, and a hashed password —
            plus session records and gameplay telemetry used to keep the world
            fair. There are no third-party analytics, no advertising, and no
            tracking pixels. We can't sell what we don't have.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">What we hold server-side</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>
              <strong>Account</strong> — username, email, display name, and a
              salted password hash (PBKDF2, SHA-256, 4096 iterations). We never
              store or see your plaintext password.
            </li>
            <li>
              <strong>Session</strong> — a token hash, plus the IP address and
              user agent of the session, kept as an audit and recovery trail.
            </li>
            <li>
              <strong>Character</strong> — your in-world progress: name, species,
              class, level, experience, gold, and position.
            </li>
            <li>
              <strong>Gameplay telemetry</strong> — movement and action rates are
              monitored by an anti-cheat service so exploits are detected. This
              is gameplay data, not a profile of you as a person.
            </li>
          </ul>
          <p className="mt-2">
            Guest play is retired: every account is email-bound. That email is
            used for the account itself, not for marketing.
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
            the open-source code repository. Your account credentials and
            gameplay travel to the game server so the authoritative server can
            run the world. Standard web infrastructure may log your IP address
            and request details for security and abuse prevention; we do not use
            those logs for advertising or profiling.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Third parties involved</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Cloudflare — hosts the website and game files, and fronts the server (privacy: cloudflare.com/privacypolicy/)</li>
            <li>GitHub — hosts the open-source repository (privacy: docs.github.com/en/site-policy/privacy-policies)</li>
            <li>itch.io — may host a downloadable version of the game client (privacy: itch.io/docs/general/privacy)</li>
          </ul>
          <p className="mt-2">
            These providers process data under their own policies; we do not send
            them anything beyond your normal web requests. No analytics or
            advertising provider is embedded in the game or the site.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Children</h2>
          <p>
            Synmergia is a general-audience game, but because it holds accounts
            it is not directed at children under 13. If you are a parent with a
            concern, contact us and we will help.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Your rights</h2>
          <p>
            You can ask us to export or delete your account and its data. Because
            we hold only what the account needs, deletion removes the account,
            its sessions, and its characters. Clearing your browser's site data
            additionally removes anything kept locally.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Changes</h2>
          <p>
            If the game adds telemetry, chat, or third-party services, this page
            changes with it — in this repo, reviewable as code. The updated date
            above moves only when the behavior moves.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Contact</h2>
          <p>
            Open an issue at{' '}
            <a href="https://github.com/dhaupin/synmergia/issues" target="_blank" rel="noreferrer" className="text-accent underline underline-offset-2 hover:text-accent-deep">
              github.com/dhaupin/synmergia/issues
            </a>{' '}
            for any privacy question.
          </p>
        </section>
      </div>
    </div>
  );
}
