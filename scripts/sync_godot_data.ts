import fs from 'fs';
import path from 'path';

export interface GodotDataPayload {
  lastSyncedAt: string;
  counts: Record<string, number>;
  classes: Record<string, any>;
  weapons: Record<string, any>;
  armors: Record<string, any>;
  consumables: Record<string, any>;
  enemies: Record<string, any>;
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
    classes: {},
    weapons: {},
    armors: {},
    consumables: {},
    enemies: {},
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
