// Generate Synmergia's `relations.json` from the tree, plus the human curation.
//
// The graph is DERIVED (tresridge's resolution rule seeds it); the curation below
// is the part no rule can infer - which residue field is a real edge, which is a
// host-owned literal, and which targets are unions. This is the whole adoption
// step: run `graph`, correct the residue, commit the result.
//
// Usage:  TRESRIDGE=/path/to/tresridge/bin/cli.mjs node scripts/gen-relations.mjs [--write]
// Without --write it prints the declaration to stdout for review.

import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..');
const DATA = join(REPO, 'game', 'data');
const OUT = join(DATA, 'relations.json');
// Invoke the sibling's PUBLIC CLI, never its internals - the interop law is
// "no host imports a sibling to check a sibling; it invokes the sibling's CLI".
// The standard is not on npm yet, so there is no bare name to fall back on:
// an unset TRESRIDGE is a named refusal here, not a module-resolution stack.
const CLI = process.env.TRESRIDGE;
if (!CLI) {
  console.error('gen-relations: TRESRIDGE is unset - point it at the standard\'s CLI.');
  console.error('  TRESRIDGE=/path/to/tresridge/bin/cli.mjs node scripts/gen-relations.mjs [--write]');
  process.exit(2);
}

// ---------------------------------------------------------------------------
// The curation. Every entry is a decision the resolution rule could not make.
// ---------------------------------------------------------------------------

// An item id lives across several directories - `wep_iron_sword` (weapons),
// `arm_leather_chest` (armors), `res_ore_silver` (resources), ... - so the target
// is a UNION family, not one directory.
const ITEM_FAMILIES = ['weapons', 'armors', 'accessories', 'resources', 'items', 'consumables', 'gliders'];

// Residue fields: the rule could not name a target, so a human does.
// `target` names a family (or union); `literal` means a host-owned id that is not
// a reference at all (a service class, a visual stem, an empty slot).
const CURATED = {
  'enemies.equipment_ids': { target: ['weapons', 'armors'], kind: 'refs' },
  'hordes.boss_template_id': { target: ['enemies', 'world_bosses'], kind: 'ref' },
  'world_bosses.boss_template_id': { target: ['enemies', 'world_bosses'], kind: 'ref' },
  'hordes.waves.boss_template_id': { target: ['enemies', 'world_bosses'], kind: 'nested' },
  'spawn_tables.entries.template_id': { target: 'enemies', kind: 'nested' },
  'skills.effects.effect_id': { target: 'status_effects', kind: 'nested' },
  'territories.controller_id': { target: 'factions', kind: 'ref' },
  // Host-owned, not references:
  'gateways.dungeon_id': { literal: true, note: 'a dungeon NAME stem; the gateway record is <stem>_entrance' },
  'npc_offerings.service_id': { literal: true, note: 'a service class name (PremiumShopService), not a record id' },
  'roads.deck_visual_id': { literal: true, note: 'a texture/visual stem resolved by the renderer' },
  'worlds.terrain_backend_id': { literal: true, note: 'a terrain backend key (sundered), not a content record' },
  'containers.instance_id': { literal: true, note: 'always empty; a reserved slot' },
  'territories.active_war_id': { literal: true, note: 'empty until a war is declared' },
  'territories.boss_ids': { literal: true, note: 'empty; bosses are named on the horde, not the territory' },
  'balance.rolls.roll_id': { literal: true, note: 'a pull label (tide/depths), not a record id' },
  'balance.skus.sku_id': { literal: true, note: 'a store SKU (sigil_100), not a content record' },
  'achievements.target_type': { literal: true, note: 'not a reference: enum/display text, judged by hand' },
  'dialogues.nodes.choices': { literal: true, note: 'not a reference: enum/display text, judged by hand' },
  'hordes.instance_scope': { literal: true, note: 'not a reference: enum/display text, judged by hand' },
  'quests.objectives.target': { literal: true, note: 'not a reference: enum/display text, judged by hand' },

  // Residue the rule could not name a target for. Each is a real reference the
  // human resolves; a `literal` row above is the opposite decision.
  'achievements.title_reward': { target: 'titles', kind: 'ref' },
  'armors.required_class': { target: 'classes', kind: 'ref' },
  'balance.items_by_role': { target: 'weapons', kind: 'nested' },
  'classes.skill_tree_unlocks': { target: 'skills', kind: 'nested' },
  'classes.starting_skills': { target: 'skills', kind: 'nested' },
  'events.rewards.id': { target: 'items', kind: 'nested' },
  'furnishings.dismantle_returns.id': { target: 'resources', kind: 'nested' },
  'gates.key_mounts': { target: 'mounts', kind: 'nested' },
  'mounts.source_ref': { target: 'loot_tables', kind: 'ref' },
  'npc.includes.ref_id': { target: 'npc_offerings', kind: 'nested' },
  'quests.rewards.id': { target: ['accessories', 'consumables', 'resources'], kind: 'nested' },
  'quests.zone_restriction': { target: 'zones', kind: 'ref' },
  'skills.required_class': { target: 'classes', kind: 'ref' },
  'species.home_faction': { target: 'factions', kind: 'ref' },
  'species.home_zone': { target: 'zones', kind: 'ref' },
  'territories.claimants.id': { target: 'factions', kind: 'nested' },
  // Route labels, not record ids: the host contract validates unlock_source for
  // methods 0/1 only, and nothing reads the field at runtime. The 23 titles whose
  // source IS an id resolve through the `achievements`/`mysteries` union.
  'titles.unlock_source': { target: ['achievements', 'mysteries'], kind: 'ref' },
  'vehicles.route_gateways': { target: 'gateways', kind: 'nested' },
  'weapons.required_class': { target: 'classes', kind: 'ref' },
  'weather_events.stir_horde_config': { target: 'hordes', kind: 'ref' },
  'zones.npcs': { target: ['models', 'npc'], kind: 'nested' },
};

// Edges the rule guessed at one family, but which are really a union.
const RETARGET = {
  'loot_tables.entries.item_id': ITEM_FAMILIES,
  'npc_offerings.catalog_items.item_id': ITEM_FAMILIES,
  // Recipe slots hold any item id, so the inferred single family (`items`) would
  // refuse every weapon/armor/resource id a recipe actually names.
  'recipes.byproducts.item_id': ITEM_FAMILIES,
  'recipes.inputs.item_id': ITEM_FAMILIES,
  'recipes.output.item_id': ITEM_FAMILIES,
};

// The acknowledged breaks. A baseline names the code, the record, a non-empty
// reason, and an expiry - there is no `--ignore` (SPEC section 9).
const BASELINES = [
  {
    code: 'dangling-ref',
    record: 'loot_tables/*.tres',
    field: 'currency_drops.currency_id',
    reason: 'RULED: the loader accepts both spellings by design (loot_table.gd normalizes currency_gold->gold for the result key), so bare "gold" is a runtime alias, not a typo. The edge targets `currencies` so real ids resolve; the alias is baselined until the data is normalized to the record id.',
    expires: '2027-01-31',
  },
  {
    code: 'dangling-ref',
    record: 'loot_tables/loot_skill_books.tres',
    field: 'entries.item_id',
    reason: 'virtual book ids (book_<skill>_<tier>) expand at runtime; a file resolver cannot see them (SPEC section 5)',
    expires: '2027-01-31',
  },
  {
    code: 'dangling-ref',
    record: 'titles/title_deepseabaron.tres',
    field: 'unlock_source',
    reason: 'RULED: unlock_method 6 (PURCHASE) is granted outside the data, so unlock_source carries a ROUTE LABEL ("sigil_sink"), not a record id. The host contract in game/tests/test_data_naming_lint.gd validates sources for methods 0 and 1 only, so method 6 is deliberately unchecked. The purchase route exists in code: game/core/services/sigil_sink_service.gd lists sink_id "title_deepseabaron" (SinkKind.TITLE, 500 sigils) and grants it via _title_data_id(). unlock_source itself is documentation-only - game/core/schemas/title_data.gd declares the field and no runtime code reads it. Baselines record the divergence from tresridge\'s stricter "every unlock_source is an id" reading; the edge still resolves the other 23 titles.',
    expires: '2027-06-30',
  },
  {
    code: 'dangling-ref',
    record: 'titles/title_pillarsworn.tres',
    field: 'unlock_source',
    reason: 'RULED: unlock_method 6 (PURCHASE); same route-label case as title_deepseabaron. game/core/services/sigil_sink_service.gd lists sink_id "title_pillarsworn" (SinkKind.TITLE, 200 sigils), so the grant path exists in code rather than as a data record. unlock_source is documentation-only (declared in game/core/schemas/title_data.gd, never read at runtime), and the host contract checks sources for methods 0/1 only.',
    expires: '2027-06-30',
  },
  {
    code: 'dangling-ref',
    record: 'titles/title_guild_founder.tres',
    field: 'unlock_source',
    reason: 'RULED: unlock_method 1 (QUEST) with source "found_guild", a SENTINEL for a guild-foundation event rather than a quest record; no quest carries that id. game/tests/test_data_naming_lint.gd accepts a "found_" prefix for method 1 explicitly (tsource.begins_with("found_")), so the token is sanctioned by the host contract, not a typo. unlock_source is documentation-only, never read at runtime.',
    expires: '2027-06-30',
  },
];

const raw = execFileSync(process.execPath, [CLI, 'graph', DATA, '--json'], { encoding: 'utf8' });
const { declaration } = JSON.parse(raw);

// Apply the retargets.
for (const e of declaration.edges) {
  const key = `${e.family}.${e.field}`;
  if (RETARGET[key]) e.target = RETARGET[key];
}

// Apply the residue curation: promote to a real edge, or drop to literal.
for (const [key, rule] of Object.entries(CURATED)) {
  const i = key.indexOf('.');
  const family = key.slice(0, i);
  const field = key.slice(i + 1);
  const existing = declaration.edges.find((e) => e.family === family && e.field === field);
  if (rule.literal) {
    if (existing) {
      existing.kind = 'literal';
      delete existing.target;
      existing.note = rule.note;
    } else {
      declaration.edges.push({ family, field, kind: 'literal', note: rule.note });
    }
    continue;
  }
  if (existing) {
    existing.target = rule.target;
    existing.kind = rule.kind;
  } else {
    declaration.edges.push({ family, field, target: rule.target, kind: rule.kind, required: true });
  }
}

declaration.baselines = BASELINES;
declaration.edges.sort((a, b) => `${a.family}.${a.field}`.localeCompare(`${b.family}.${b.field}`));

const json = JSON.stringify(declaration, null, 2) + '\n';
if (process.argv.includes('--write')) {
  writeFileSync(OUT, json);
  console.error(`wrote ${OUT}: ${declaration.families.length} families, ${declaration.edges.length} edges`);
} else {
  process.stdout.write(json);
}
