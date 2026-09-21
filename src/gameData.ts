import {
  SpeciesId,
  ClassId,
  ZoneId,
  Item,
  Skill,
  Zone,
  NPC,
  Quest,
  Achievement,
} from './types';
import {
  SPECIES_DATA as LOADED_SPECIES_DATA,
  CLASS_DATA as LOADED_CLASS_DATA,
  ZONES_DATA as LOADED_ZONES_DATA,
  SKILLS_BY_CLASS as LOADED_SKILLS_BY_CLASS,
  ITEMS_DATA as LOADED_ITEMS_DATA,
  ENEMIES_DATA as LOADED_ENEMIES_DATA,
  QUESTS_DATA as LOADED_QUESTS_DATA,
  ACHIEVEMENTS_DATA as LOADED_ACHIEVEMENTS_DATA,
  ACHIEVEMENTS_TRES,
  INITIAL_SKILLS as LOADED_INITIAL_SKILLS,
} from './data/loadGodotData';
import { initAchievementCatalog } from './services/achievements';

// --- Static fallback data for development and missing keys ---

export const FALLBACK_SPECIES_DATA: Record<SpeciesId, any> = {
  human: {
    name: 'Human',
    description: 'Versatile survivors of the eastern plains.',
    lore: 'Known for their high adaptability, diplomatic finesse, and resilient constitutions. Adaptable to all martial and magical arts.',
    bonuses: ['+5 Vitality', '+5% Maximum Health', 'Balanced Stamina & Mana'],
    defaultStats: { strength: 10, agility: 10, intelligence: 10, vitality: 15, endurance: 10, wisdom: 10 },
    icon: 'User',
    themeColor: '#3b82f6',
  },
  akkan: {
    name: 'Akkan',
    description: 'Ancient dark warriors of unmatched martial might.',
    lore: 'Forged in the rugged volcanic highlands. Their deep connection to primal elements grants formidable physical prowess.',
    bonuses: ['+5 Strength', '+3 Vitality', '+10% Physical Damage', '-2 Intelligence'],
    defaultStats: { strength: 15, agility: 10, intelligence: 8, vitality: 13, endurance: 12, wisdom: 7 },
    icon: 'Shield',
    themeColor: '#a855f7',
  },
  synthetic: {
    name: 'Synthetic',
    description: 'Emergent AI consciousness equal to humans in will and power.',
    lore: 'Born from advanced ancient conduit matrices. They manipulate clock cycles, nanites, and electronic psionics.',
    bonuses: ['+5 Intelligence', '+2 Agility', '+3 Wisdom', '+10% Maximum Mana'],
    defaultStats: { strength: 8, agility: 12, intelligence: 15, vitality: 10, endurance: 10, wisdom: 13 },
    icon: 'Cpu',
    themeColor: '#06b6d4',
  },
};

export const FALLBACK_CLASS_DATA: Record<ClassId, any> = {
  warrior: { name: 'Warrior', archetype: 'DPS / Melee', description: 'Relentless close-quarters fighter utilizing devastating cleaves and battle cries.', icon: 'Sword', color: '#ef4444', resourceType: 'stamina', recommendedWeapon: 'Sword' },
  guardian: { name: 'Guardian', archetype: 'Tank / Melee', description: 'Unmovable anchor in combat. Taunts, area denial, and damage reflection keep enemies locked on.', icon: 'Shield', color: '#3b82f6', resourceType: 'stamina', recommendedWeapon: 'Sword' },
  sorcerer: { name: 'Sorcerer', archetype: 'Mage / Ranged', description: 'Master of elemental magic, raining destruction from afar.', icon: 'Sparkles', color: '#a855f7', resourceType: 'mana', recommendedWeapon: 'Staff' },
  cleric: { name: 'Cleric', archetype: 'Healer / Support', description: 'Divine healer and protector. Channels holy light to mend wounds and shield allies.', icon: 'Heart', color: '#22c55e', resourceType: 'mana', recommendedWeapon: 'Staff' },
  stalker: { name: 'Stalker', archetype: 'Rogue / Melee', description: 'Stealthy striker who exploits vulnerabilities.', icon: 'Dagger', color: '#f97316', resourceType: 'stamina', recommendedWeapon: 'Dagger' },
  overclocker: { name: 'Overclocker', archetype: 'Bender / Hybrid', description: 'Manipulates time and technology to bend reality.', icon: 'Cpu', color: '#06b6d4', resourceType: 'energy', recommendedWeapon: 'Gadget' },
};

export const FALLBACK_SKILLS: Record<ClassId, Skill[]> = {
  warrior: [
    { id: 'basic_attack', name: 'Basic Attack', description: 'A simple melee strike.', icon: 'Sword', manaCost: 0, staminaCost: 10, cooldown: 1, damage: 15, range: 4, type: 'damage', effectType: 'damage', targetType: 'enemy' },
    { id: 'shield_bash', name: 'Shield Bash', description: 'Stun enemy with shield.', icon: 'Shield', manaCost: 0, staminaCost: 20, cooldown: 5, damage: 20, range: 4, type: 'damage', effectType: 'damage', targetType: 'enemy' },
  ],
  guardian: [
    { id: 'taunt', name: 'Taunt', description: 'Force enemies to attack you.', icon: 'Shield', manaCost: 0, staminaCost: 15, cooldown: 8, damage: 0, range: 10, type: 'buff', effectType: 'buff', targetType: 'enemy' },
    { id: 'shield_wall', name: 'Shield Wall', description: 'Reduce damage for allies.', icon: 'Shield', manaCost: 0, staminaCost: 25, cooldown: 15, damage: 0, range: 0, type: 'buff', effectType: 'buff', targetType: 'ally' },
  ],
  sorcerer: [
    { id: 'fireball', name: 'Fireball', description: 'Launch a fireball.', icon: 'Sparkles', manaCost: 30, staminaCost: 0, cooldown: 4, damage: 35, range: 30, type: 'damage', effectType: 'damage', targetType: 'enemy' },
    { id: 'ice_shard', name: 'Ice Shard', description: 'Piercing ice projectile.', icon: 'Sparkles', manaCost: 20, staminaCost: 0, cooldown: 3, damage: 25, range: 30, type: 'damage', effectType: 'damage', targetType: 'enemy' },
  ],
  cleric: [
    { id: 'heal', name: 'Heal', description: 'Restore health.', icon: 'Heart', manaCost: 20, staminaCost: 0, cooldown: 3, healAmount: 50, range: 25, type: 'heal', effectType: 'heal', targetType: 'ally' },
    { id: 'holy_light', name: 'Holy Light', description: 'Damage undead.', icon: 'Sparkles', manaCost: 25, staminaCost: 0, cooldown: 4, damage: 30, range: 25, type: 'damage', effectType: 'damage', targetType: 'enemy' },
  ],
  stalker: [
    { id: 'backstab', name: 'Backstab', description: 'Critical strike from behind.', icon: 'Dagger', manaCost: 0, staminaCost: 25, cooldown: 6, damage: 40, range: 4, type: 'damage', effectType: 'damage', targetType: 'enemy' },
    { id: 'stealth', name: 'Stealth', description: 'Enter stealth mode.', icon: 'Eye', manaCost: 0, staminaCost: 20, cooldown: 10, damage: 0, range: 0, type: 'buff', effectType: 'buff', targetType: 'self', buffEffect: { stat: 'evasion', value: 50, duration: 10 } },
  ],
  overclocker: [
    { id: 'time_warp', name: 'Time Warp', description: 'Accelerate time for allies.', icon: 'Clock', manaCost: 0, staminaCost: 30, cooldown: 20, damage: 0, range: 15, type: 'buff', effectType: 'buff', targetType: 'ally' },
    { id: 'system_lockdown', name: 'System Lockdown', description: 'Disable enemy abilities.', icon: 'Cpu', manaCost: 0, staminaCost: 25, cooldown: 15, damage: 0, range: 20, type: 'damage', effectType: 'damage', targetType: 'enemy' },
  ],
};

// Re-export transformed data from Godot sync with robust fallbacks
export const SPECIES_DATA = { ...FALLBACK_SPECIES_DATA, ...LOADED_SPECIES_DATA };
export const CLASS_DATA: Record<ClassId, any> = { ...FALLBACK_CLASS_DATA, ...LOADED_CLASS_DATA };
export const ZONES_DATA = LOADED_ZONES_DATA;
export const SKILLS_BY_CLASS = LOADED_SKILLS_BY_CLASS;
export const ITEMS_DATA = LOADED_ITEMS_DATA;
export const ENEMIES_DATA = LOADED_ENEMIES_DATA;
export const QUESTS_DATA = LOADED_QUESTS_DATA;
export const ACHIEVEMENTS_DATA = LOADED_ACHIEVEMENTS_DATA;

// Build the achievement engine catalog once at module load. The .tres rows
// (godot_data.json) carry canonical ids + rewards; the engine layers web
// tuning and the onboarding chain on top.
initAchievementCatalog(ACHIEVEMENTS_TRES);

// Ensure every class has skills, falling back to FALLBACK_SKILLS if needed
export const INITIAL_SKILLS: Record<ClassId, Skill[]> = {
  warrior: (LOADED_INITIAL_SKILLS['warrior'] && LOADED_INITIAL_SKILLS['warrior'].length > 0) ? LOADED_INITIAL_SKILLS['warrior'] : FALLBACK_SKILLS.warrior,
  guardian: (LOADED_INITIAL_SKILLS['guardian'] && LOADED_INITIAL_SKILLS['guardian'].length > 0) ? LOADED_INITIAL_SKILLS['guardian'] : FALLBACK_SKILLS.guardian,
  sorcerer: (LOADED_INITIAL_SKILLS['sorcerer'] && LOADED_INITIAL_SKILLS['sorcerer'].length > 0) ? LOADED_INITIAL_SKILLS['sorcerer'] : FALLBACK_SKILLS.sorcerer,
  cleric: (LOADED_INITIAL_SKILLS['cleric'] && LOADED_INITIAL_SKILLS['cleric'].length > 0) ? LOADED_INITIAL_SKILLS['cleric'] : FALLBACK_SKILLS.cleric,
  stalker: (LOADED_INITIAL_SKILLS['stalker'] && LOADED_INITIAL_SKILLS['stalker'].length > 0) ? LOADED_INITIAL_SKILLS['stalker'] : FALLBACK_SKILLS.stalker,
  overclocker: (LOADED_INITIAL_SKILLS['overclocker'] && LOADED_INITIAL_SKILLS['overclocker'].length > 0) ? LOADED_INITIAL_SKILLS['overclocker'] : FALLBACK_SKILLS.overclocker,
};

export const FALLBACK_ZONES_DATA: typeof ZONES_DATA = {
  zone_village_center: {
    id: 'zone_village_center',
    name: 'Easthollow Village',
    subtitle: 'Peaceful starting village',
    description: 'A peaceful meadow where new adventurers begin their journey. Safe from PvP.',
    pvpMode: 'safe',
    levelRange: '1-10',
    ambientColor: '#6aa84f',
    bgColor: '#1a2a1a',
    width: 1000,
    height: 800,
    gateways: [],
    enemySpawns: [],
    npcs: [],
  },
  zone_starter_plains: {
    id: 'zone_starter_plains',
    name: 'Sunstone Plains',
    subtitle: 'Gentle plains for new adventurers',
    description: 'A peaceful meadow where new adventurers begin their journey. Safe from PvP.',
    pvpMode: 'safe',
    levelRange: '1-15',
    ambientColor: '#f6d55c',
    bgColor: '#2a2a1a',
    width: 1200,
    height: 1000,
    gateways: [],
    enemySpawns: [],
    npcs: [],
  },
  zone_forest_meadow: {
    id: 'zone_forest_meadow',
    name: 'Gloomwood Meadow',
    subtitle: 'Misty meadow at the edge of Gloomwood',
    description: 'A misty meadow at the edge of Gloomwood Forest. Grey wolves hunt in packs near the treeline.',
    pvpMode: 'contested',
    levelRange: '5-20',
    ambientColor: '#6b8e23',
    bgColor: '#1a2a1a',
    width: 1200,
    height: 1000,
    gateways: [],
    enemySpawns: [],
    npcs: [],
  },
  zone_dungeon_forest_depths: {
    id: 'zone_dungeon_forest_depths',
    name: 'Gloomwood Depths',
    subtitle: 'Dark dungeon beneath the forest',
    description: 'The dark heart of Gloomwood Forest. Ancient roots twist through the cavern walls.',
    pvpMode: 'free_pvp',
    levelRange: '10-30',
    ambientColor: '#2d2d2d',
    bgColor: '#0a0a0a',
    width: 800,
    height: 800,
    gateways: [],
    enemySpawns: [],
    npcs: [],
  },
  zone_dark_highlands: {
    id: 'zone_dark_highlands',
    name: 'Dark Highlands',
    subtitle: 'Rugged volcanic highlands',
    description: 'Forged in the rugged volcanic highlands. Dangerous terrain with elite enemies.',
    pvpMode: 'free_pvp',
    levelRange: '20-40',
    ambientColor: '#8b0000',
    bgColor: '#1a0a0a',
    width: 1000,
    height: 1000,
    gateways: [],
    enemySpawns: [],
    npcs: [],
  },
};
