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
};

// Edges the rule guessed at one family, but which are really a union.
const RETARGET = {
  'loot_tables.entries.item_id': ITEM_FAMILIES,
  'npc_offerings.catalog_items.item_id': ITEM_FAMILIES,
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
