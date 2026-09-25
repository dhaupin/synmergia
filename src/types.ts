export type SpeciesId = 'human' | 'akkan' | 'synthetic';

export type ClassId = 'warrior' | 'guardian' | 'sorcerer' | 'cleric' | 'stalker' | 'overclocker';

export type ZoneId =
  | 'zone_village_center'
  | 'zone_starter_plains'
  | 'zone_forest_meadow'
  | 'zone_dungeon_forest_depths'
  | 'zone_dark_highlands';

export type ItemRarity = 'common' | 'uncommon' | 'rare' | 'epic' | 'legendary' | 'mythic';

export type ItemType = 'weapon' | 'armor' | 'accessory' | 'consumable' | 'material' | 'misc' | 'event' | 'gem' | 'dwelling' | 'skill_book';

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
  upgradeTiers?: any[];
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
  achievementProgress?: AchievementProgress;
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

export type AchievementCategoryId =
  | 'combat'
  | 'social'
  | 'economy'
  | 'exploration'
  | 'progression';

export type AchievementTier = 'bronze' | 'silver' | 'gold' | 'epic';

export type AchievementTriggerType = 'instant' | 'counter' | 'first_session';

/** Canonical definition merged from godot_data.json (.tres source of truth) + web tuning. */
export interface AchievementDef {
  id: string;
  title: string;
  description: string;
  icon: string;
  category: AchievementCategoryId;
  tier: AchievementTier;
  trigger: AchievementTriggerType;
  /** Counter key this achievement reads (when trigger is counter/threshold). */
  counter?: AchievementCounterKey;
  /** Unlock threshold for counter achievements. */
  target?: number;
  /** Gold awarded on unlock (from .tres gold_reward). */
  goldReward: number;
  /** XP awarded on unlock (from .tres xp_reward). */
  xpReward: number;
  /** Title granted on unlock (from .tres title_reward -> TitleData). */
  titleReward?: string;
  /** Event types that instantly unlock this achievement (trigger === 'instant'). */
  instantOn?: AchievementEventType[];
  /** Points shown in the Hall of Valor. */
  points: number;
  /** Onboarding chain id (e.g. 'onboarding'); non-chain achievements omit this. */
  chain?: string;
  /** Sort position within the chain (1-based) — unlocks gate on the previous step. */
  chainStep?: number;
}

export type AchievementCounterKey =
  | 'kills'
  | 'boss_kills'
  | 'bandit_kills'
  | 'elite_kills'
  | 'gold_earned'
  | 'items_collected'
  | 'items_sold'
  | 'items_crafted'
  | 'potions_used'
  | 'skills_cast'
  | 'crits'
  | 'quests_completed'
  | 'zones_visited'
  | 'chat_messages'
  | 'npcs_talked';

export type AchievementEventType =
  | 'session_started'
  | 'enemy_defeated'
  | 'crit_landed'
  | 'gold_earned'
  | 'item_bought'
  | 'item_sold'
  | 'item_crafted'
  | 'item_looted'
  | 'potion_used'
  | 'skill_cast'
  | 'quest_completed'
  | 'zone_visited'
  | 'chat_sent'
  | 'npc_talked'
  | 'level_up'
  | 'party_joined'
  | 'guild_joined'
  | 'trade_completed';

export interface AchievementEvent {
  type: AchievementEventType;
  /** Enemy templateId for kills, item id for economy, zone id for travel, etc. */
  targetId?: string;
  amount?: number;
  isBoss?: boolean;
  isElite?: boolean;
  meta?: Record<string, unknown>;
}

export interface AchievementCounters {
  kills: number;
  boss_kills: number;
  bandit_kills: number;
  elite_kills: number;
  gold_earned: number;
  items_collected: number;
  items_sold: number;
  items_crafted: number;
  potions_used: number;
  skills_cast: number;
  crits: number;
  quests_completed: number;
  zones_visited: number;
  chat_messages: number;
  npcs_talked: number;
  [key: string]: number;
}

/** Persisted with the character save so onboarding chains survive reloads. */
export interface AchievementProgress {
  /** id -> unlock timestamp (0 = migrated, time unknown). */
  unlocked: Record<string, number>;
  counters: AchievementCounters;
  /** Zone ids already credited toward zones_visited. */
  visitedZones: string[];
}

export interface AchievementUnlock {
  def: AchievementDef;
  unlockedAt: number;
}

export interface Achievement {
  id: string;
  title: string;
  description: string;
  icon?: string;
  category?: AchievementCategoryId;
  unlocked: boolean;
  points?: number;
  tier?: AchievementTier;
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

/** WebSocket message emitted by the authoritative server when it unlocks an achievement. */
export interface AchievementUnlockedMessage {
  achievementId?: string;
  id?: string;
  title?: string;
  playerId?: string;
}
