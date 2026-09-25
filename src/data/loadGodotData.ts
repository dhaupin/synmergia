import godotData from './godot_data.json';
import type {
  SpeciesId,
  ClassId,
  ZoneId,
  Item,
  Skill,
  Zone,
  NPC,
  Quest,
  Achievement,
  AchievementCategoryId,
  AchievementTier,
  CharacterStats,
  ItemStats,
  ItemRarity,
  ItemType,
  EquipSlot,
} from '../types';

const RAW = godotData as any;

// --- Helpers ---
function colorToHex(c: { r: number; g: number; b: number; a?: number } | string): string {
  if (typeof c === 'string') return c;
  const r = Math.round((c.r || 0) * 255);
  const g = Math.round((c.g || 0) * 255);
  const b = Math.round((c.b || 0) * 255);
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
}

function vec2(v: { v3: number[] } | { x: number; y: number }): { x: number; y: number } {
  if (v && 'v3' in v) return { x: v.v3[0] || 0, y: v.v3[1] || 0 };
  return { x: (v as any).x || 0, y: (v as any).y || 0 };
}

function parseUpgradeTiers(s: string): any[] {
  try {
    // Fix malformed JSON: trailing commas in objects/arrays
    const fixed = s.replace(/,(\s*[}\]])/g, '$1');
    return JSON.parse(fixed);
  } catch {
    return [];
  }
}

function mapPvpMode(n: number): 'safe' | 'contested' | 'free_pvp' {
  return n === 0 ? 'safe' : n === 1 ? 'contested' : 'free_pvp';
}

function mapResourceType(n: number): 'mana' | 'stamina' | 'energy' {
  return n === 0 ? 'stamina' : n === 1 ? 'mana' : 'energy';
}

function mapRole(n: number): ClassId {
  const map: Record<number, ClassId> = { 
    1: 'guardian',  // tank
    2: 'warrior',   // dps
    3: 'sorcerer',  // mage
    4: 'stalker',   // rogue
    5: 'overclocker', // bender
    6: 'cleric'     // healer
  };
  return map[n] || 'warrior';
}

export function normalizeClassId(id: string): ClassId {
  const k = (id || '').toLowerCase();
  if (k.includes('guardian') || k.includes('bulwark') || k.includes('warden')) return 'guardian';
  if (k.includes('sorcerer') || k.includes('rune') || k.includes('psion') || k.includes('mage')) return 'sorcerer';
  if (k.includes('cleric') || k.includes('shaman') || k.includes('conduit') || k.includes('healer')) return 'cleric';
  if (k.includes('stalker') || k.includes('marksman') || k.includes('tracker') || k.includes('rogue')) return 'stalker';
  if (k.includes('overclocker') || k.includes('temporalist') || k.includes('seer') || k.includes('bender')) return 'overclocker';
  return 'warrior';
}

function mapRarity(n: number): ItemRarity {
  const map: ItemRarity[] = ['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic'];
  return map[n] || 'common';
}

function mapItemType(cat: number): ItemType {
  const map: Record<number, ItemType> = { 0: 'weapon', 1: 'armor', 2: 'consumable', 3: 'material', 5: 'misc' };
  return map[cat] || 'misc';
}

function mapEquipSlot(slot: number): EquipSlot {
  const map: Record<number, EquipSlot> = {
    0: 'head', 1: 'chest', 5: 'main_hand', 6: 'off_hand', 7: 'accessory', 8: 'accessory', 9: 'accessory'
  };
  return map[slot] || 'accessory';
}

function skillIcon(skillType: number): string {
  return skillType === 3 ? 'Heart' : skillType === 2 ? 'Shield' : 'Sword';
}

// --- Transforms ---
export function transformSpecies(): Record<SpeciesId, any> {
  const out: Record<string, any> = {};
  for (const [id, s] of Object.entries(RAW.species || {})) {
    const sp = s as any;
    out[id] = {
      name: sp.display_name || id,
      description: sp.description || '',
      lore: sp.description || '',
      bonuses: sp.stat_modifiers
        ? Object.entries(sp.stat_modifiers)
            .filter(([, v]) => (v as number) > 0)
            .map(([k, v]) => `+${v} ${k.charAt(0).toUpperCase() + k.slice(1)}`)
        : [],
      defaultStats: {
        strength: sp.stat_modifiers?.strength || 10,
        agility: sp.stat_modifiers?.agility || 10,
        intelligence: sp.stat_modifiers?.intelligence || 10,
        vitality: sp.stat_modifiers?.vitality || 10,
        endurance: sp.stat_modifiers?.endurance || 10,
        wisdom: sp.stat_modifiers?.wisdom || 10,
      },
      icon: sp.icon_path?.split('/').pop()?.replace('.png', '') || 'User',
      themeColor: sp.health_modifier > 1 ? '#ef4444' : sp.mana_modifier > 1 ? '#3b82f6' : '#06b6d4',
    };
  }
  return out as Record<SpeciesId, any>;
}

export function transformClasses(): Record<ClassId, any> {
  const out: Record<string, any> = {};
  const archetypeNames: Record<ClassId, string> = {
    warrior: 'DPS / Melee',
    guardian: 'Tank / Melee',
    sorcerer: 'Mage / Ranged',
    cleric: 'Healer / Support',
    stalker: 'Rogue / Melee',
    overclocker: 'Bender / Hybrid',
  };

  for (const [id, c] of Object.entries(RAW.classes || {})) {
    const cl = c as any;
    const archetype = mapRole(cl.role);
    const classObj = {
      name: cl.display_name || id,
      archetype: archetypeNames[archetype] || 'DPS',
      description: cl.description || '',
      icon: archetype === 'guardian' ? 'Shield' : archetype === 'sorcerer' ? 'Sparkles' : archetype === 'cleric' ? 'Heart' : archetype === 'stalker' ? 'Crosshair' : archetype === 'overclocker' ? 'Cpu' : 'Sword',
      color: archetype === 'guardian' ? '#3b82f6' : archetype === 'cleric' ? '#22c55e' : archetype === 'sorcerer' ? '#a855f7' : archetype === 'stalker' ? '#f97316' : archetype === 'overclocker' ? '#06b6d4' : '#ef4444',
      resourceType: mapResourceType(cl.resource_type),
      recommendedWeapon: cl.default_weapon_path || 'Sword',
    };
    out[id] = classObj;
    const normId = normalizeClassId(id);
    if (!out[normId] || id === normId || id.startsWith('human_')) {
      out[normId] = classObj;
    }
  }

  // Ensure all 6 base archetypes are guaranteed to exist
  const baseClasses: ClassId[] = ['warrior', 'guardian', 'sorcerer', 'cleric', 'stalker', 'overclocker'];
  for (const b of baseClasses) {
    if (!out[b]) {
      out[b] = {
        name: b.charAt(0).toUpperCase() + b.slice(1),
        archetype: archetypeNames[b],
        description: `Master of the ${b} discipline.`,
        icon: b === 'guardian' ? 'Shield' : b === 'sorcerer' ? 'Sparkles' : b === 'cleric' ? 'Heart' : b === 'stalker' ? 'Crosshair' : b === 'overclocker' ? 'Cpu' : 'Sword',
        color: b === 'guardian' ? '#3b82f6' : b === 'cleric' ? '#22c55e' : b === 'sorcerer' ? '#a855f7' : b === 'stalker' ? '#f97316' : b === 'overclocker' ? '#06b6d4' : '#ef4444',
        resourceType: (b === 'sorcerer' || b === 'cleric') ? 'mana' : b === 'overclocker' ? 'energy' : 'stamina',
        recommendedWeapon: 'Sword',
      };
    }
  }

  return out as Record<ClassId, any>;
}

export function transformZones(): Record<ZoneId, Zone> {
  const out: Record<string, Zone> = {};
  for (const [id, z] of Object.entries(RAW.zones || {})) {
    const zn = z as any;
    const width = zn.zone_radius ? zn.zone_radius * 2 : 1000;
    const height = zn.zone_radius ? zn.zone_radius * 2 : 1000;
    out[id] = {
      id: zn.id as ZoneId,
      name: zn.display_name || id,
      subtitle: zn.description || '',
      description: zn.description || '',
      pvpMode: mapPvpMode(zn.pvp_mode),
      levelRange: `${zn.level_requirement || 1}-${zn.max_level || 50}`,
      ambientColor: zn.ambient_light_color ? colorToHex(zn.ambient_light_color) : '#888888',
      bgColor: '#1a1a2e',
      width,
      height,
      gateways: [],
      enemySpawns: (zn.spawn_points || []).map((sp: any, i: number) => ({
        templateId: 'wolf',
        level: zn.level_requirement || 1,
        x: vec2(sp).x,
        y: vec2(sp).y,
        isBoss: false,
        isElite: false,
      })),
      npcs: (zn.npcs || []).map((n: any) => ({
        id: n.id || '',
        name: n.display_name || '',
        title: n.role || 'NPC',
        role: (n.role as any) || 'merchant',
        greeting: '',
        dialogue: [],
        questIds: [],
        x: vec2(n.position || n.spawn_point || { v3: [0, 0, 0] }).x,
        y: vec2(n.position || n.spawn_point || { v3: [0, 0, 0] }).y,
      })),
    };
  }
  return out as Record<ZoneId, Zone>;
}

export function transformSkills(): Record<string, Skill[]> {
  const out: Record<string, Skill[]> = {
    warrior: [],
    guardian: [],
    sorcerer: [],
    cleric: [],
    stalker: [],
    overclocker: [],
  };

  for (const [id, s] of Object.entries(RAW.skills || {})) {
    const sk = s as any;
    const rawClass = sk.required_class || 'warrior';
    const normClass = normalizeClassId(rawClass);

    const skill: Skill = {
      id: sk.id,
      name: sk.display_name || id,
      description: sk.description || '',
      icon: skillIcon(sk.skill_type),
      manaCost: sk.mana_cost || 0,
      staminaCost: sk.mana_cost || 0,
      cooldown: sk.cooldown || 1,
      damage: sk.effects?.[0]?.type === 'damage' ? sk.effects[0].value : 0,
      healAmount: sk.effects?.[0]?.type === 'heal' ? sk.effects[0].value : 0,
      range: sk.range || 20,
      type: sk.skill_type === 3 ? 'heal' : sk.skill_type === 2 ? 'buff' : 'damage',
      effectType: sk.skill_type === 3 ? 'heal' : sk.skill_type === 2 ? 'buff' : 'damage',
      targetType: sk.target_type === 3 ? 'ally' : sk.target_type === 2 ? 'area' : 'enemy',
      buffEffect: sk.effects?.[0]?.type === 'buff' ? { stat: 'armor', value: 10, duration: sk.effects[0].duration || 10 } : undefined,
      requiredLevel: sk.required_level,
      classId: normClass,
      upgradeTiers: sk.upgrade_tiers ? parseUpgradeTiers(sk.upgrade_tiers) : [],
    };

    if (!out[rawClass]) out[rawClass] = [];
    out[rawClass].push(skill);

    if (!out[normClass]) out[normClass] = [];
    out[normClass].push(skill);
  }

  return out;
}

export function transformItems(): Item[] {
  const out: Item[] = [];
  for (const [id, it] of Object.entries(RAW.weapons || {})) {
    const i = it as any;
    out.push({
      id: i.id,
      name: i.display_name || id,
      type: mapItemType(i.item_category),
      rarity: mapRarity(i.rarity),
      slot: mapEquipSlot(i.equip_slot),
      description: i.description || '',
      stats: {
        attackPower: i.weapon_damage_min ? (i.weapon_damage_min + i.weapon_damage_max) / 2 : undefined,
        armor: i.armor_value,
        ...i.stats,
      },
      value: i.sell_price || i.buy_price || 0,
      icon: i.icon_path?.split('/').pop()?.replace('.png', '') || 'Sword',
    });
  }
  for (const [id, it] of Object.entries(RAW.armors || {})) {
    const i = it as any;
    out.push({
      id: i.id,
      name: i.display_name || id,
      type: 'armor',
      rarity: mapRarity(i.rarity),
      slot: mapEquipSlot(i.equip_slot),
      description: i.description || '',
      stats: { armor: i.armor_value },
      value: i.sell_price || i.buy_price || 0,
      icon: i.icon_path?.split('/').pop()?.replace('.png', '') || 'Shield',
    });
  }
  for (const [id, it] of Object.entries(RAW.consumables || {})) {
    const i = it as any;
    out.push({
      id: i.id,
      name: i.display_name || id,
      type: 'consumable',
      rarity: mapRarity(i.rarity),
      slot: 'accessory',
      description: i.description || '',
      healAmount: i.stats?.heal || i.effects?.[0]?.value,
      manaAmount: i.stats?.mana || 0,
      value: i.sell_price || i.buy_price || 0,
      icon: i.icon_path?.split('/').pop()?.replace('.png', '') || 'Heart',
    });
  }
  // Generic items: data/items (quest tokens, coins), data/accessories
  // (rings, necklaces, cloaks, belts), data/resources (crafting mats).
  for (const src of [RAW.items, RAW.accessories, RAW.resources]) {
    for (const [id, it] of Object.entries(src || {})) {
      const i = it as any;
      out.push({
        id: i.id,
        name: i.display_name || id,
        type: mapItemType(i.item_category),
        rarity: mapRarity(i.rarity),
        slot: mapEquipSlot(i.equip_slot),
        description: i.description || '',
        stats: i.stats || {},
        value: i.sell_price || i.buy_price || 0,
        icon: i.icon_path?.split('/').pop()?.replace('.png', '') || 'Package',
      });
    }
  }
  return out;
}

export function transformEnemies(): Record<string, any> {
  const out: Record<string, any> = {};
  for (const [id, e] of Object.entries(RAW.enemies || {})) {
    const en = e as any;
    out[id] = {
      id: en.id,
      templateId: en.id,
      name: en.display_name || id,
      level: en.level || 1,
      hp: en.base_health || 100,
      maxHp: en.base_health || 100,
      attackPower: en.attack_power || 10,
      armor: en.defense || 0,
      x: 0, y: 0,
      spawnX: 0, spawnY: 0,
      state: 'patrol',
      patrolRadius: 80,
      aggroRadius: 160,
      attackRange: 40,
      attackCooldown: 0,
      xpReward: en.xp_reward || 10,
      goldReward: en.gold_reward || 5,
      isBoss: en.is_boss || false,
      isElite: en.is_elite || false,
    };
  }
  return out;
}

export function transformQuests(): Record<string, Quest> {
  const out: Record<string, Quest> = {};
  for (const [id, q] of Object.entries(RAW.quests || {})) {
    const qu = q as any;
    out[id] = {
      id: qu.id,
      title: qu.display_name || id,
      description: qu.description || '',
      giverNpcId: '',
      targetType: qu.target_type || 'kill',
      targetId: qu.target_name || '',
      targetName: qu.target_name || '',
      requiredCount: qu.required_count || 1,
      rewards: { xp: qu.rewards?.xp || 0, gold: qu.rewards?.gold || 0, items: qu.rewards?.items || [] },
    };
  }
  return out;
}

export function transformAchievements(): Achievement[] {
  const out: Achievement[] = [];
  for (const [id, a] of Object.entries(RAW.achievements || {})) {
    const ac = a as any;
    out.push({
      id: ac.id || id,
      title: ac.display_name || id,
      description: ac.description || '',
      icon: ac.icon_path?.split('/').pop()?.replace('.png', '') || 'Award',
      category: mapAchievementCategory(ac.category),
      unlocked: false,
      points: 10,
      tier: mapAchievementTier(ac.rarity),
    });
  }
  return out;
}

const ACHIEVEMENT_CATEGORY_MAP: Record<number, AchievementCategoryId> = {
  0: 'combat',
  1: 'social',
  2: 'economy',
  3: 'exploration',
  4: 'progression',
};

function mapAchievementCategory(n: number | undefined): AchievementCategoryId {
  return ACHIEVEMENT_CATEGORY_MAP[n ?? 4] ?? 'progression';
}

const ACHIEVEMENT_TIER_MAP: Record<number, AchievementTier> = {
  0: 'bronze',
  1: 'silver',
  2: 'gold',
  3: 'epic',
  4: 'epic',
};

function mapAchievementTier(n: number | undefined): AchievementTier {
  return ACHIEVEMENT_TIER_MAP[n ?? 0] ?? 'bronze';
}

// --- Aggregated exports ---
export const SPECIES_DATA = transformSpecies();
export const CLASS_DATA = transformClasses();
export const ZONES_DATA = transformZones();
export const SKILLS_BY_CLASS = transformSkills();
export const ITEMS_DATA = transformItems();
export const ENEMIES_DATA = transformEnemies();
export const QUESTS_DATA = transformQuests();
export const ACHIEVEMENTS_DATA = transformAchievements();

// --- Raw .tres achievement rows (rewards live here, not in the UI mapping) ---
export const ACHIEVEMENTS_TRES = (RAW.achievements || {}) as Record<
  string,
  {
    id?: string;
    display_name?: string;
    description?: string;
    gold_reward?: number;
    xp_reward?: number;
    title_reward?: string;
  }
>;

// --- Init skills per class (for backward compat) ---
export const INITIAL_SKILLS: Record<ClassId, Skill[]> = SKILLS_BY_CLASS;