// Prototype: derive the .tres relation graph from schemas + data.
// Goal: prove relations can be EXTRACTED, not hand-maintained.
// Not shipped; a probe for the roadmap in labs/prd-data-graph.md.
import { readFileSync, readdirSync, statSync } from 'fs';
import { resolve, join, basename } from 'path';

const ROOT = resolve(process.cwd(), 'game');
const DATA = join(ROOT, 'data');
const SCHEMAS = join(ROOT, 'core/schemas');

// ---- 1. schema index: class_name -> exported fields -----------------------
const schemas = new Map(); // class_name -> { file, exports: [{name, type}] }
for (const f of readdirSync(SCHEMAS)) {
  if (!f.endsWith('.gd')) continue;
  const txt = readFileSync(join(SCHEMAS, f), 'utf8');
  const cn = txt.match(/^class_name\s+(\w+)/m)?.[1];
  if (!cn) continue;
  const exports = [];
  for (const m of txt.matchAll(/@export(?:_[a-z_]+)?\s+var\s+(\w+)\s*:\s*([\w\[\]]+)/g)) {
    exports.push({ name: m[1], type: m[2] });
  }
  schemas.set(cn, { file: f, exports });
}

// ---- 2. data index: walk dirs, read id + script_class + fields -----------
const walk = (dir) => {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(full));
    else if (e.name.endsWith('.tres')) out.push(full);
  }
  return out;
};

const records = []; // { file, dir, id, scriptClass, fields: Map }
const idsByDir = new Map(); // dir -> Set(id)
for (const file of walk(DATA)) {
  const txt = readFileSync(file, 'utf8');
  const rel = file.slice(DATA.length + 1);
  const dir = rel.split('/')[0];
  const scriptClass = txt.match(/script_class="(\w+)"/)?.[1] || '';
  const id = txt.match(/^id\s*=\s*"([^"]*)"/m)?.[1] || basename(file, '.tres');
  const fields = new Map();
  for (const m of txt.matchAll(/^\s*"?([a-z_0-9]+)"?\s*[:=]\s*(.+)$/gm)) {
    if (m[1] === 'id' || m[1] === 'script') continue;
    fields.set(m[1], m[2].trim());
  }
  records.push({ file: rel, dir: rel.split('/')[0], id, scriptClass, fields });
  if (!idsByDir.has(dir)) idsByDir.set(dir, new Set());
  idsByDir.get(dir).add(id);
}
// items live in several dirs; build a union for *_id refs
const ITEM_DIRS = ['weapons', 'armors', 'accessories', 'consumables', 'resources', 'items'];
const allIds = new Set(records.map((r) => r.id));

// ---- 3. relation detection by convention --------------------------------
// A relation is a field whose name ends in _id (scalar) or _ids (array), or a
// dict key ending in _id inside an array value.
const SUFFIX_DIR = {
  npc: 'npc', zone: 'zones', world: 'worlds', faction: 'factions',
  currency: 'currencies', quest: 'quests', loot_table: 'loot_tables',
  skill: 'skills', model: 'models', hitbox_profile: 'hitbox_profiles',
  movement_profile: 'movement_profiles', species: 'species', territory: 'territories',
  gateway: 'gateways', title: 'titles', mount: 'mounts', vehicle: 'vehicles',
  enemy: 'enemies', house: 'houses', landmark: 'landmarks', sign: 'signs',
  act: 'acts', mystery: 'mysteries', ocean: 'oceans', target: 'targets',
  spawn_table: 'spawn_tables', calibration: 'calibration',
};

const relations = []; // { from, fromDir, field, target, kind }
const dangling = [];
const unresolved = new Map(); // field -> count (convention gaps)

for (const r of records) {
  for (const [field, raw] of r.fields) {
    const ids = [];
    for (const m of raw.matchAll(/"([a-z0-9_]+)"/g)) ids.push(m[1]);
    if (!/_ids?$/.test(field)) continue;
    const base = field.replace(/_ids?$/, '');
    // Resolve by exact stem first, then by the LAST family token in a compound
    // name (giver_npc_id -> npc, source_zone_id -> zone). This measures how much
    // a smarter convention buys before explicit declaration is required.
    const tokens = base.split('_');
    const targetDir = SUFFIX_DIR[base]
      || [...tokens].reverse().map((t) => SUFFIX_DIR[t]).find(Boolean)
      || (base === 'item' ? 'items' : undefined);
    for (const t of ids) {
      if (!targetDir) { unresolved.set(field, (unresolved.get(field) || 0) + 1); continue; }
      const pool = targetDir === 'items' ? ITEM_DIRS : [targetDir];
      const ok = pool.some((d) => idsByDir.get(d)?.has(t));
      relations.push({ from: r.id, fromDir: r.dir, field, target: t, kind: 'id' });
      if (!ok) dangling.push({ from: r.id, dir: r.dir, field, target: t, targetDir });
    }
  }
}

// ---- 4. report -----------------------------------------------------------
const out = [];
out.push(`schemas with class_name: ${schemas.size}`);
out.push(`records: ${records.length} across ${idsByDir.size} dirs`);
out.push(`relations extracted: ${relations.length}`);
out.push(`dangling: ${dangling.length}`);
out.push(`fields with no target convention: ${unresolved.size}`);
out.push('');
out.push('--- top dangling (target not found) ---');
const byField = new Map();
for (const d of dangling) byField.set(d.field, (byField.get(d.field) || 0) + 1);
for (const [f, n] of [...byField.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)) {
  out.push(`  ${String(n).padStart(4)}  ${f}`);
}
out.push('');
out.push('--- fields with no convention (needs declaration) ---');
for (const [f, n] of [...unresolved.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15)) {
  out.push(`  ${String(n).padStart(4)}  ${f}`);
}
out.push('');
out.push('--- sample dangling ---');
for (const d of dangling.slice(0, 10)) {
  out.push(`  ${d.fromDir}/${d.from}.${d.field} -> "${d.target}" (expect ${d.targetDir})`);
}
console.log(out.join('\n'));
