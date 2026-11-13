// Synmergia Achievement Engine
// Pure, side-effect-free core for the achievement system. The React layer
// (App.tsx) feeds game events in and consumes unlocks/rewards/announcement
// state out; the engine never touches React state, sound, or the DOM.
//
// Sources of truth:
//   - src/data/godot_data.json  (canonical .tres defs: ids, gold/xp/title rewards)
//   - ACHIEVEMENT_OVERRIDES     (web tuning: counters, tiers, points)
//   - ONBOARDING_CHAIN          ("First Steps in Haven" — gates the playable loop)
//
// `initAchievementCatalog()` must be called once at module load (done in
// gameData.ts) before any unlock evaluation happens.

import type {
  AchievementCategoryId,
  AchievementCounterKey,
  AchievementCounters,
  AchievementDef,
  AchievementEvent,
  AchievementEventType,
  AchievementProgress,
  AchievementUnlock,
} from '../types';

export type { AchievementUnlock };

// ---------------------------------------------------------------------------
// Catalog building blocks
// ---------------------------------------------------------------------------

/** Web-side tuning layered on top of the canonical .tres definitions. */
interface OverrideDef {
  description?: string;
  icon?: string;
  category: AchievementCategoryId;
  tier: AchievementDef['tier'];
  trigger: AchievementDef['trigger'];
  counter?: AchievementCounterKey;
  /** Extended counter keys (level) not part of the typed counter union. */
  counterExtended?: string;
  target?: number;
  instantOn?: AchievementEventType[];
  points: number;
}

/** Web-only achievements with no .tres counterpart yet. */
interface WebDef extends OverrideDef {
  id: string;
  title: string;
  /** Rewards are web-defined here (canonical .tres rows carry their own). */
  goldReward?: number;
  xpReward?: number;
  /** Onboarding chain id + 1-based step (set programmatically for the chain). */
  chain?: string;
  chainStep?: number;
}

interface TresRow {
  id?: string;
  display_name?: string;
  description?: string;
  gold_reward?: number;
  xp_reward?: number;
  title_reward?: string;
}

// --- Web tuning for canonical (.tres) achievements -------------------------

const ACHIEVEMENT_OVERRIDES: Record<string, OverrideDef> = {
  first_blood: {
    description: 'Defeat your first enemy',
    icon: 'Swords',
    category: 'combat',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'kills',
    target: 1,
    points: 10,
  },
  slayer_10: {
    description: 'Defeat 10 enemies',
    icon: 'Swords',
    category: 'combat',
    tier: 'silver',
    trigger: 'counter',
    counter: 'kills',
    target: 10,
    points: 25,
  },
  slayer_100: {
    description: 'Defeat 100 enemies',
    icon: 'Swords',
    category: 'combat',
    tier: 'gold',
    trigger: 'counter',
    counter: 'kills',
    target: 100,
    points: 50,
  },
  explorer: {
    description: 'Visit 10 zones',
    icon: 'Map',
    category: 'exploration',
    tier: 'silver',
    trigger: 'counter',
    counter: 'zones_visited',
    target: 10,
    points: 30,
  },
  collector_50: {
    description: 'Collect 50 items',
    icon: 'Backpack',
    category: 'economy',
    tier: 'silver',
    trigger: 'counter',
    counter: 'items_collected',
    target: 50,
    points: 30,
  },
  social_butterfly: {
    description: 'Join your first party',
    icon: 'Users',
    category: 'social',
    tier: 'bronze',
    trigger: 'instant',
    instantOn: ['party_joined'],
    points: 10,
  },
  guild_member: {
    description: 'Join a guild',
    icon: 'Castle',
    category: 'social',
    tier: 'bronze',
    trigger: 'instant',
    instantOn: ['guild_joined'],
    points: 10,
  },
  trader: {
    description: 'Complete your first trade',
    icon: 'Handshake',
    category: 'economy',
    tier: 'bronze',
    trigger: 'instant',
    instantOn: ['trade_completed'],
    points: 10,
  },
};

// --- Web-only achievements (id prefix ach_, legacy client ids kept) --------

const WEB_ONLY: WebDef[] = [
  {
    id: 'ach_bandit_scourge',
    title: 'Scourge of the Outlaws',
    description: 'Defeat 5 highway outlaws in the Sunstone Plains',
    icon: 'Flame',
    category: 'combat',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'bandit_kills',
    target: 5,
    points: 15,
  },
  {
    id: 'ach_boss_slayer',
    title: 'Conqueror of the Depths',
    description: 'Defeat a zone boss',
    icon: 'Skull',
    category: 'combat',
    tier: 'epic',
    trigger: 'counter',
    counter: 'boss_kills',
    target: 1,
    points: 50,
  },
  {
    id: 'ach_master_smith',
    title: 'Dwarven Temper',
    description: "Temper or forge at Torvald's Forge",
    icon: 'Hammer',
    category: 'economy',
    tier: 'gold',
    trigger: 'counter',
    counter: 'items_crafted',
    target: 1,
    points: 20,
  },
  {
    id: 'ach_realm_traveler',
    title: 'Wayfarer of the Shards',
    description: 'Discover 3 distinct zones via portal or map travel',
    icon: 'Compass',
    category: 'exploration',
    tier: 'silver',
    trigger: 'counter',
    counter: 'zones_visited',
    target: 3,
    points: 25,
  },
  {
    id: 'ach_veteran_adventurer',
    title: 'Veteran Adventurer',
    description: 'Reach level 10',
    icon: 'Star',
    category: 'progression',
    tier: 'silver',
    trigger: 'counter',
    counter: undefined,
    counterExtended: 'level',
    target: 10,
    points: 30,
  },
];

// --- Onboarding chain: "First Steps in Haven" --------------------------
// Steps unlock strictly in order, teaching the playable loop. This is the
// onboarding track that greets a brand-new character.

const ONBOARDING_CHAIN_RAW: WebDef[] = [
  {
    id: 'ob_wake',
    title: 'A New Dawn',
    description: 'Enter Synmergia for the first time',
    icon: 'Sunrise',
    category: 'progression',
    tier: 'bronze',
    trigger: 'first_session',
    points: 5,
    goldReward: 0,
    xpReward: 0,
  },
  {
    id: 'ob_first_skill',
    title: 'First Techniques',
    description: 'Cast your first skill',
    icon: 'Sparkles',
    category: 'progression',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'skills_cast',
    target: 1,
    points: 5,
    goldReward: 0,
    xpReward: 10,
  },
  {
    id: 'ob_first_kill',
    title: 'First Blood of Many',
    description: 'Defeat your first hostile',
    icon: 'Swords',
    category: 'progression',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'kills',
    target: 1,
    points: 10,
    goldReward: 15,
    xpReward: 25,
  },
  {
    id: 'ob_first_potion',
    title: 'Steady Hands',
    description: 'Drink a healing draught',
    icon: 'Heart',
    category: 'progression',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'potions_used',
    target: 1,
    points: 5,
    goldReward: 0,
    xpReward: 10,
  },
  {
    id: 'ob_first_quest',
    title: "The Adventurer's Path",
    description: 'Turn in your first quest',
    icon: 'ScrollText',
    category: 'progression',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'quests_completed',
    target: 1,
    points: 15,
    goldReward: 25,
    xpReward: 50,
  },
  {
    id: 'ob_first_shop',
    title: 'Honest Coin',
    description: 'Earn your first coin from the world (combat, quests, or sales)',
    icon: 'Coins',
    category: 'progression',
    tier: 'bronze',
    trigger: 'counter',
    counter: 'gold_earned',
    target: 1,
    points: 10,
    goldReward: 0,
    xpReward: 10,
  },
  {
    id: 'ob_forge',
    title: 'Sparks of the Forge',
    description: "Temper your blade at Torvald's Forge",
    icon: 'Hammer',
    category: 'progression',
    tier: 'silver',
    trigger: 'counter',
    counter: 'items_crafted',
    target: 1,
    points: 15,
    goldReward: 30,
    xpReward: 40,
  },
  {
    id: 'ob_wanderer',
    title: 'Wanderer',
    description: 'Set foot in 3 zones of Synmergia',
    icon: 'Compass',
    category: 'progression',
    tier: 'silver',
    trigger: 'counter',
    counter: 'zones_visited',
    target: 3,
    points: 20,
    goldReward: 50,
    xpReward: 60,
  },
  {
    id: 'ob_slayer_path',
    title: "The Slayer's Path",
    description: 'Defeat 10 hostiles',
    icon: 'Flame',
    category: 'progression',
    tier: 'gold',
    trigger: 'counter',
    counter: 'kills',
    target: 10,
    points: 25,
    goldReward: 75,
    xpReward: 100,
  },
  {
    id: 'ob_graduation',
    title: 'Beyond the Shards',
    description: 'Turn in 3 quests — the world opens up',
    icon: 'Crown',
    category: 'progression',
    tier: 'epic',
    trigger: 'counter',
    counter: 'quests_completed',
    target: 3,
    points: 40,
    goldReward: 150,
    xpReward: 200,
  },
];

const ONBOARDING_CHAIN: Array<WebDef & { chain: string; chainStep: number }> =
  ONBOARDING_CHAIN_RAW.map((def, i) => ({
    ...def,
    chain: 'onboarding' as string,
    chainStep: i + 1,
  }));

// ---------------------------------------------------------------------------
// Catalog assembly
// ---------------------------------------------------------------------------

function buildCatalog(tresRows: Record<string, TresRow>): AchievementDef[] {
  const catalog: AchievementDef[] = [];

  for (const [tresId, tres] of Object.entries(tresRows)) {
    const ov = ACHIEVEMENT_OVERRIDES[tresId];
    if (!ov) continue; // .tres entry without a web mapping yet
    catalog.push({
      id: tresId,
      title: tres.display_name || tresId,
      description: ov.description ?? tres.description ?? '',
      icon: ov.icon ?? 'Award',
      category: ov.category,
      tier: ov.tier,
      trigger: ov.trigger,
      counter: ov.counter,
      target: ov.target,
      instantOn: ov.instantOn,
      goldReward: tres.gold_reward ?? 0,
      xpReward: tres.xp_reward ?? 0,
      titleReward: tres.title_reward,
      points: ov.points,
    });
  }

  for (const def of [...WEB_ONLY, ...ONBOARDING_CHAIN]) {
    catalog.push({
      id: def.id,
      title: def.title,
      description: def.description ?? '',
      icon: def.icon ?? 'Award',
      category: def.category as AchievementCategoryId,
      tier: def.tier,
      trigger: def.trigger,
      counter: def.counter ?? (def.counterExtended as AchievementCounterKey | undefined),
      target: def.target,
      instantOn: def.instantOn,
      goldReward: def.goldReward ?? 0,
      xpReward: def.xpReward ?? 0,
      points: def.points,
      chain: def.chain,
      chainStep: def.chainStep,
    });
  }

  catalog.sort((a, b) => {
    if (a.chain && b.chain) return (a.chainStep ?? 0) - (b.chainStep ?? 0);
    if (a.chain) return -1;
    if (b.chain) return 1;
    if (a.category !== b.category) return a.category.localeCompare(b.category);
    return b.points - a.points;
  });

  return catalog;
}

// Injected once at module init via initAchievementCatalog().
let CATALOG: AchievementDef[] | null = null;
let BY_ID: Map<string, AchievementDef> | null = null;
let BY_CATEGORY: Record<AchievementCategoryId, AchievementDef[]> | null = null;
let CHAIN: AchievementDef[] | null = null;

export function initAchievementCatalog(tresRows: Record<string, TresRow>): void {
  CATALOG = buildCatalog(tresRows);
  BY_ID = new Map(CATALOG.map((d) => [d.id, d]));
  BY_CATEGORY = { combat: [], social: [], economy: [], exploration: [], progression: [] };
  for (const def of CATALOG) {
    BY_CATEGORY[def.category].push(def);
  }
  CHAIN = CATALOG.filter((d) => d.chain === 'onboarding').sort(
    (a, b) => (a.chainStep ?? 0) - (b.chainStep ?? 0)
  );
}

function assertCatalog(): void {
  if (!CATALOG) {
    initAchievementCatalog({});
  }
}

export function getCatalog(): AchievementDef[] {
  assertCatalog();
  return CATALOG!;
}

export function getAchievementById(id: string): AchievementDef | undefined {
  assertCatalog();
  return BY_ID!.get(id);
}

export function getAchievementsByCategory(): Record<AchievementCategoryId, AchievementDef[]> {
  assertCatalog();
  return BY_CATEGORY!;
}

export function getOnboardingChain(): AchievementDef[] {
  assertCatalog();
  return CHAIN!;
}

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------

const EMPTY_COUNTERS: AchievementCounters = {
  kills: 0,
  boss_kills: 0,
  bandit_kills: 0,
  elite_kills: 0,
  gold_earned: 0,
  items_collected: 0,
  items_sold: 0,
  items_crafted: 0,
  potions_used: 0,
  skills_cast: 0,
  crits: 0,
  quests_completed: 0,
  zones_visited: 0,
  chat_messages: 0,
  npcs_talked: 0,
  level: 1,
};

export function emptyCounters(): AchievementCounters {
  return { ...EMPTY_COUNTERS };
}

interface CounterUpdate {
  key: AchievementCounterKey | 'level' | 'trades_completed';
  /** Fixed delta, or a function of the event. */
  by?: number | ((ev: AchievementEvent) => number);
  /** Absolute set (overrides `by`). Used for counters that track a current value. */
  set?: (ev: AchievementEvent) => number;
  /** Optional gate — only applies when it returns true. */
  cond?: (ev: AchievementEvent) => boolean;
}

const EVENT_COUNTERS: Partial<Record<AchievementEventType, CounterUpdate[]>> = {
  enemy_defeated: [
    { key: 'kills', by: 1 },
    { key: 'boss_kills', by: 1, cond: (ev) => !!ev.isBoss },
    { key: 'bandit_kills', by: 1, cond: (ev) => ev.targetId === 'bandit' },
    { key: 'elite_kills', by: 1, cond: (ev) => !!ev.isElite },
  ],
  crit_landed: [{ key: 'crits', by: 1 }],
  gold_earned: [{ key: 'gold_earned', by: (ev) => Math.max(0, ev.amount ?? 0) }],
  item_looted: [{ key: 'items_collected', by: (ev) => Math.max(1, ev.amount ?? 1) }],
  item_bought: [{ key: 'items_collected', by: (ev) => Math.max(1, ev.amount ?? 1) }],
  item_sold: [{ key: 'items_sold', by: (ev) => Math.max(1, ev.amount ?? 1) }],
  item_crafted: [{ key: 'items_crafted', by: 1 }],
  potion_used: [{ key: 'potions_used', by: 1 }],
  skill_cast: [{ key: 'skills_cast', by: 1 }],
  quest_completed: [{ key: 'quests_completed', by: 1 }],
  chat_sent: [{ key: 'chat_messages', by: 1 }],
  npc_talked: [{ key: 'npcs_talked', by: 1 }],
  level_up: [{ key: 'level', set: (ev) => Math.max(1, ev.amount ?? 1) }],
  trade_completed: [{ key: 'trades_completed', by: 1 }],
  // party_joined / guild_joined / zone_visited carry no counter — they are
  // consumed via instant triggers and the visitedZones set respectively.
};

// ---------------------------------------------------------------------------
// Engine state + evaluation
// ---------------------------------------------------------------------------

/** Mutable engine state; the App layer clones it into React state. */
export interface AchievementEngineState {
  /** id -> unlock timestamp (0 for migrated unlocks with unknown time). */
  unlocked: Record<string, number>;
  counters: AchievementCounters;
  /** Distinct zone ids credited (zones_visited counts these). */
  visitedZones: string[];
}

export function createEngineState(): AchievementEngineState {
  return {
    unlocked: {},
    counters: emptyCounters(),
    visitedZones: [],
  };
}

/** Migration map: pre-.tres client ids -> canonical ids. */
const LEGACY_ID_MAP: Record<string, string> = {
  ach_first_blood: 'first_blood',
  ach_realm_traveler: 'explorer',
};

/**
 * Carry unlocked ids from a legacy save (boolean list, old ids) into the
 * engine state so the Hall of Valor history survives the upgrade.
 */
export function migrateLegacyUnlocks(unlockedIds: string[], state: AchievementEngineState): void {
  for (const id of unlockedIds) {
    const canonical = LEGACY_ID_MAP[id] ?? id;
    if (!state.unlocked[canonical]) {
      state.unlocked[canonical] = 0; // 0 = migrated, timestamp unknown
    }
  }
}

export interface EngineResult {
  state: AchievementEngineState;
  /** Achievements unlocked by this event, in evaluation order. */
  newlyUnlocked: AchievementUnlock[];
  /** Aggregated rewards to grant the player (0 when nothing unlocked). */
  rewards: { gold: number; xp: number };
}

/**
 * Apply a game event to the engine state and evaluate unlocks.
 * Onboarding steps gate on the previous step being unlocked.
 */
export function applyEvent(
  state: AchievementEngineState,
  event: AchievementEvent,
  now: number = Date.now()
): EngineResult {
  const result: EngineResult = {
    state,
    newlyUnlocked: [],
    rewards: { gold: 0, xp: 0 },
  };

  // 1. Counter increments
  const updates = EVENT_COUNTERS[event.type];
  if (updates) {
    for (const upd of updates) {
      if (upd.cond && !upd.cond(event)) continue;
      if (upd.set) {
        state.counters[upd.key] = Math.max(state.counters[upd.key] ?? 0, upd.set(event));
      } else {
        const delta = typeof upd.by === 'function' ? upd.by(event) : upd.by ?? 1;
        state.counters[upd.key] = (state.counters[upd.key] ?? 0) + delta;
      }
    }
  }

  // 2. Distinct-zone bookkeeping (zones_visited counts unique zones)
  if (event.type === 'zone_visited' && event.targetId && !state.visitedZones.includes(event.targetId)) {
    state.visitedZones.push(event.targetId);
    state.counters.zones_visited = state.visitedZones.length;
  }

  // 3. Unlock evaluation
  for (const def of getCatalog()) {
    if (state.unlocked[def.id]) continue;

    // Onboarding gating: step N needs step N-1 unlocked
    if (def.chain === 'onboarding' && (def.chainStep ?? 1) > 1) {
      const prev = getOnboardingChain()[(def.chainStep ?? 1) - 2];
      if (prev && !state.unlocked[prev.id]) continue;
    }

    let hit = false;
    if (def.trigger === 'counter' && def.counter && def.target != null) {
      hit = (state.counters[def.counter] ?? 0) >= def.target;
    } else if (def.trigger === 'instant') {
      hit = def.instantOn?.includes(event.type) ?? false;
    } else if (def.trigger === 'first_session') {
      hit = event.type === 'session_started';
    }

    if (hit) {
      state.unlocked[def.id] = now;
      result.newlyUnlocked.push({ def, unlockedAt: now });
      result.rewards.gold += def.goldReward;
      result.rewards.xp += def.xpReward;
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Progress helpers (read-only, for UI)
// ---------------------------------------------------------------------------

export interface AchievementProgressInfo {
  current: number;
  target: number;
  pct: number;
}

export function getAchievementProgress(
  def: AchievementDef,
  state: AchievementEngineState
): AchievementProgressInfo {
  const isDone = Boolean(state.unlocked[def.id]);
  const current = isDone
    ? def.target ?? 1
    : def.counter && def.target != null
      ? Math.min(state.counters[def.counter] ?? 0, def.target)
      : 0;
  const target = def.target ?? 1;
  return {
    current,
    target,
    pct: target > 0 ? Math.min(100, (current / target) * 100) : 0,
  };
}

export function getChainProgress(state: AchievementEngineState): {
  completed: number;
  total: number;
  next?: AchievementDef;
} {
  const chain = getOnboardingChain();
  const completed = chain.filter((d) => state.unlocked[d.id]).length;
  const next = chain.find((d) => !state.unlocked[d.id]);
  return { completed, total: chain.length, next };
}

/**
 * Sync engine state onto the persisted AchievementProgress blob saved with
 * the character (keeps the old fields the Hall of Valor already reads).
 */
export function toPersistedProgress(state: AchievementEngineState): AchievementProgress {
  return {
    unlocked: { ...state.unlocked },
    counters: { ...state.counters },
    visitedZones: [...state.visitedZones],
  };
}
