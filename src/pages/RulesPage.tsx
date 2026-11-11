// Rules page — the conduct law, in plain language. Grounded in the real
// moderation machinery the server ships (chat_service /report ->
// PlayerReporter; PermissionManager mute/kick/ban, where a ban may be
// temporary or effectively permanent). No fake legalese: the boundaries
// below are the ones the tools can actually enforce.
export default function RulesPage() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="font-display text-3xl mb-2">Rules of the World</h1>
      <p className="text-sm text-ink-soft mb-10">Last updated: November 4, 2026</p>

      <div className="space-y-8 text-sm leading-relaxed text-ink/90">
        <section>
          <h2 className="font-display text-xl mb-2">The short version</h2>
          <p>
            Play in good faith. Don't ruin the world for other people, don't
            cheat, and don't try to break the game or the server. That covers
            almost everything below.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Play fair</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>
              <strong>No cheating or exploits.</strong> Don't use third-party
              tools, modified clients, automation, or unintended bugs to gain an
              advantage. If you find a bug, report it instead of farming it.
            </li>
            <li>
              <strong>No exploiting the economy.</strong> Duping items, currency,
              or progress — by any method — is a ban.
            </li>
            <li>
              <strong>No tampering.</strong> Don't attack, overload, probe, or
              attempt to gain unauthorized access to the servers, the network, or
              other players' accounts.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Be decent to other people</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>
              <strong>No harassment or hate.</strong> Don't target people with
              abuse, threats, slurs, or sustained griefing.
            </li>
            <li>
              <strong>No real-world harm.</strong> Threats of violence, doxxing,
              or sharing someone's private information are never acceptable.
            </li>
            <li>
              <strong>Keep it in the game.</strong> Competition, PvP, and rivalry
              are part of the world; taking a grudge into real life is not.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Names and content</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>
              Character names and any text you put into the world must not
              impersonate staff, and must not be hateful, sexual, or otherwise
              designed to offend.
            </li>
            <li>
              Don't advertise, scam, or solicit other players for anything
              outside the game.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Enforcement</h2>
          <p>
            When a rule is broken, the moderation tools can mute you, kick you
            from the shard, or ban you. A ban may be temporary or effectively
            permanent. Serious or repeated violations — cheating, real-world
            threats, or attacks on the service — may be banned permanently and
            without warning.
          </p>
          <p className="mt-2">
            Enforcement is at the discretion of the maintainers, and a ban is not
            owed an appeal. We aim to be consistent and to explain a decision when
            we can.
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Reporting a problem</h2>
          <p>
            Report abuse, exploits, and bugs in-game with{' '}
            <code className="text-accent">/report</code>. Reports are reviewed by
            moderators. For anything urgent or server-level, open an issue at{' '}
            <a
              href="https://github.com/dhaupin/synmergia/issues"
              target="_blank"
              rel="noreferrer"
              className="text-accent hover:underline"
            >
              github.com/dhaupin/synmergia/issues
            </a>
            .
          </p>
        </section>

        <section>
          <h2 className="font-display text-xl mb-2">Changes</h2>
          <p>
            These rules live in this repository and change with the game. The
            updated date above moves only when the rules move.
          </p>
        </section>
      </div>
    </div>
  );
}
