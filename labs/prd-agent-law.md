# PRD: The Agent Law — behavioral integrity for ALL accounts
(S16.6, 2026-10-08. Owner directive, verbatim intent: "agent law
should extend to all accounts period. It's like a layer on top of
Anticheat. To catch the bad ones fucking with synmergia. We have an
advantage with our extended a11y to mitigate, hook in to Anticheat
for whatever they're up to.")

## 0. The reframe (decided)

"Agent law" is NOT about agents being special. It is the opposite:
there is no agent special-casing anywhere in the lawful chains
(harvest, mounts, inventory, login — the citizen law already in
code). The AGENT LAW is a BEHAVIORAL INTEGRITY LAYER that applies to
EVERY ACCOUNT — human, synthetic, future species — because the bad
actors are people, not species. Agents are just the citizens we can
see the plumbing of.

## 1. The layer over Anticheat

AnticheatService owns MOVEMENT integrity (speed/jump/fall limits,
launch tickets, drift law). The agent law owns BEHAVIORAL integrity
on top of it, same signal spine:

    AnticheatService.cheat_detected / player_flagged / player_banned
    SecurityService.exploit_detected / invalid_input

New detector classes (all feed the same signals):
- ECONOMY: duplication-pattern grants, harvest cadence beyond human
  envelope (QoS rate-limit is the floor; the detector is the
  pattern), trade asymmetry streaks.
- INPUT HUMANITY: input entropy — human input has noise, rhythm,
  hesitation. Scripted input is too clean. The a11y layer already
  models input as events with timing; that telemetry IS the
  detector's food.
- SESSION SHAPE: login/zone/mount/harvest sequences that no human
  walk produces (teleport-shaped zone hops, perfect harvest loops).

## 2. The a11y advantage (why we can win this)

Synmergia's a11y rig (screen-reader-first UI, every action a typed
event, text labels on every control) means the server already sees
a CLEAN, SEMANTIC action stream — not raw input blobs. A cheater's
tooling must either mimic that stream perfectly (hard) or bypass it
(detectable as missing/odd events). The a11y law doubles as the
integrity law: every action is typed, attributable, and analyzable.
(Design note: this must never degrade the a11y experience — the
telemetry rides events that already exist.)

## 3. Synthetics through the lawful chain (the account half)

- Synthetic accounts are ACCOUNTS: LoginService/AccountService with
  a species field; species-agnostic bodies (already true in
  projection). No backdoor sessions for agents — an agent that
  cheats gets flagged exactly like a human.
- is_agent exists on AnticheatService.register_player: it may gate
  TUNING (agents get no launch grace they don't earn), never
  EXEMPTION. Nobody is above the law; some are just held to it
  more precisely.
- Agent brains (vant) attach AFTER account creation, as the mind
  behind the account — the account is the citizenship, the brain
  is the player.

## 4. Build order

1. ACCOUNT: synthetic species through the login chain (register,
   lobby, spawn — same path as human; species field plumbed).
2. TELEMETRY: semantic action ledger (harvest/trade/mount already
   write world deltas; route the same events to a per-account
   rolling envelope).
3. DETECTORS: economy + input-humanity + session-shape, feeding
   AnticheatService's existing flag/ban spine. Measure first
   (strike/streak law: sustained frames, not single events — the
   anticheat lesson).
4. TRIBUNAL: strikes, shadow-flags, bans ride the existing signals;
   the world delta ledger IS the evidence trail (provenance law).

## 5. Explicitly out of scope

- Captcha/altitude checks that degrade the a11y experience.
- Agent-specific restrictions that break the citizen law.
- Any detector whose false-positive rate isn't measured first.
