// Codex data layer: a generic viewer over the build-time godot_data.json
// (produced by scripts/sync_godot_data.ts from game/data/**/*.tres).
//
// This is deliberately NOT a curated read of the game. We are mid-refactor
// on the data/engine boundary, so any hand-picked field list here would
// drift the moment a schema moves. Instead this renders whatever the .tres
// files actually carry -- one entry per source file, every field, and the
// engine's own enum labels for enum-typed values (read from the schemas at
// sync time, so the web can never disagree with the engine about a rung).
//
// No network, no runtime fetch: the JSON is bundled.

import godotData from '../data/godot_data.json';

type Raw = Record<string, any>;
const DATA = godotData as unknown as Record<string, any>;

interface GodotVocab {
  enums: Record<string, string[]>;
  byClass: Record<string, Record<string, string>>;
  fieldEnums: Record<string, string>;
}
const EMPTY_VOCAB: GodotVocab = { enums: {}, byClass: {}, fieldEnums: {} };
const VOCAB: GodotVocab = (DATA.vocab as GodotVocab) || EMPTY_VOCAB;

// Keys the viewer supplies itself (title, prose, source footer) or that are
// parser scaffolding rather than authored data.
const META_KEYS = new Set([
  'id', 'display_name', 'name', 'description', 'script', '_sourceFile', '_scriptClass',
]);

// ---- value shaping ----------------------------------------------------

const titleCase = (s: unknown): string =>
  String(s ?? '')
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();

// Category keys whose display label is a fixed acronym (universal terms, not
// game curation -- NPC stays NPC in any viewer).
const LABEL_OVERRIDES: Record<string, string> = { npcs: 'NPCs' };
const labelFor = (key: string): string => LABEL_OVERRIDES[key] ?? titleCase(key);

// SCREAMING_SNAKE enum labels read as prose, but short acronyms (GM, DD,
// DPS, PVP) stay uppercase so the canonical term is preserved.
const humanizeEnumLabel = (label: string): string =>
  label
    .split('_')
    .map((w) => (w.length <= 3 ? w : w.charAt(0) + w.slice(1).toLowerCase()))
    .join(' ');

const asText = (v: unknown): string => {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') return v.trim();
  return String(v);
};

// A multi-line `[...]`/`{...}` reaches us as a string (often Godot-typed,
// e.g. "Array[int]([0, 1])") because the .tres parser only yields a real
// structure when the value fits on one line. Recover the shape when we can.
function coerceStructure(v: unknown): any[] | Record<string, any> | null {
  if (Array.isArray(v)) return v;
  if (v && typeof v === 'object') return v as Record<string, any>;
  if (typeof v !== 'string') return null;
  const s = v.trim();
  const typed = s.match(/^Array\[[^\]]*\]\((\[[\s\S]*\])\)$/);
  const body = typed ? typed[1] : s;
  if (!body.startsWith('[') && !body.startsWith('{')) return null;
  try {
    return JSON.parse(
      body
        .replace(/([{,]\s*)([A-Za-z_]\w*|\d+)\s*:/g, '$1"$2":')
        .replace(/,\s*([}\]])/g, '$1'),
    );
  } catch {
    return null;
  }
}

const isVector3 = (o: Raw) => 'x' in o && 'y' in o && 'z' in o && !('r' in o);
const isColor = (o: Raw) => 'r' in o && 'g' in o && 'b' in o;

const toHex = (o: Raw): string => {
  const c = (n: unknown) => {
    const v = Math.round(Number(n) * 255);
    return Math.max(0, Math.min(255, Number.isFinite(v) ? v : 0))
      .toString(16)
      .padStart(2, '0');
  };
  return `#${c(o.r)}${c(o.g)}${c(o.b)}`;
};

export type FieldKind = 'scalar' | 'list' | 'map' | 'color';

export interface CodexField {
  key: string;
  label: string;
  value: string;
  kind: FieldKind;
  /** For kind==='list': one row per element. */
  items?: string[];
  /** For kind==='map': key/value pairs. */
  pairs?: Array<{ key: string; value: string }>;
  /** For kind==='color': the resolved hex. */
  color?: string;
}

// Resolve an integer against the engine's enum for this (scriptClass, field).
// Falls back to the class-agnostic map only for unambiguous field names.
function enumFor(scriptClass: string, field: string): string[] | null {
  const cls = VOCAB.byClass?.[scriptClass];
  const name = (cls && cls[field]) || VOCAB.fieldEnums?.[field];
  if (!name) return null;
  return VOCAB.enums?.[name] || null;
}

function formatValue(scriptClass: string, field: string, v: unknown): CodexField | null {
  const label = titleCase(field);

  if (v === null || v === undefined || v === '') return null;

  if (typeof v === 'boolean') {
    return { key: field, label, value: v ? 'Yes' : 'No', kind: 'scalar' };
  }

  if (typeof v === 'number') {
    const en = enumFor(scriptClass, field);
    if (en && Number.isInteger(v) && v >= 0 && v < en.length) {
      return { key: field, label, value: humanizeEnumLabel(en[v]), kind: 'scalar' };
    }
    return { key: field, label, value: String(v), kind: 'scalar' };
  }

  if (typeof v === 'string') {
    // A multi-line array/dict arrives as a string; try to recover it before
    // falling back to a plain scalar.
    const struct = coerceStructure(v);
    if (struct === null) {
      return { key: field, label, value: v, kind: 'scalar' };
    }
    return structuredField(field, label, struct);
  }

  const struct = coerceStructure(v);
  if (struct === null) {
    return { key: field, label, value: asText(v), kind: 'scalar' };
  }
  return structuredField(field, label, struct);
}

function structuredField(
  field: string,
  label: string,
  struct: any[] | Record<string, any>,
): CodexField | null {
  if (Array.isArray(struct)) {
    if (struct.length === 0) return null;
    const items = struct.map((el) =>
      el && typeof el === 'object' ? JSON.stringify(el) : asText(el),
    );
    return { key: field, label, value: `${items.length}`, kind: 'list', items };
  }

  const obj = struct as Raw;
  if (isColor(obj)) {
    const hex = toHex(obj);
    return { key: field, label, value: hex, kind: 'color', color: hex };
  }
  if (isVector3(obj)) {
    return { key: field, label, value: `(${obj.x}, ${obj.y}, ${obj.z})`, kind: 'scalar' };
  }

  const pairs = Object.entries(obj).map(([k, val]) => ({
    key: k,
    value: val && typeof val === 'object' ? JSON.stringify(val) : asText(val),
  }));
  if (pairs.length === 0) return null;
  return { key: field, label, value: `${pairs.length}`, kind: 'map', pairs };
}

// ---- entries ----------------------------------------------------------

export interface CodexEntry {
  id: string;
  name: string;
  description: string;
  /** The .tres this entry was read from (the viewer's anchor). */
  source: string;
  scriptClass: string;
  fields: CodexField[];
  /** Lower-cased search haystack. */
  search: string;
}

export interface CodexCategory {
  key: string;
  label: string;
  blurb: string;
  entries: CodexEntry[];
}

function buildEntry(id: string, v: Raw): CodexEntry {
  const scriptClass = asText(v._scriptClass);
  const source = asText(v._sourceFile);

  const fields: CodexField[] = [];
  for (const key of Object.keys(v)) {
    if (META_KEYS.has(key)) continue;
    const f = formatValue(scriptClass, key, v[key]);
    if (f) fields.push(f);
  }
  // Scalars read first; collections collapse below them. Authored order is
  // preserved within each band.
  const ordered = [
    ...fields.filter((f) => f.kind !== 'list' && f.kind !== 'map'),
    ...fields.filter((f) => f.kind === 'list' || f.kind === 'map'),
  ];

  const name = asText(v.display_name) || asText(v.name) || titleCase(id);
  const description = asText(v.description);

  return {
    id,
    name,
    description,
    source,
    scriptClass,
    fields: ordered,
    search: [id, name, description, scriptClass, ...ordered.map((f) => f.value)]
      .join(' ')
      .toLowerCase(),
  };
}

function buildCategory(key: string, raw: Record<string, any>): CodexCategory {
  // One entry per source file: the sync injects bare base-archetype aliases
  // (warrior -> human_warrior) that are the same .tres, not a second one.
  const bySource = new Map<string, CodexEntry>();
  for (const [id, v] of Object.entries(raw)) {
    if (!v || typeof v !== 'object') continue;
    // Namespace the id by category: ids are unique within a directory but not
    // across the tree (a weapon and an achievement can share a slug), and the
    // Codex renders every category in one list.
    const entry = buildEntry(`${key}:${id}`, v as Raw);
    const anchor = entry.source || id;
    if (!bySource.has(anchor)) bySource.set(anchor, entry);
  }
  const entries = [...bySource.values()].sort((a, b) => a.name.localeCompare(b.name));

  const scriptClasses = [...new Set(entries.map((e) => e.scriptClass).filter(Boolean))];
  const blurb = entries.length
    ? `${entries.length} file${entries.length === 1 ? '' : 's'}${
        scriptClasses.length ? ` · ${scriptClasses.join(', ')}` : ''
      }`
    : 'No entries.';

  return { key, label: labelFor(key), blurb, entries };
}

// Categories come straight off the payload -- add a .tres directory and it
// appears here with no code change. Meta keys are the only exclusion.
const META_CATEGORIES = new Set(['lastSyncedAt', 'counts', 'vocab']);

export function buildCodex(): CodexCategory[] {
  const categories: CodexCategory[] = [];
  for (const [key, value] of Object.entries(DATA)) {
    if (META_CATEGORIES.has(key)) continue;
    if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
    const cat = buildCategory(key, value as Record<string, any>);
    if (cat.entries.length > 0) categories.push(cat);
  }
  categories.sort((a, b) => a.label.localeCompare(b.label));
  return categories;
}

export const CODEX_TOTAL = (() => {
  const cats = buildCodex();
  return cats.reduce((n, c) => n + c.entries.length, 0);
})();
