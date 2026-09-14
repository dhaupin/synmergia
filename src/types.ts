export type SpeciesId = 'human' | 'akkan' | 'synthetic';

export type ClassId = 'warrior' | 'guardian' | 'sorcerer' | 'cleric' | 'stalker' | 'overclocker';

export type ZoneId =
  | 'zone_village_center'
  | 'zone_starter_plains'
  | 'zone_forest_meadow'
  | 'zone_dungeon_forest_depths'
  | 'zone_dark_highlands';

export type ItemRarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary';

export type ItemType = 'weapon' | 'armor' | 'accessory' | 'consumable' | 'material' | 'misc';

export type EquipSlot = 'head' | 'chest' | 'main_hand' | 'off_hand' | 'accessory';

export interface ItemStats {
  attackPower?: number;
  spellPower?: number;
  armor?: number;
  vitality?: number;
  strength?: number;
  agility?: number;
  intelligence?: number;
  wisdom?: number;
  healthBonus?: number;
  manaBonus?: number;
}

export interface Item {
  id: string;
  name: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  value: number; // Gold value
  slot?: EquipSlot;
  stats?: ItemStats;
  icon?: string;
  quantity?: number;
  healAmount?: number;
  manaAmount?: number;
  cooldown?: number; // In seconds
}

export interface Skill {
  id: string;
  name: string;
  description: string;
  icon: string;
  manaCost: number;
  staminaCost: number;
  cooldown: number; // In seconds
  range: number; // Range in game units
  damage?: number;
  damageMultiplier?: number;
  healAmount?: number;
  shieldAmount?: number;
  castTime?: number; // 0 = instant
  type?: 'damage' | 'heal' | 'buff' | 'aoe' | 'dash' | 'spell';
  effectType?: 'damage' | 'heal' | 'buff' | 'aoe' | 'dash';
  targetType?: 'enemy' | 'self' | 'ally' | 'area';
  buffEffect?: {
    stat: string;
    value: number;
    duration: number;
  };
  requiredLevel?: number;
  classId?: ClassId;
}

export interface StatusEffect {
  id: string;
  name: string;
  icon?: string;
  stat?: string;
  value?: number;
  duration: number; // Remaining duration in seconds
  maxDuration?: number;
  isDebuff?: boolean;
  statModifier?: Partial<ItemStats>;
  dotDamage?: number; // Damage per tick
  hotHeal?: number; // Heal per tick
}

export interface CharacterStats {
  strength: number;
  agility: number;
  intelligence: number;
  vitality: number;
  endurance: number;
  wisdom: number;
}

export interface PlayerCharacter {
  id: string;
  name: string;
  species: SpeciesId;
  classId: ClassId;
  level: number;
  xp: number;
  maxXp: number;
  hp: number;
  maxHp: number;
  mp: number;
  maxMp: number;
  stamina: number;
  maxStamina: number;
  gold: number;
  stats: CharacterStats;
  inventory: (Item | null)[];
  equipment: Partial<Record<EquipSlot, Item | null>>;
  activeBuffs: StatusEffect[];
  activeQuests: { questId: string; progress: number }[];
  completedQuests: string[];
  unlockedAchievements: string[];
  x: number;
  y: number;
  zoneId?: ZoneId;
  targetId?: string | null;
  direction?: 'up' | 'down' | 'left' | 'right';
  isMoving?: boolean;
  inCombat?: boolean;
}

export interface Enemy {
  id: string;
  templateId: string;
  name: string;
  description?: string;
  level: number;
  hp: number;
  maxHp: number;
  attackPower: number;
  armor: number;
  xpReward: number;
  goldMin?: number;
  goldMax?: number;
  goldReward: number;
  x: number;
  y: number;
  startX?: number;
  startY?: number;
  spawnX: number;
  spawnY: number;
  isBoss: boolean;
  isElite: boolean;
  aggroRadius: number;
  attackRange: number;
  attackCooldown: number;
  attackSpeed?: number;
  lastAttackTime?: number;
  isAggressive?: boolean;
  state: 'idle' | 'chase' | 'attack' | 'dead' | 'patrol';
  patrolRadius?: number;
  respawnTime?: number;
  lootTable?: { itemId: string; dropRate: number }[];
  icon?: string;
}

export interface NPC {
  id: string;
  name: string;
  title: string;
  role: 'merchant' | 'blacksmith' | 'elder' | 'trainer';
  greeting: string;
  dialogue: string[];
  questIds: string[];
  shopItems?: string[];
  x: number;
  y: number;
  icon?: string;
}

export interface Quest {
  id: string;
  title: string;
  description: string;
  giverNpcId: string;
  targetType: 'kill' | 'gather' | 'talk';
  targetId: string; // enemy templateId or item or npc id
  targetName: string;
  requiredCount: number;
  rewards: {
    xp: number;
    gold: number;
    items?: { itemId: string; quantity: number }[];
  };
}

export interface Achievement {
  id: string;
  title: string;
  description: string;
  icon?: string;
  category?: 'combat' | 'exploration' | 'progression' | 'crafting';
  unlocked: boolean;
}

export interface ZoneGateway {
  targetZoneId: ZoneId;
  name: string;
  x: number;
  y: number;
  targetX: number;
  targetY: number;
}

export interface ZoneSpawn {
  templateId: string;
  x: number;
  y: number;
  level: number;
  isBoss?: boolean;
  isElite?: boolean;
}

export interface Zone {
  id: ZoneId;
  name: string;
  subtitle: string;
  description: string;
  pvpMode: 'safe' | 'contested' | 'free_pvp';
  levelRange: string;
  ambientColor: string;
  bgColor: string;
  width: number;
  height: number;
  gateways: ZoneGateway[];
  enemySpawns?: ZoneSpawn[];
  npcs?: NPC[];
}

export interface CombatText {
  id: string;
  text: string;
  x: number;
  y: number;
  type: 'damage' | 'crit' | 'heal' | 'xp' | 'gold' | 'miss';
  color: string;
  createdAt: number;
}

export interface ChatMessage {
  id: string;
  sender?: string;
  channel: 'global' | 'local' | 'party' | 'guild' | 'system' | 'combat' | 'all';
  text: string;
  timestamp: string | number;
}
