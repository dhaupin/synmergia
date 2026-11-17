import fs from 'fs';
import path from 'path';

/**
 * The canonical enum vocabulary, read off `game/core/schemas/*.gd`.
 *
 * The web codex used to hand-copy each GDScript enum into a TypeScript
 * array, which drifted the moment a schema changed (e.g. ResourceType's
 * ENERGY landed on the wrong rung). Deriving the labels here means the
 * web reads the same rung the engine does, and cannot disagree with it.
 *
 *   enums      EnumName -> [LABEL, ...] (index = authored int)
 *   byClass    ScriptClass -> { field: EnumName }  (authoritative)
 *   fieldEnums field -> EnumName, only for fields whose name maps to one
 *              enum across every schema (ambiguous names are omitted)
 */
export interface GodotVocab {
  enums: Record<string, string[]>;
  byClass: Record<string, Record<string, string>>;
  fieldEnums: Record<string, string>;
}

export interface GodotDataPayload {
  lastSyncedAt: string;
  counts: Record<string, number>;
  vocab: GodotVocab;
  classes: Record<string, any>;
  weapons: Record<string, any>;
  armors: Record<string, any>;
  consumables: Record<string, any>;
  enemies: Record<string, any>;
  models: Record<string, any>;
  zones: Record<string, any>;
  skills: Record<string, any>;
  quests: Record<string, any>;
  buffs: Record<string, any>;
  factions: Record<string, any>;
  achievements: Record<string, any>;
  titles: Record<string, any>;
  species: Record<string, any>;
  dialogues: Record<string, any>;
  currencies: Record<string, any>;
  mounts: Record<string, any>;
  vehicles: Record<string, any>;
  resources: Record<string, any>;
  items: Record<string, any>;
  accessories: Record<string, any>;
  recipes: Record<string, any>;
  status_effects: Record<string, any>;
  npcs: Record<string, any>;
  world_bosses: Record<string, any>;
  signs: Record<string, any>;
  mysteries: Record<string, any>;
  acts: Record<string, any>;
  loot_tables: Record<string, any>;
  hordes: Record<string, any>;
  weather_events: Record<string, any>;
  gateways: Record<string, any>;
  oceans: Record<string, any>;
  biomes: Record<string, any>;
  furnishings: Record<string, any>;
  gliders: Record<string, any>;
  thermals: Record<string, any>;
}

// Helper to convert Godot values into JS primitives/objects
function parseGodotValue(rawVal: string): any {
  const trimmed = rawVal.trim();
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;

  // Numbers (int / float)
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) {
    return Number(trimmed);
  }

  // Quoted string
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed.slice(1, -1);
    }
  }

  // Vector3(x, y, z)
  const v3Match = trimmed.match(/^Vector3\s*\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)$/);
  if (v3Match) {
    return { x: parseFloat(v3Match[1]), y: parseFloat(v3Match[2]), z: parseFloat(v3Match[3]) };
  }

  // Color(r, g, b, a)
  const colorMatch = trimmed.match(/^Color\s*\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)$/);
  if (colorMatch) {
    return { r: parseFloat(colorMatch[1]), g: parseFloat(colorMatch[2]), b: parseFloat(colorMatch[3]), a: parseFloat(colorMatch[4]) };
  }

  // ExtResource("id")
  const extMatch = trimmed.match(/^ExtResource\s*\(\s*["']?([^"')]+)["']?\s*\)$/);
  if (extMatch) {
    return { _extResource: extMatch[1] };
  }

  // Try JSON parsing for simple arrays or objects if valid
  if ((trimmed.startsWith('[') && trimmed.endsWith(']')) || (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
    try {
      // Replace Vector3 inside array/obj before JSON.parse
      const sanitized = trimmed
        .replace(/Vector3\(([^)]+)\)/g, '{"v3":[$1]}')
        .replace(/Color\(([^)]+)\)/g, '{"color":[$1]}')
        .replace(/ExtResource\([^)]+\)/g, 'null');
      return JSON.parse(sanitized);
    } catch {
      // Fallback manual extract
    }
  }

  return trimmed;
}

export function parseTresFile(content: string, filePath: string): { scriptClass?: string; data: Record<string, any> } {
  const lines = content.split(/\r?\n/);
  let scriptClass: string | undefined;

  // Extract script_class from header if present
  const headerMatch = lines[0]?.match(/script_class="([^"]+)"/);
  if (headerMatch) {
    scriptClass = headerMatch[1];
  }

  // Look for [resource] section
  const resourceIdx = lines.findIndex((l) => l.trim() === '[resource]');
  if (resourceIdx === -1) {
    return { scriptClass, data: {} };
  }

  const resourceLines = lines.slice(resourceIdx + 1);
  const data: Record<string, any> = {};
  let currentKey = '';
  let multilineBuffer = '';
  let insideMultiline = false;
  let multilineCloser = '';

  for (let i = 0; i < resourceLines.length; i++) {
    const rawLine = resourceLines[i];
    const trimmed = rawLine.trim();

    if (!insideMultiline) {
      if (!trimmed || trimmed.startsWith(';') || trimmed.startsWith('#')) {
        continue;
      }
      if (trimmed.startsWith('[')) {
        // Next section begins
        break;
      }

      const eqIdx = trimmed.indexOf('=');
      if (eqIdx !== -1) {
        const key = trimmed.slice(0, eqIdx).trim();
        const valuePart = trimmed.slice(eqIdx + 1).trim();

        if (valuePart.startsWith('{') && !valuePart.endsWith('}')) {
          insideMultiline = true;
          multilineCloser = '}';
          currentKey = key;
          multilineBuffer = valuePart;
        } else if (valuePart.startsWith('[') && !valuePart.endsWith(']')) {
          insideMultiline = true;
          multilineCloser = ']';
          currentKey = key;
          multilineBuffer = valuePart;
        } else {
          data[key] = parseGodotValue(valuePart);
        }
      }
    } else {
      multilineBuffer += '\n' + trimmed;
      if (trimmed.endsWith(multilineCloser)) {
        insideMultiline = false;
        data[currentKey] = parseGodotValue(multilineBuffer);
        currentKey = '';
        multilineBuffer = '';
      }
    }
  }

  // If id is missing, infer from filename
  if (!data.id) {
    const baseName = path.basename(filePath, '.tres');
    data.id = baseName;
  }

  return { scriptClass, data };
}

// Strip a trailing `#` comment, ignoring any `#` inside a quoted string.
function stripLineComment(line: string): string {
  let out = '';
  let quote: string | null = null;
  for (const ch of line) {
    if (quote) {
      out += ch;
      if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      out += ch;
    } else if (ch === '#') {
      break;
    } else {
      out += ch;
    }
  }
  return out;
}

// Read the `enum Name { ... }` blocks and `@export var field: EnumType`
// declarations out of one schema file. Comments are stripped first so a
// label list like `TANK = 1,  # Bulwark, Guardian` never leaks its prose
// into the labels (the bug that made the old hand-copy tempting).
function parseSchemaEnums(source: string): {
  enums: Record<string, string[]>;
  fieldEnums: Record<string, string>;
} {
  const lines = source.split('\n').map(stripLineComment);
  const enums: Record<string, string[]> = {};
  const fieldEnums: Record<string, string> = {};

  let i = 0;
  while (i < lines.length) {
    const m = lines[i].match(/\benum\s+([A-Za-z_]\w*)\s*\{/);
    if (m) {
      const name = m[1];
      let buf = lines[i].split('{').slice(1).join('{');
      let depth = (lines[i].match(/{/g) || []).length - (lines[i].match(/}/g) || []).length;
      i += 1;
      while (i < lines.length && depth > 0) {
        depth += (lines[i].match(/{/g) || []).length - (lines[i].match(/}/g) || []).length;
        buf += depth > 0 ? lines[i] : lines[i].split('}')[0];
        i += 1;
      }
      const labels: string[] = [];
      for (const part of buf.split(',')) {
        const label = part.split('=')[0].trim();
        if (/^[A-Za-z_]\w*$/.test(label)) labels.push(label);
      }
      enums[name] = labels;
      continue;
    }
    i += 1;
  }

  const joined = lines.join('\n');
  const varRe = /@export\s+var\s+([a-z_]\w*)\s*:\s*([A-Za-z_]\w*)/g;
  let vm: RegExpExecArray | null;
  while ((vm = varRe.exec(joined)) !== null) {
    if (enums[vm[2]]) fieldEnums[vm[1]] = vm[2];
  }
  return { enums, fieldEnums };
}

// Walk game/core/schemas/*.gd and assemble the one vocabulary.
export function buildVocab(): GodotVocab {
  const schemaDir = path.resolve(process.cwd(), 'game/core/schemas');
  const enums: Record<string, string[]> = {};
  const byClass: Record<string, Record<string, string>> = {};
  const owners: Record<string, Set<string>> = {};

  let files: string[] = [];
  try {
    files = fs.readdirSync(schemaDir).filter((f) => f.endsWith('.gd'));
  } catch {
    files = [];
  }

  for (const file of files) {
    const src = fs.readFileSync(path.join(schemaDir, file), 'utf-8');
    const parsed = parseSchemaEnums(src);
    const classMatch = src.match(/class_name\s+([A-Za-z_]\w*)/);
    if (classMatch && Object.keys(parsed.fieldEnums).length > 0) {
      byClass[classMatch[1]] = parsed.fieldEnums;
    }
    for (const [name, labels] of Object.entries(parsed.enums)) {
      if (!enums[name]) enums[name] = labels;
    }
    for (const [field, enumName] of Object.entries(parsed.fieldEnums)) {
      (owners[field] ||= new Set()).add(enumName);
    }
  }

  // A field name is safe to resolve globally only when every schema that
  // declares it agrees on the enum. `kind`/`category`/`source` do not, so
  // they resolve per-class instead (see byClass).
  const fieldEnums: Record<string, string> = {};
  for (const [field, names] of Object.entries(owners)) {
    if (names.size === 1) fieldEnums[field] = [...names][0];
  }

  return { enums, byClass, fieldEnums };
}

function scanDir(dir: string): string[] {
  let results: string[] = [];
  if (!fs.existsSync(dir)) return results;
  const list = fs.readdirSync(dir);
  for (const file of list) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(scanDir(fullPath));
    } else if (file.endsWith('.tres')) {
      results.push(fullPath);
    }
  }
  return results;
}

export function syncGodotData(): GodotDataPayload {
  const dataDir = path.resolve(process.cwd(), 'game/data');
  const targetJsonPath = path.resolve(process.cwd(), 'src/data/godot_data.json');

  const payload: GodotDataPayload = {
    lastSyncedAt: new Date().toISOString(),
    counts: {},
    vocab: { enums: {}, byClass: {}, fieldEnums: {} },
    classes: {},
    weapons: {},
    armors: {},
    consumables: {},
    enemies: {},
    models: {},
    zones: {},
    skills: {},
    quests: {},
    buffs: {},
    factions: {},
    achievements: {},
    titles: {},
    species: {},
    dialogues: {},
    currencies: {},
    mounts: {},
    vehicles: {},
    resources: {},
    items: {},
    accessories: {},
    recipes: {},
    status_effects: {},
    npcs: {},
    world_bosses: {},
    signs: {},
    mysteries: {},
    acts: {},
    loot_tables: {},
    hordes: {},
    weather_events: {},
    gateways: {},
    oceans: {},
    biomes: {},
    furnishings: {},
    gliders: {},
    thermals: {},
  };

  const categories: Array<keyof Omit<GodotDataPayload, 'lastSyncedAt' | 'counts'>> = [
    'classes',
    'weapons',
    'armors',
    'consumables',
    'enemies',
    'models',
    'zones',
    'skills',
    'quests',
    'buffs',
    'factions',
    'achievements',
    'titles',
    'species',
    'dialogues',
    'currencies',
    'mounts',
    'vehicles',
    'resources',
    'items',
    'accessories',
    'recipes',
    'status_effects',
    'npcs',
    'world_bosses',
    'signs',
    'mysteries',
    'acts',
    'loot_tables',
    'hordes',
    'weather_events',
    'gateways',
    'oceans',
    'biomes',
    'furnishings',
    'gliders',
    'thermals',
  ];

  for (const cat of categories) {
    // Some payload keys are the plural of the on-disk dir (npc -> npcs).
    const dirName = cat === 'npcs' ? 'npc' : cat;
    const catDir = path.join(dataDir, dirName);
    const files = scanDir(catDir);
    for (const file of files) {
      try {
        const content = fs.readFileSync(file, 'utf-8');
        const parsed = parseTresFile(content, file);
        const item = parsed.data;
        if (item.id) {
          payload[cat][item.id] = {
            ...item,
            _sourceFile: path.relative(process.cwd(), file),
            _scriptClass: parsed.scriptClass,
          };
        }
      } catch (err) {
        console.warn(`[sync:data] Failed to parse ${file}:`, err);
      }
    }
    if (cat === 'classes') {
      // Map base archetypes (e.g. human_warrior -> warrior) for UI compatibility
      for (const [classId, classData] of Object.entries(payload.classes)) {
        const baseArchetype = classId.replace(/^(human|synthetic|akkan)_/, '');
        if (baseArchetype && !payload.classes[baseArchetype]) {
          payload.classes[baseArchetype] = {
            ...classData,
            id: baseArchetype,
            name: baseArchetype.charAt(0).toUpperCase() + baseArchetype.slice(1),
          };
        }
      }
    }
    payload.counts[cat] = Object.keys(payload[cat]).length;
  }

  // The canonical enum vocabulary, read from the schemas the .tres name.
  payload.vocab = buildVocab();

  // Ensure target directory exists
  const targetDir = path.dirname(targetJsonPath);
  if (!fs.existsSync(targetDir)) {
    fs.mkdirSync(targetDir, { recursive: true });
  }

  fs.writeFileSync(targetJsonPath, JSON.stringify(payload, null, 2), 'utf-8');
  console.log(`[sync:data] Synced Godot data to ${targetJsonPath}`);
  console.log(
    `[sync:data] Extracted categories:`,
    Object.entries(payload.counts)
      .map(([k, v]) => `${k}: ${v}`)
      .join(', ')
  );

  return payload;
}

// Run directly when invoked as a script
if (process.argv[1]?.includes('sync_godot_data')) {
  syncGodotData();
}
