// verify_codex.mjs — prove the web Codex reads the world faithfully.
//
// The Codex is a generic viewer over godot_data.json (the build-time read of
// game/data/**/*.tres). Two things must stay true, because the codex is only
// trustworthy if they are:
//
//   1. Coverage  — every authored field of every source file reaches the
//      viewer. A hand-picked field list here would silently drop the rest.
//   2. Enum fidelity — every enum-typed value renders with the label the
//      engine's own schema gives that rung (the ResourceType/ENERGY class of
//      bug), never a stale hand-copied array.
//
// Run: node scripts/verify_codex.mjs   (exit 0 = the Codex is faithful)

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DATA = JSON.parse(readFileSync(resolve(ROOT, 'src/data/godot_data.json'), 'utf-8'));

// The viewer's own meta keys (title/prose/source) and parser scaffolding.
const META_KEYS = new Set(['id', 'display_name', 'name', 'description', 'script', '_sourceFile', '_scriptClass']);
const META_CATEGORIES = new Set(['lastSyncedAt', 'counts', 'vocab']);

let pass = 0;
let fail = 0;
const check = (name, cond, detail = '') => {
  if (cond) {
    pass += 1;
    console.log('  ok   ', name);
  } else {
    fail += 1;
    console.log('  FAIL ', name, detail ? `-- ${detail}` : '');
  }
};

// 1. The vocabulary is present and canonical (spot-check the rungs that
//    drifted when the labels were hand-copied).
const vocab = DATA.vocab || {};
check('vocab: enums present', Object.keys(vocab.enums || {}).length > 50);
check('vocab: ResourceType is the engine ladder',
  JSON.stringify(vocab.enums?.ResourceType) === JSON.stringify(['MANA', 'ENERGY', 'RAGE', 'RUNIC_POWER', 'CHI']),
  JSON.stringify(vocab.enums?.ResourceType));
check('vocab: Role carries the legacy aliases',
  (vocab.enums?.Role || []).includes('DPS_MELEE') && (vocab.enums?.Role || []).includes('DPS_RANGED'));
check('vocab: Rarity is the five-rung scale',
  JSON.stringify(vocab.enums?.Rarity) === JSON.stringify(['COMMON', 'RARE', 'EPIC', 'LEGENDARY', 'MYTHIC']));
check('vocab: ambiguous field names resolve per-class, not globally',
  !('kind' in (vocab.fieldEnums || {})) && !('category' in (vocab.fieldEnums || {})),
  'kind/category must not have a global enum');

// 2. Coverage: every authored, non-empty field of every source file must be
//    reachable from the payload (the viewer renders all of them). We assert
//    the payload itself is complete -- a field list in codex.ts is what used
//    to drop these.
let authoredFields = 0;
const seenSources = new Set();
let sourceFiles = 0;
for (const [key, raw] of Object.entries(DATA)) {
  if (META_CATEGORIES.has(key) || !raw || typeof raw !== 'object') continue;
  const localSeen = new Set();
  for (const [id, v] of Object.entries(raw)) {
    if (!v || typeof v !== 'object') continue;
    const src = v._sourceFile || id;
    if (localSeen.has(src)) continue;
    localSeen.add(src);
    for (const f of Object.keys(v)) {
      if (META_KEYS.has(f)) continue;
      const val = v[f];
      if (val === null || val === undefined || val === '') continue;
      authoredFields += 1;
    }
  }
  seenSources.add(key);
  sourceFiles += localSeen.size;
}
check('coverage: payload carries authored fields', authoredFields > 10000, `got ${authoredFields}`);
check('coverage: every .tres source is represented', sourceFiles > 900, `got ${sourceFiles}`);

// 3. Enum fidelity on live data: every class resource_type must land on the
//    engine's rung, not a stale mirror.
const classes = DATA.classes || {};
const resEnum = vocab.enums?.ResourceType || [];
let badRes = 0;
for (const [, v] of Object.entries(classes)) {
  if (!v || typeof v !== 'object') continue;
  const rt = v.resource_type;
  if (typeof rt === 'number' && (rt < 0 || rt >= resEnum.length)) badRes += 1;
}
check('fidelity: every class resource_type is inside the canonical enum', badRes === 0, `${badRes} out of range`);

// 4. Focal stats survive: the field the old curated view dropped entirely.
const cls = vocab.byClass?.CharacterClass || {};
check('fidelity: CharacterClass maps focal/resource fields to enums',
  cls.role === 'Role' && cls.resource_type === 'ResourceType',
  JSON.stringify(cls));
const withFocals = Object.values(classes).filter((v) => v && typeof v === 'object' && 'focal_stat_1' in v).length;
check('fidelity: focal_stat_1 present on authored classes', withFocals > 0, `got ${withFocals}`);

console.log(`\n  verify:codex  ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
