# PRD: Daily Class Blessing - As-Built and Remaining Work

> **Status:** PARTIAL (as built 2026-11-16; core loop shipped, finish list below)
> **Law:** `labs/prd-psy.md` sections 4 and 8 are the design source. This
> document is the implementation receipt and the handoff for the remaining
> gaps; where this document and code disagree, code wins.
> **Naming:** the feature is the **Daily Class Blessing** internally. The
> player-facing voice may say "the wheel names X" or "carries the sky's
> favor"; never faith language (`labs/prd-psy.md` section 4). The data id is
> `blessing_balance`, the service is `SignService`, the visual is
> `BlessedMark`.

## 1. What Is Shipped

| Piece | Truth |
| --- | --- |
| Wheel | `SignService.get_blessed_class_id(day)` shuffles the playable, non-GM classes once per round (seed = round epoch) and walks the permutation. Every class blesses once per round by construction. |
| Earn gate | `SignService.is_blessing_active(day)` is true only when that day is Ancient-unlocked. `is_class_blessed(class_id, day)` requires both the wheel pick and the earned day. No solve, no buff. |
| Payout record | `game/data/balance/blessing_balance.tres` (`BlessingBalanceData`): `damage_multiplier`, `heal_multiplier`, `xp_multiplier`, `level_bonus`. `DataService.get_blessing_balance()` owns the record; `SignService` exposes compatibility getters. |
| Damage | `CombatMath.calculate_hit()` stamps `blessing_multiplier`; `CombatMath.calculate_damage()` applies it. Covers the standard skill/basic-attack hit table. |
| Healing | `Skill.calculate_healing()` multiplies direct heals for a blessed class. |
| XP | `KillRewards._grant_xp()` multiplies kill XP for a blessed class. |
| Effective level | `CharacterData.get_stat_total()` adds `level_bonus` when computing class stats for a blessed class. It does not change the body's displayed `level`. |
| Almanac | `ui/components/sky_almanac_ui.gd` shows today's class/live state and tomorrow's preview through the same wheel data. |
| Visual | `entities/blessed_mark.gd`: sky-cyan mote ring + halo, lit only while the day is earned. Titles/chat use the `(*)` sigil in front of the prefix (`TitleService`, `ChatService`). |
| Announcements | `SignService` fires code-assembly (tomorrow preview), dawn (live), and login (personal) notifications through `NotifKind.CLASS_BLESSED`. |
| Receipts | `game/tests/test_daily_class_blessing.gd`, `game/tests/test_blessed_mark.gd`, and `probe_ancient_loop.gd` cover the wheel/earn gate and the three main consumers. |

## 2. The Canonical Rules

1. **The sky pays for solved work only.** A day's blessing is inert until the
   previous day's four glyphs were assembled. Agents may reveal the code
   outside the game process; the code is the lottery ticket.
2. **One class, one day, whole shard.** The wheel is deterministic from data
   and the round epoch; no server may reroll the order.
3. **No power purchase.** The blessing is earned by the Concord loop, never
   sold, never granted by a vendor, and never a permanent account stat.
4. **Bout-local stats stay bout-local.** The blessing's effective level is a
   stat calculation, not a rewrite of `level`; arena power normalization
   remains the instance's separate modifier.
5. **A blessed body is still its own class.** Alts and characters of the named
   class both receive it; a different class on the same account does not.

## 3. Gaps To Finish (priority order)

### P1 - Make the damage payout total

The blessing damage multiplier currently rides only the `calculate_hit()` ->
`calculate_damage()` lane. These damage paths bypass that lane and therefore
do **not** receive the blessing:

- `game/core/combat/projectile.gd` (`_calculate_damage`, chain and explosion
  damage call `health_component.take_damage` directly).
- Damage-over-time ticks and direct `take_damage` trap/environment paths.
- Any future source that calls `HealthComponent.take_damage` without a
  `CombatMath` hit result.

**Finish:** give every hostile damage source one small helper that resolves
the caster's blessing multiplier (or make all sources pass through a shared
"outgoing damage" seam). Add a receipt proving a projectile and a DoT land
1.2x for a blessed class, not merely that `calculate_damage()` does.

### P1 - Make healing and XP honest across all sources

- `Skill.calculate_healing()` covers direct heals. HoT ticks use the raw
  `hot_heal` value and are not multiplied.
- `KillRewards._grant_xp()` covers kill XP only. Quest, gathering, crafting,
  and any other XP grant need an explicit product decision: bless kill XP
  only (document it) or route every grant through the same helper.

**Finish:** either bless the HoT tick at application/ticks with a stamped
multiplier, or document the exclusion in the PRD and tooltip. Do not leave the
player-facing "+20% healing" claim broader than the code.

### P2 - Show the state everywhere the player fights

`BlessedMark` is parented only by `globe_world.gd` (`_setup_blessed_marks`).
The moon and underworld worlds have no mark setup, and there is no persistent
HUD chip outside the almanac. A blessed player who travels should not lose the
only visible sign of the payout.

**Finish:** one world-entry seam that attaches the mark (or a HUD chip), not
one copy per world scene. The mark already live-checks the earn state; reuse
it. Add a probe that travels between worlds and reads the mark state.

### P2 - Fix the documentation debt around the feature

`labs/prd-psy.md` contains the Daily Class Blessing section twice (an earlier
merge duplicated section 8). This document is the current implementation
receipt; the PRD still needs its duplicate removed and its "shipped" claims
reconciled with the gaps above.

### P3 - Tooltip and voice pass

- The payout notification says "+20% might, +5 levels, +20% XP" but omits
  healing. Add healing to the player-facing summary or deliberately keep it
  in the almanac detail.
- Verify all copy uses the section 4 observational vocabulary (no "holy",
  "sacred", "prayer", or supernatural "curse"). The almanac and notifications
  are the current risk surface.
- Add the live state, remaining time until dawn, and tomorrow's preview to
  one HUD/almanac read; do not create a second wheel calculator.

## 4. Acceptance For The Finish Pass

- [ ] A blessed class's projectile, DoT, direct skill, and basic attack all
      deal the record's `damage_multiplier`; an unblessed class deals 1.0.
- [ ] Direct heals and HoT ticks follow one documented rule; the test names
      which is included.
- [ ] XP follows one documented rule across kill/quest/craft/gather grants.
- [ ] Mark/HUD state follows the player into every world, and clears at dawn
      when the earn state ends.
- [ ] `prd-psy.md` has one blessing section, with a pointer to this receipt.
- [ ] `test_daily_class_blessing`, `test_blessed_mark`, and the new source
      coverage are green in `scripts/godot_test_runner.sh`.
- [ ] No blessing value is purchasable; the earn gate still requires the
      previous day's Ancient unlock.

## 5. Receipts To Re-Run

```sh
sh ./scripts/godot_test_runner.sh test_daily_class_blessing test_blessed_mark
sh ./scripts/godot_test_runner.sh probe_ancient_loop
```

The blessing balance is data, not code:

```text
game/data/balance/blessing_balance.tres
game/core/schemas/blessing_balance_data.gd
game/core/services/sign_service.gd
game/core/services/combat_math.gd (calculate_hit -> calculate_damage)
game/core/combat/skill.gd (calculate_healing)
game/core/services/kill_rewards.gd (_grant_xp)
game/core/schemas/character_data.gd (get_stat_total)
game/entities/blessed_mark.gd
game/ui/components/sky_almanac_ui.gd
```
