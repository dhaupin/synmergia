// Codex data layer: reads the build-time godot_data.json (produced by
// scripts/sync_godot_data.ts from game/data/**/*.tres on every build)
// and normalizes it for the browse UI. No network, no runtime fetch --
// the JSON is bundled, so the codex can never disagree with the .tres
// files it describes. Adding a category here is a view decision, not a
// data one: every field below already exists in the synced payload.

import godotData from '../data/godot_data.json';

type Raw = Record<string, any>;
const DATA = godotData as unknown as Record<string, Raw>;

// ---- enum label maps (mirror the GDScript enums, by index) ----

const RARITY = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic'];
const ITEM_CATEGORY = [
  'Weapon', 'Armor', 'Accessory', 'Consumable', 'Resource',
  'Gem', 'Event', 'Dwelling', 'Misc', 'Skill Book',
];
const WEAPON_TYPE = [
  'None', 'Sword', 'Axe', 'Mace', 'Dagger', 'Bow',
  'Crossbow', 'Staff', 'Wand', 'Spear', 'Shield',
];
const ARMOR_TYPE = ['None', 'Cloth', 'Leather', 'Mail', 'Plate'];
const ACCESSORY_TYPE = ['None', 'Ring', 'Necklace', 'Bracelet', 'Cloak', 'Belt', 'Breather'];
const EQUIP_SLOT = [
  'None', 'Head', 'Chest', 'Legs', 'Feet', 'Gloves', 'Shoulders',
  'Main Hand', 'Off Hand', 'Ring 1', 'Ring 2', 'Necklace', 'Cloak', 'Belt',
];
const ENEMY_TYPE = ['Normal', 'Elite', 'Champion', 'Boss', 'World Boss', 'Raid Boss'];
const SKILL_TYPE = [
  'Melee', 'Ranged', 'Instant', 'Ground Targeted', 'Targeted AoE',
  'Self', 'Channel', 'Projectile AoE', 'Revive',
];
const TARGET_TYPE = [
  'Single Enemy', 'Multiple Enemies', 'Self', 'Ally', 'Dead Ally', 'Ground', 'Targeted AoE',
];
const PVP_MODE = ['Safe', 'Species PvP', 'Faction PvP', 'Free PvP', 'Warzone'];
const ROLE = ['GM', 'Tank', 'Damage', 'Mage', 'Ranger', 'Bender', 'Healer', 'Melee', 'Ranged'];
const RESOURCE_TYPE = ['None', 'Mana', 'Rage', 'Energy', 'Focus'];
const ACCESSORY_TYPE_SHORT = ACCESSORY_TYPE;

const pick = (arr: string[], i: unknown): string =>
  typeof i === 'number' && i >= 0 && i < arr.length ? arr[i] : '';

export const rarityLabel = (i: unknown) => pick(RARITY, i);
export const itemCategoryLabel = (i: unknown) => pick(ITEM_CATEGORY, i);
export const weaponTypeLabel = (i: unknown) => pick(WEAPON_TYPE, i);
export const armorTypeLabel = (i: unknown) => pick(ARMOR_TYPE, i);
export const accessoryTypeLabel = (i: unknown) => pick(ACCESSORY_TYPE_SHORT, i);
export const equipSlotLabel = (i: unknown) => pick(EQUIP_SLOT, i);
export const enemyTypeLabel = (i: unknown) => pick(ENEMY_TYPE, i);
export const skillTypeLabel = (i: unknown) => pick(SKILL_TYPE, i);
export const targetTypeLabel = (i: unknown) => pick(TARGET_TYPE, i);
export const pvpModeLabel = (i: unknown) => pick(PVP_MODE, i);
export const roleLabel = (i: unknown) => pick(ROLE, i);
export const resourceTypeLabel = (i: unknown) => pick(RESOURCE_TYPE, i);

// ---- normalized entries ----

export interface CodexEntry {
  id: string;
  name: string;
  description: string;
  /** Short tag chips shown under the title (e.g. "Rare", "Boss", "Lv 25"). */
  tags: string[];
  /** Label/value rows rendered in the detail pane. */
  facts: Array<{ label: string; value: string }>;
  /** Grouping label for the list column (sub-header bucketing). */
  group?: string;
  /** Lower-cased search haystack. */
  search: string;
}

export interface CodexCategory {
  key: string;
  label: string;
  blurb: string;
  entries: CodexEntry[];
}

// The .tres parser only yields a real array/object when the value fits on
// one line; a multi-line `[...]`/`{...}` comes through as a string (often
// Godot-typed, e.g. "Array[int]([0, 1])"). These coercers keep the codex
// honest for both shapes.
const asArray = (v: unknown): any[] => {
  if (Array.isArray(v)) return v;
  if (typeof v === 'string') {
    const typed = v.match(/^Array\[[^\]]*\]\((\[[\s\S]*\])\)$/);
    const body = typed ? typed[1] : v;
    if (body.trim().startsWith('[')) {
      try {
        return JSON.parse(body.replace(/([{,]\s*)([A-Za-z_][\w]*)\s*:/g, '$1"$2":'));
      } catch {
        return [];
      }
    }
  }
  return [];
};

const asObject = (v: unknown): Record<string, any> => {
  if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, any>;
  if (typeof v === 'string' && v.trim().startsWith('{')) {
    try {
      return JSON.parse(v.replace(/([{,]\s*)([A-Za-z_][\w]*)\s*:/g, '$1"$2":').replace(/,\s*}/g, '}'));
    } catch {
      return {};
    }
  }
  return {};
};

const titleCase = (s: unknown): string =>
  String(s ?? '')
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();

const asText = (v: unknown): string => {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') return v.trim();
  return String(v);
};

// Strip the data-layer category prefixes so ids read as prose
// ("zone_nexus_central" -> "Nexus Central"). Applied to referenced ids
// in fact rows; the entry's own id keeps its prefix (it is an anchor).
const ID_PREFIXES = ['zone_', 'faction_', 'npc_', 'item_quest_', 'item_', 'res_', 'currency_', 'recipe_', 'loot_', 'mount_', 'veh_', 'acc_', 'arm_', 'wep_', 'buff_', 'quest_'];
const prettyId = (v: unknown): string => {
  let s = asText(v);
  if (!s) return '';
  for (const p of ID_PREFIXES) {
    if (s.startsWith(p)) {
      s = s.slice(p.length);
      break;
    }
  }
  return titleCase(s);
};

function makeEntry(
  id: string,
  name: string,
  description: string,
  tags: string[],
  facts: Array<{ label: string; value: string }>,
  group?: string,
): CodexEntry {
  const cleanTags = tags.filter(Boolean);
  const cleanFacts = facts.filter((f) => f.value !== '' && f.value !== undefined);
  return {
    id,
    name: name || titleCase(id),
    description,
    tags: cleanTags,
    facts: cleanFacts,
    group,
    search: [id, name, description, ...cleanTags, ...cleanFacts.map((f) => f.value)]
      .join(' ')
      .toLowerCase(),
  };
}

const rows = (cat: string): Raw => DATA[cat] || {};

function mapCategory(
  cat: string,
  fn: (id: string, v: Raw) => CodexEntry | null,
): CodexEntry[] {
  const out: CodexEntry[] = [];
  for (const [id, v] of Object.entries(rows(cat))) {
    const e = fn(id, v);
    if (e) out.push(e);
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  return out;
}

// The playable, prefixed classes: the sync adds bare base-archetype
// aliases (warrior, cleric, ...) pointing at the same .tres. The codex
// lists the authored, species-prefixed rows so a class appears once.
const isAuthoredClass = (id: string): boolean =>
  /^(human|akkan|synthetic)_/.test(id);

export function buildCodex(): CodexCategory[] {
  const categories: CodexCategory[] = [];

  // Classes
  categories.push({
    key: 'classes',
    label: 'Classes',
    blurb: 'Every playable class across the three species, plus the reserved GM seats.',
    entries: mapCategory('classes', (id, v) => {
      if (!isAuthoredClass(id)) return null;
      const role = roleLabel(v.role);
      const res = resourceTypeLabel(v.resource_type);
      const stats = asObject(v.base_stats);
      const species = id.split('_')[0];
      const facts = [
        { label: 'Species', value: titleCase(species) },
        { label: 'Role', value: role },
        { label: 'Resource', value: res },
        { label: 'Strength', value: asText(stats.strength) },
        { label: 'Agility', value: asText(stats.agility) },
        { label: 'Intelligence', value: asText(stats.intelligence) },
        { label: 'Vitality', value: asText(stats.vitality) },
        { label: 'Endurance', value: asText(stats.endurance) },
        { label: 'Wisdom', value: asText(stats.wisdom) },
        { label: 'Base resource', value: asText(v.base_resource) },
        { label: 'Base attack', value: asText(v.base_attack_power) },
      ];
      return makeEntry(id, v.display_name, v.description, [titleCase(species), role].filter(Boolean), facts, titleCase(species));
    }),
  });

  // Species
  categories.push({
    key: 'species',
    label: 'Species',
    blurb: 'The peoples of the planet, their homes, and how they see each other.',
    entries: mapCategory('species', (id, v) => {
      const mods = asObject(v.stat_modifiers);
      const modsText = Object.entries(mods)
        .filter(([, n]) => Number(n) !== 0)
        .map(([k, n]) => `${titleCase(k)} ${Number(n) > 0 ? '+' : ''}${n}`)
        .join(', ');
      const facts = [
        { label: 'Home zone', value: prettyId(v.home_zone) },
        { label: 'Home faction', value: prettyId(v.home_faction) },
        { label: 'Stat modifiers', value: modsText },
        { label: 'Health', value: v.health_modifier ? `x${v.health_modifier}` : '' },
        { label: 'Mana', value: v.mana_modifier ? `x${v.mana_modifier}` : '' },
        { label: 'Allied with', value: asArray(v.allied_species).map(titleCase).join(', ') },
        { label: 'Hostile to', value: asArray(v.hostile_species).map(titleCase).join(', ') },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Skills
  categories.push({
    key: 'skills',
    label: 'Skills',
    blurb: 'Every ability the server ships, with its real cost, cooldown, and effect.',
    entries: mapCategory('skills', (id, v) => {
      const effects = asArray(v.effects)
        .map((e: Raw) => {
          const t = titleCase(asText(e.type));
          return e.value !== undefined ? `${t} ${e.value}` : t;
        })
        .filter(Boolean)
        .join(', ');
      const tags = [
        skillTypeLabel(v.skill_type),
        v.required_level ? `Lv ${v.required_level}` : '',
        v.mana_cost ? `${v.mana_cost} mana` : '',
      ];
      const facts = [
        { label: 'Type', value: skillTypeLabel(v.skill_type) },
        { label: 'Target', value: targetTypeLabel(v.target_type) },
        { label: 'Required level', value: asText(v.required_level) },
        { label: 'Mana cost', value: asText(v.mana_cost) },
        { label: 'Stamina cost', value: asText(v.stamina_cost) },
        { label: 'Cooldown', value: v.cooldown ? `${v.cooldown}s` : '' },
        { label: 'Cast time', value: v.cast_time ? `${v.cast_time}s` : '' },
        { label: 'Range', value: v.range ? `${v.range} m` : '' },
        { label: 'AoE radius', value: v.aoe_radius ? `${v.aoe_radius} m` : '' },
        { label: 'Effects', value: effects },
      ];
      const group = v._sourceFile ? String(v._sourceFile).split('/').slice(-2, -1)[0] : undefined;
      return makeEntry(id, v.display_name, v.description, tags, facts, group ? titleCase(group) : undefined);
    }),
  });

  // Enemies
  categories.push({
    key: 'enemies',
    label: 'Enemies',
    blurb: 'Everything that fights back, from roadside bandits to world bosses.',
    entries: mapCategory('enemies', (id, v) => {
      const type = enemyTypeLabel(v.enemy_type);
      const facts = [
        { label: 'Type', value: type },
        { label: 'Level', value: asText(v.level) },
        { label: 'Health', value: asText(v.health) },
        { label: 'Mana', value: asText(v.mana) },
        { label: 'Strength', value: asText(v.strength) },
        { label: 'Agility', value: asText(v.agility) },
        { label: 'Intelligence', value: asText(v.intelligence) },
        { label: 'Vitality', value: asText(v.vitality) },
      ];
      const tags = [type, v.level ? `Lv ${v.level}` : ''];
      return makeEntry(id, v.display_name, v.description, tags, facts, type);
    }),
  });

  // Zones
  categories.push({
    key: 'zones',
    label: 'Zones',
    blurb: 'The named places of the world and the rules that hold inside them.',
    entries: mapCategory('zones', (id, v) => {
      const mode = pvpModeLabel(v.pvp_mode);
      const facts = [
        { label: 'PvP', value: mode },
        { label: 'Level requirement', value: asText(v.level_requirement) },
        { label: 'Max level', value: v.max_level === 999 ? 'Uncapped' : asText(v.max_level) },
        { label: 'Respawn timer', value: v.respawn_timer ? `${v.respawn_timer}s` : '' },
        { label: 'Radius', value: v.zone_radius ? `${v.zone_radius} m` : '' },
      ];
      return makeEntry(id, v.display_name, v.description, [mode], facts, mode);
    }),
  });

  // Weapons / Armor / Accessories / Items / Resources / Consumables
  const itemLike = (
    cat: string,
    label: string,
    blurb: string,
    kind: (v: Raw) => string,
  ) => {
    categories.push({
      key: cat,
      label,
      blurb,
      entries: mapCategory(cat, (id, v) => {
        const rarity = rarityLabel(v.rarity);
        const kindLabel = kind(v);
        const facts = [
          { label: 'Type', value: kindLabel },
          { label: 'Rarity', value: rarity },
          { label: 'Item level', value: asText(v.item_level) },
          { label: 'Required level', value: asText(v.required_level) },
          { label: 'Equip slot', value: equipSlotLabel(v.equip_slot) },
          { label: 'Stack size', value: asText(v.stack_size) },
          { label: 'Buy price', value: v.buy_price ? `${v.buy_price} g` : '' },
          { label: 'Sell price', value: v.sell_price ? `${v.sell_price} g` : '' },
        ];
        const tags = [rarity, kindLabel, v.required_level ? `Lv ${v.required_level}` : ''];
        return makeEntry(id, v.display_name, v.description, tags, facts, kindLabel);
      }),
    });
  };
  itemLike('weapons', 'Weapons', 'Blades, hafts, bows, and staves — and what they cost.', (v) => weaponTypeLabel(v.weapon_type));
  itemLike('armors', 'Armor', 'Cloth to plate, and the belts and cloaks that hang off it.', (v) => armorTypeLabel(v.armor_type));
  itemLike('accessories', 'Accessories', 'Rings, amulets, cloaks, belts, and the deep-water breathers.', (v) => accessoryTypeLabel(v.accessory_type));
  itemLike('items', 'Items', 'Coins, seals, quest tokens, and everything else.', (v) => itemCategoryLabel(v.item_category));
  itemLike('resources', 'Resources', 'Ores, fibers, petals — the raw stock the world gathers.', (v) => itemCategoryLabel(v.item_category));
  itemLike('consumables', 'Consumables', 'Potions, elixirs, and the things you drink once.', (v) => itemCategoryLabel(v.item_category));
  itemLike('dwellings', 'Dwellings', 'Placeable structures: fireplaces, anvils, and the like.', (v) => itemCategoryLabel(v.item_category));

  // Recipes
  categories.push({
    key: 'recipes',
    label: 'Recipes',
    blurb: 'What the crafting stations make, from what, and how likely it is to hold.',
    entries: mapCategory('recipes', (id, v) => {
      const inputs = asArray(v.inputs)
        .map((i: Raw) => `${i.qty}x ${prettyId(i.item_id)}`)
        .join(', ');
      const output = v.output ? `${v.output.qty || 1}x ${prettyId(v.output.item_id)}` : '';
      const facts = [
        { label: 'Produces', value: output },
        { label: 'Inputs', value: inputs },
        { label: 'Required level', value: asText(v.required_level) },
        { label: 'Failure rate', value: v.failure_rate ? `${Math.round(v.failure_rate * 100)}%` : '0%' },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Mounts
  categories.push({
    key: 'mounts',
    label: 'Mounts',
    blurb: 'The creatures and craft you ride, and how fast they carry you.',
    entries: mapCategory('mounts', (id, v) => {
      const facts = [
        { label: 'Speed', value: v.speed_multiplier ? `x${v.speed_multiplier}` : '' },
        { label: 'Required level', value: asText(v.required_level) },
        { label: 'Cost', value: v.cost ? `${v.cost} ${prettyId(v.currency_id)}` : '' },
      ];
      return makeEntry(id, v.display_name, v.description, [v.required_level ? `Lv ${v.required_level}` : ''], facts);
    }),
  });

  // Factions
  categories.push({
    key: 'factions',
    label: 'Factions',
    blurb: 'The powers of the world and how they stand with one another.',
    entries: mapCategory('factions', (id, v) => {
      const relations = asObject(v.relations);
      const rel = Object.entries(relations)
        .map(([k, n]) => `${titleCase(k)} ${n}`)
        .join(', ');
      const facts = [
        { label: 'Species', value: titleCase(asText(v.species_id)) },
        { label: 'Joinable', value: v.is_joinable ? 'Yes' : 'No' },
        { label: 'Standing', value: rel },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Status effects
  categories.push({
    key: 'status_effects',
    label: 'Effects',
    blurb: 'Buffs and debuffs — what they do and how long they last.',
    entries: mapCategory('status_effects', (id, v) => {
      const facts = [
        { label: 'Effect', value: titleCase(asText(v.effect_type)) },
        { label: 'Duration', value: v.duration ? `${v.duration}s` : '' },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Titles
  categories.push({
    key: 'titles',
    label: 'Titles',
    blurb: 'The names you earn and wear before your own.',
    entries: mapCategory('titles', (id, v) => {
      const rarity = rarityLabel(v.rarity);
      const facts = [
        { label: 'Rarity', value: rarity },
        { label: 'Prefix', value: asText(v.prefix_form) },
        { label: 'Suffix', value: asText(v.suffix_form) },
      ];
      return makeEntry(id, v.display_name, v.description, [rarity], facts);
    }),
  });

  // Achievements
  categories.push({
    key: 'achievements',
    label: 'Achievements',
    blurb: 'The deeds the game remembers, and what they pay.',
    entries: mapCategory('achievements', (id, v) => {
      const facts = [
        { label: 'Goal', value: v.target ? `${v.target} ${asText(v.target_type)}` : '' },
        { label: 'Gold reward', value: v.gold_reward ? `${v.gold_reward} g` : '' },
        { label: 'XP reward', value: asText(v.xp_reward) },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // World bosses
  categories.push({
    key: 'world_bosses',
    label: 'World Bosses',
    blurb: 'The scheduled threats that gather the whole shard.',
    entries: mapCategory('world_bosses', (id, v) => {
      const facts = [
        { label: 'Zone', value: prettyId(v.zone_id) },
        { label: 'Every', value: v.interval_seconds ? `${Math.round(v.interval_seconds / 60)} min` : '' },
        { label: 'Window', value: v.window_seconds ? `${Math.round(v.window_seconds / 60)} min` : '' },
        { label: 'Announced', value: v.announce ? 'Yes' : 'No' },
      ];
      return makeEntry(id, v.display_name, '', ['World Boss'], facts);
    }),
  });

  // Signs (the sky clock)
  categories.push({
    key: 'signs',
    label: 'Sky Signs',
    blurb: 'The communal sky clock — the glyphs the whole planet reads together.',
    entries: mapCategory('signs', (id, v) => {
      const facts = [
        { label: 'Glyph', value: asText(v.glyph) },
        { label: 'Hint', value: asText(v.observation_hint) },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Mysteries
  categories.push({
    key: 'mysteries',
    label: 'Mysteries',
    blurb: 'Chapter-gated riddles. The answer is never stored — it is derived.',
    entries: mapCategory('mysteries', (id, v) => {
      const facts = [
        { label: 'Gate act', value: prettyId(v.gate_act_id) },
        { label: 'Chapter', value: asText(v.gate_chapter_index) },
        { label: 'Hint', value: asText(v.hint) },
      ];
      return makeEntry(id, v.display_name, v.riddle || v.description, [], facts);
    }),
  });

  // Weather events
  categories.push({
    key: 'weather_events',
    label: 'Weather',
    blurb: 'The sky events that roll across the world on their own schedule.',
    entries: mapCategory('weather_events', (id, v) => {
      const facts = [
        { label: 'Triggers', value: asArray(v.trigger_kinds).map(titleCase).join(', ') },
        { label: 'Bands', value: asArray(v.band_names).map(titleCase).join(', ') },
        { label: 'Cooldown', value: v.cooldown_sec ? `${Math.round(v.cooldown_sec / 60)} min` : '' },
      ];
      return makeEntry(id, v.display_name, '', [], facts);
    }),
  });

  // Gateways
  categories.push({
    key: 'gateways',
    label: 'Gateways',
    blurb: 'The doors and passages that connect one place to the next.',
    entries: mapCategory('gateways', (id, v) => {
      const facts = [
        { label: 'From', value: prettyId(v.source_zone_id) },
        { label: 'To', value: prettyId(v.destination_zone_id) },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // NPCs
  categories.push({
    key: 'npcs',
    label: 'People',
    blurb: 'The villagers, vendors, and wanderers who hold the world together.',
    entries: mapCategory('npcs', (id, v) => {
      const facts = [
        { label: 'Zone', value: prettyId(v.zone_id) },
        { label: 'Level', value: asText(v.level) },
        { label: 'Greeting', value: asText(v.greeting) },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Hordes
  categories.push({
    key: 'hordes',
    label: 'Hordes',
    blurb: 'The wave events that scale with the players who answer them.',
    entries: mapCategory('hordes', (id, v) => {
      const facts = [
        { label: 'Waves', value: asText(asArray(v.waves).length) },
        { label: 'Reward gold', value: v.reward_gold ? `${v.reward_gold} g` : '' },
        { label: 'Reward XP', value: asText(v.reward_xp) },
      ];
      return makeEntry(id, v.display_name, '', [], facts);
    }),
  });

  // Loot tables
  categories.push({
    key: 'loot_tables',
    label: 'Loot Tables',
    blurb: 'What the world drops, and the odds it drops it.',
    entries: mapCategory('loot_tables', (id, v) => {
      // entries parse as a string when the .tres array is multi-line;
      // count the "item_id" occurrences so the number stays honest.
      const rawEntries = typeof v.entries === 'string' ? v.entries : JSON.stringify(v.entries || []);
      const entryCount = (rawEntries.match(/item_id/g) || []).length;
      const facts = [
        { label: 'Level', value: asText(v.level) },
        { label: 'Drops', value: `${asText(v.min_items_dropped)}-${asText(v.max_items_dropped)}` },
        { label: 'Possible items', value: entryCount ? asText(entryCount) : '' },
      ];
      return makeEntry(id, v.name || v.display_name, v.description, [], facts);
    }),
  });

  // Currencies
  categories.push({
    key: 'currencies',
    label: 'Currencies',
    blurb: 'The monies of the world, from coin to Concord Sigil.',
    entries: mapCategory('currencies', (id, v) => {
      const facts = [
        { label: 'Symbol', value: asText(v.symbol) },
        { label: 'Gold value', value: asText(v.gold_per_unit) },
      ];
      return makeEntry(id, v.display_name, v.description, [], facts);
    }),
  });

  // Drop categories with no entries (keeps the nav honest).
  return categories.filter((c) => c.entries.length > 0);
}

export const CODEX_TOTAL = (() => {
  const cats = buildCodex();
  return cats.reduce((n, c) => n + c.entries.length, 0);
})();
