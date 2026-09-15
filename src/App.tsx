import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  PlayerCharacter,
  Enemy,
  NPC,
  Zone,
  ZoneId,
  ZoneSpawn,
  Skill,
  Item,
  EquipSlot,
  CombatText,
  ChatMessage,
  SpeciesId,
  ClassId,
} from './types';
import {
  ZONES_DATA,
  SPECIES_DATA,
  CLASS_DATA,
  QUESTS_DATA,
  INITIAL_SKILLS,
} from './gameData';
import { soundEngine } from './soundEngine';
import { synmergiaBridge } from './services/bridgeClient';
import { gameWebSocket, type WSMessage } from './services/gameWebSocket';

// Components
import { GameCanvas } from './components/GameCanvas';
import { HUD } from './components/HUD';
import { CharacterSelectModal } from './components/CharacterSelectModal';
import { CharacterSheetModal } from './components/CharacterSheetModal';
import { InventoryModal } from './components/InventoryModal';
import { QuestModal } from './components/QuestModal';
import { ShopModal } from './components/ShopModal';
import { BlacksmithModal } from './components/BlacksmithModal';
import { WorldMapModal } from './components/WorldMapModal';
import { ChatBox } from './components/ChatBox';
import { AchievementsModal } from './components/AchievementsModal';
import { VirtualJoystick } from './components/VirtualJoystick';
import { PortalHeader, PortalMode } from './components/PortalHeader';
import { GodotClientView } from './components/wasm/GodotClientView';
import { AdminDashboardView } from './components/admin/AdminDashboardView';

const SAVE_KEY = 'synmergia_save_v1';
const TELEMETRY_POLL_INTERVAL_MS = 5_000;
const TELEMETRY_FALLBACK_STALE_MS = 15_000;
const MAX_TICK_RATE_SAMPLES = 20;
const ONLINE_PLAYER_COUNT_KEYS = [
  'activePlayerCount',
  'active_player_count',
  'onlinePlayerCount',
  'online_player_count',
  'playerCount',
  'player_count',
  'connectedPlayerCount',
  'connected_player_count',
] as const;
const SERVER_TICK_RATE_KEYS = [
  'serverTickRate',
  'server_tick_rate',
  'tickRate',
  'tick_rate',
  'serverTickRateHz',
  'server_tick_rate_hz',
] as const;
const ONLINE_PLAYER_COUNT_QUERY =
  "SELECT COUNT(*) FROM characters WHERE last_online > NOW() - INTERVAL '5 minutes'";

type TelemetryRecord = Record<string, unknown>;
type TelemetryRow = {
  active_player_count?: unknown;
  online_player_count?: unknown;
  count?: unknown;
};

const readNumeric = (value: unknown): number | null => {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
    return value;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const parsed = Number(trimmed);
    if (Number.isFinite(parsed) && parsed >= 0) return parsed;
    try {
      return readNumeric(JSON.parse(trimmed));
    } catch {
      return null;
    }
  }
  return null;
};

const readCountValue = (value: unknown): number | null => {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed) {
      try {
        const parsed = JSON.parse(trimmed);
        if (parsed !== trimmed) {
          const parsedCount = readCountValue(parsed);
          if (parsedCount !== null) return parsedCount;
        }
      } catch {
        return null;
      }
    }
  }

  const numeric = readNumeric(value);
  if (numeric !== null) return Math.floor(numeric);
  if (Array.isArray(value)) return value.length;
  if (value && typeof value === 'object') {
    const record = value as TelemetryRecord;
    const nested =
      readNumeric(record.activePlayerCount) ??
      readNumeric(record.active_player_count) ??
      readNumeric(record.onlinePlayerCount) ??
      readNumeric(record.online_player_count) ??
      readNumeric(record.playerCount) ??
      readNumeric(record.player_count) ??
      readNumeric(record.count) ??
      readNumeric(record.total) ??
      readNumeric(record.size) ??
      readNumeric(record.value);
    return nested === null ? Object.keys(record).length : Math.floor(nested);
  }
  return null;
};

const readNumericField = (payload: unknown, keys: readonly string[]): number | null => {
  if (!payload || typeof payload !== 'object') return null;
  const record = payload as TelemetryRecord;
  for (const key of keys) {
    const value = readNumeric(record[key]);
    if (value !== null) return value;
  }
  return null;
};

const readPlayerCount = (payload: unknown): number | null => {
  const explicit = readNumericField(payload, ONLINE_PLAYER_COUNT_KEYS);
  if (explicit !== null) return Math.floor(explicit);
  if (!payload || typeof payload !== 'object') return null;
  const record = payload as TelemetryRecord;
  const onlinePlayers = record.online_players ?? record.onlinePlayers;
  const count = readCountValue(onlinePlayers);
  return count === null ? null : Math.floor(count);
};

const readTickRate = (payload: unknown): number | null => {
  const value = readNumericField(payload, SERVER_TICK_RATE_KEYS);
  return value !== null && value > 0 ? value : null;
};

const readEntityPlayerCount = (payload: unknown): number | null => {
  if (!payload || typeof payload !== 'object') return null;
  const entities = (payload as TelemetryRecord).entities;
  if (!Array.isArray(entities)) return null;

  const playerIds = new Set<string>();
  let foundPlayer = false;
  for (const entity of entities) {
    if (!entity || typeof entity !== 'object') continue;
    const record = entity as TelemetryRecord;
    const entityType =
      typeof record.entityType === 'string'
        ? record.entityType
        : typeof record.type === 'string'
          ? record.type
          : '';
    const hasPlayerMarker =
      entityType.toLowerCase() === 'player' ||
      'playerId' in record ||
      'player_id' in record;
    if (!hasPlayerMarker) continue;

    foundPlayer = true;
    const playerId = record.playerId ?? record.player_id ?? record.id;
    playerIds.add(typeof playerId === 'string' && playerId ? playerId : String(playerIds.size));
  }
  return foundPlayer ? playerIds.size : null;
};

const createDefaultCharacter = (): PlayerCharacter => ({
  id: 'player_1',
  name: 'Valerius',
  species: 'human',
  classId: 'warrior',
  level: 1,
  xp: 0,
  maxXp: 100,
  hp: 120,
  maxHp: 120,
  mp: 50,
  maxMp: 50,
  stamina: 100,
  maxStamina: 100,
  gold: 45,
  x: 500,
  y: 400,
  direction: 'down',
  stats: {
    strength: 14,
    agility: 10,
    intelligence: 8,
    vitality: 12,
    endurance: 11,
    wisdom: 7,
  },
  equipment: {
    head: null,
    chest: {
      id: 'apprentice_tunic',
      name: 'Leather Brigandine',
      type: 'armor',
      rarity: 'common',
      slot: 'chest',
      description: 'Sturdy boiled leather with bronze rivets.',
      stats: { armor: 6, vitality: 2 },
      value: 15,
      icon: 'Shield',
    },
    main_hand: {
      id: 'iron_broadsword',
      name: 'Forged Steel Blade',
      type: 'weapon',
      rarity: 'uncommon',
      slot: 'main_hand',
      description: 'A well-balanced double-edged steel longsword.',
      stats: { attackPower: 8, strength: 2 },
      value: 25,
      icon: 'Sword',
    },
    off_hand: null,
    accessory: null,
  },
  inventory: [
    {
      id: 'minor_healing_potion',
      name: 'Lesser Healing Draught',
      type: 'consumable',
      rarity: 'common',
      description: 'A crimson tonic distilled from sunberries.',
      healAmount: 50,
      quantity: 4,
      value: 8,
      icon: 'Heart',
    },
    {
      id: 'minor_mana_potion',
      name: 'Lesser Mana Draught',
      type: 'consumable',
      rarity: 'common',
      description: 'Azure essence that replenishes mental focus.',
      manaAmount: 40,
      quantity: 3,
      value: 10,
      icon: 'Zap',
    },
    {
      id: 'iron_ore',
      name: 'Highland Iron Ore',
      type: 'material',
      rarity: 'common',
      description: 'Raw mineral ore harvested from rock crags.',
      quantity: 5,
      value: 4,
      icon: 'Coins',
    },
  ],
  activeQuests: [
    { questId: 'q_plains_trouble', progress: 0 },
    { questId: 'q_wolf_menace', progress: 0 },
  ],
  completedQuests: [],
  activeBuffs: [],
  unlockedAchievements: [],
});

export default function App() {
  const [portalMode, setPortalMode] = useState<PortalMode>('companion');
  const [crossOriginIsolated, setCrossOriginIsolated] = useState<boolean>(false);
  const [activePlayerCount, setActivePlayerCount] = useState<number>(0);
  const [serverTickRate, setServerTickRate] = useState<number>(0);

  const telemetryActiveRef = useRef<boolean>(false);
  const telemetryRequestInFlightRef = useRef<boolean>(false);
  const lastWebSocketCountAtRef = useRef<number>(0);
  const lastWebSocketTickAtRef = useRef<number>(0);
  const lastTickSampleRef = useRef<{ tick: number; timestamp: number } | null>(null);
  const lastEntityUpdateAtRef = useRef<number>(0);
  const tickRateSamplesRef = useRef<number[]>([]);

  useEffect(() => {
    setCrossOriginIsolated(typeof window !== 'undefined' && Boolean(window.crossOriginIsolated));
  }, []);

  // --- Persistent State Initialization ---
  const [player, setPlayer] = useState<PlayerCharacter>(() => {
    try {
      const saved = localStorage.getItem(SAVE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved);
        const defaults = createDefaultCharacter();
        return {
          ...defaults,
          ...parsed,
          activeBuffs: Array.isArray(parsed.activeBuffs) ? parsed.activeBuffs : [],
          inventory: Array.isArray(parsed.inventory) ? parsed.inventory : defaults.inventory,
          activeQuests: Array.isArray(parsed.activeQuests) ? parsed.activeQuests : defaults.activeQuests,
          completedQuests: Array.isArray(parsed.completedQuests) ? parsed.completedQuests : defaults.completedQuests,
          unlockedAchievements: Array.isArray(parsed.unlockedAchievements) ? parsed.unlockedAchievements : defaults.unlockedAchievements,
        };
      }
    } catch {
      // Fallback
    }
    return createDefaultCharacter();
  });

  const [currentZoneId, setCurrentZoneId] = useState<ZoneId>('zone_village_center');
  const currentZone = ZONES_DATA[currentZoneId] || ZONES_DATA['zone_village_center'];

  // Zone Entities
  const [enemies, setEnemies] = useState<Enemy[]>([]);
  const [npcs, setNpcs] = useState<NPC[]>([]);

  // Selection & Targeting
  const [selectedEnemy, setSelectedEnemy] = useState<Enemy | null>(null);
  const [selectedNpc, setSelectedNpc] = useState<NPC | null>(null);

  // Combat Texts & Cast
  const [combatTexts, setCombatTexts] = useState<CombatText[]>([]);
  const [activeSkillCast, setActiveSkillCast] = useState<{ skill: Skill; progress: number } | null>(null);

  // Skill Cooldowns
  const [cooldowns, setCooldowns] = useState<Record<string, number>>({});

  // Audio Mute State
  const [isMuted, setIsMuted] = useState(false);

  // Modals
  const [isCharSelectOpen, setIsCharSelectOpen] = useState(false);
  const [isCharSheetOpen, setIsCharSheetOpen] = useState(false);
  const [isInventoryOpen, setIsInventoryOpen] = useState(false);
  const [isQuestOpen, setIsQuestOpen] = useState(false);
  const [isShopOpen, setIsShopOpen] = useState(false);
  const [isBlacksmithOpen, setIsBlacksmithOpen] = useState(false);
  const [isMapOpen, setIsMapOpen] = useState(false);
  const [isAchievementsOpen, setIsAchievementsOpen] = useState(false);

  // Mobile Touch Joystick
  const [joystickVector, setJoystickVector] = useState<{ x: number; y: number } | null>(null);

  // Chat Messages
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([
    {
      id: '1',
      sender: 'System',
      channel: 'system',
      text: 'Welcome to Synmergia! Move with WASD, Arrow keys, or Click-to-Move.',
      timestamp: new Date().toLocaleTimeString(),
    },
    {
      id: '2',
      sender: 'Elder Garrick',
      channel: 'global',
      text: 'Hail traveler! Approach me in Easthollow to receive your adventurer orders.',
      timestamp: new Date().toLocaleTimeString(),
    },
  ]);

  // Available Skills based on Class
  const classSkills = (INITIAL_SKILLS && (INITIAL_SKILLS[player.classId] || INITIAL_SKILLS['warrior'])) || [];

  // Count Quick Potions
  const quickPotion = (player.inventory || []).find(
    (item) => item?.type === 'consumable' && item?.healAmount
  );
  const potionCount = quickPotion?.quantity || (quickPotion ? 1 : 0);

  // --- Save Game Progress ---
  useEffect(() => {
    try {
      localStorage.setItem(SAVE_KEY, JSON.stringify(player));
    } catch {
      // Ignore quota errors
    }
  }, [player]);

  // --- Load Zone Data ---
  useEffect(() => {
    // Populate zone NPCs
    setNpcs(currentZone.npcs || []);

    // Populate zone Enemies from templates
    const spawns = currentZone.enemySpawns || [];
    const newEnemies: Enemy[] = spawns.map((spawn: ZoneSpawn, idx: number) => ({
      id: `enemy_${currentZone.id}_${idx}_${Date.now()}`,
      templateId: spawn.templateId,
      name: spawn.templateId === 'bandit' ? 'Highway Outlaw' : spawn.templateId === 'wolf' ? 'Dire Wolf' : spawn.templateId === 'slime' ? 'Toxic Slime' : 'Netherlord Malgor',
      level: spawn.level,
      hp: spawn.isBoss ? 450 : spawn.isElite ? 220 : 65 + spawn.level * 15,
      maxHp: spawn.isBoss ? 450 : spawn.isElite ? 220 : 65 + spawn.level * 15,
      attackPower: spawn.isBoss ? 28 : spawn.isElite ? 18 : 8 + spawn.level * 2,
      armor: spawn.isBoss ? 20 : 6,
      x: spawn.x + (Math.random() * 40 - 20),
      y: spawn.y + (Math.random() * 40 - 20),
      spawnX: spawn.x,
      spawnY: spawn.y,
      state: 'patrol',
      patrolRadius: 80,
      aggroRadius: spawn.isBoss ? 240 : 160,
      attackRange: spawn.isBoss ? 55 : 40,
      attackCooldown: 0,
      xpReward: spawn.isBoss ? 160 : spawn.isElite ? 80 : 30 + spawn.level * 8,
      goldReward: spawn.isBoss ? 75 : 10 + Math.floor(Math.random() * 10),
      isBoss: !!spawn.isBoss,
      isElite: !!spawn.isElite,
    }));

    setEnemies(newEnemies);
    setSelectedEnemy(null);
    setSelectedNpc(null);
  }, [currentZone]);

  // --- Add Chat Message ---
  const addChatMessage = useCallback(
    (text: string, channel: 'all' | 'global' | 'system' | 'combat' | 'party' = 'global', sender: string = 'System') => {
      setChatMessages((prev) => [
        ...prev.slice(-60),
        {
          id: `msg_${Date.now()}_${Math.random()}`,
          sender: sender || 'System',
          channel,
          text,
          timestamp: new Date().toLocaleTimeString(),
        },
      ]);
    },
    []
  );

  // --- Add Floating Combat Text ---
  const addCombatText = useCallback(
    (text: string, x: number, y: number, color: string, type: 'damage' | 'heal' | 'crit' | 'xp' = 'damage') => {
      setCombatTexts((prev) => [
        ...prev.slice(-25),
        {
          id: `ct_${Date.now()}_${Math.random()}`,
          text,
          x: x + (Math.random() * 20 - 10),
          y: y - 10,
          color,
          createdAt: Date.now(),
          type,
        },
      ]);
    },
    []
  );

  const applyTelemetryFromMessage = useCallback(
    (payload: unknown, timestamp?: number, estimateInterval = false) => {
      const now = Date.now();
      const playerCount = readPlayerCount(payload) ?? readEntityPlayerCount(payload);
      if (playerCount !== null) {
        setActivePlayerCount(playerCount);
        lastWebSocketCountAtRef.current = now;
      }

      const tickRate = readTickRate(payload);
      if (tickRate !== null) {
        setServerTickRate(Math.round(tickRate));
        lastWebSocketTickAtRef.current = now;
      }

      const tick = readNumericField(payload, ['tick', 'serverTick', 'server_tick']);
      const sampleTimestamp =
        typeof timestamp === 'number' && timestamp > 0 ? timestamp : now;
      if (tick !== null) {
        const previous = lastTickSampleRef.current;
        if (
          previous &&
          sampleTimestamp > previous.timestamp &&
          tick > previous.tick
        ) {
          const elapsedMs = sampleTimestamp - previous.timestamp;
          const observedTickRate = ((tick - previous.tick) * 1000) / elapsedMs;
          if (observedTickRate >= 1 && observedTickRate <= 240) {
            tickRateSamplesRef.current.push(observedTickRate);
            if (tickRateSamplesRef.current.length > MAX_TICK_RATE_SAMPLES) {
              tickRateSamplesRef.current.shift();
            }
            const averageTickRate =
              tickRateSamplesRef.current.reduce((sum, sample) => sum + sample, 0) /
              tickRateSamplesRef.current.length;
            setServerTickRate(Math.max(1, Math.round(averageTickRate)));
          }
        }
        lastTickSampleRef.current = { tick, timestamp: sampleTimestamp };
      } else if (estimateInterval) {
        const previous = lastEntityUpdateAtRef.current;
        if (previous && sampleTimestamp > previous) {
          const elapsedMs = sampleTimestamp - previous;
          const observedTickRate = 1000 / elapsedMs;
          if (observedTickRate >= 1 && observedTickRate <= 240) {
            tickRateSamplesRef.current.push(observedTickRate);
            if (tickRateSamplesRef.current.length > MAX_TICK_RATE_SAMPLES) {
              tickRateSamplesRef.current.shift();
            }
            const averageTickRate =
              tickRateSamplesRef.current.reduce((sum, sample) => sum + sample, 0) /
              tickRateSamplesRef.current.length;
            setServerTickRate(Math.max(1, Math.round(averageTickRate)));
          }
        }
        lastEntityUpdateAtRef.current = sampleTimestamp;
      }
    },
    []
  );

  const refreshTelemetry = useCallback(async () => {
    if (!telemetryActiveRef.current || telemetryRequestInFlightRef.current) return;
    telemetryRequestInFlightRef.current = true;

    try {
      const [cachedCount, cachedPlayers, cachedTickRate, cachedTick, onlinePeers] =
        await Promise.all([
          synmergiaBridge.getCache('online_player_count'),
          synmergiaBridge.getCache('online_players'),
          synmergiaBridge.getCache('server_tick_rate'),
          synmergiaBridge.getCache('tick_rate'),
          synmergiaBridge.getHashAll('online:peers'),
        ]);
      const now = Date.now();
      const hasRedisCount =
        cachedCount != null ||
        cachedPlayers != null ||
        Object.keys(onlinePeers ?? {}).length > 0;
      const bridgePlayerCount =
        readCountValue(cachedCount) ??
        readCountValue(cachedPlayers) ??
        readCountValue(onlinePeers);
      const shouldRefreshCount =
        lastWebSocketCountAtRef.current === 0 ||
        now - lastWebSocketCountAtRef.current > TELEMETRY_FALLBACK_STALE_MS;
      if (
        telemetryActiveRef.current &&
        shouldRefreshCount &&
        bridgePlayerCount !== null
      ) {
        setActivePlayerCount(bridgePlayerCount);
      }

      const bridgeTickRate =
        readTickRate(cachedTickRate) ?? readTickRate(cachedTick);
      const shouldRefreshTickRate =
        lastWebSocketTickAtRef.current === 0 ||
        now - lastWebSocketTickAtRef.current > TELEMETRY_FALLBACK_STALE_MS;
      if (
        telemetryActiveRef.current &&
        shouldRefreshTickRate &&
        bridgeTickRate !== null
      ) {
        setServerTickRate(Math.round(bridgeTickRate));
      }

      if (!hasRedisCount) {
        const result = await synmergiaBridge.query<TelemetryRow>(
          ONLINE_PLAYER_COUNT_QUERY
        );
        const row = result.ok ? result.rows?.[0] : undefined;
        const playerCount = row ? readCountValue(row) : null;
        const isCountStillStale =
          lastWebSocketCountAtRef.current === 0 ||
          Date.now() - lastWebSocketCountAtRef.current > TELEMETRY_FALLBACK_STALE_MS;
        if (
          telemetryActiveRef.current &&
          isCountStillStale &&
          playerCount !== null
        ) {
          setActivePlayerCount(playerCount);
        }
      }
    } finally {
      telemetryRequestInFlightRef.current = false;
    }
  }, []);

  useEffect(() => {
    telemetryActiveRef.current = true;
    void refreshTelemetry();
    const interval = window.setInterval(() => {
      void refreshTelemetry();
    }, TELEMETRY_POLL_INTERVAL_MS);

    return () => {
      telemetryActiveRef.current = false;
      window.clearInterval(interval);
    };
  }, [refreshTelemetry]);

  // --- Real-time WebSocket sync (companion mode) ---
  useEffect(() => {
    if (portalMode !== 'companion') return;

    let cancelled = false;

    gameWebSocket.onOpen(() => {
      gameWebSocket.send('auth', { token: 'dev', playerId: player.id });
      void refreshTelemetry();
    });

    const unsubscribePlayerState = gameWebSocket.on('player_state', (msg: WSMessage) => {
      if (cancelled) return;
      applyTelemetryFromMessage(msg.payload, msg.timestamp);
      const p = msg.payload as {
        x: number;
        y: number;
        hp: number;
        mp: number;
        stamina: number;
        zone: string;
      };
      if (!p) return;
      setPlayer((prev) => ({
        ...prev,
        x: p.x ?? prev.x,
        y: p.y ?? prev.y,
        hp: p.hp ?? prev.hp,
        mp: p.mp ?? prev.mp,
        stamina: p.stamina ?? prev.stamina,
      }));
      if (p.zone && p.zone !== currentZoneId) {
        setCurrentZoneId(p.zone as ZoneId);
      }
    });

    const unsubscribeEntityUpdate = gameWebSocket.on('entity_update', (msg: WSMessage) => {
      if (cancelled) return;
      const payload = msg.payload as { entities?: unknown[] };
      applyTelemetryFromMessage(msg.payload, msg.timestamp, true);
      if (!payload?.entities) return;
    });

    const unsubscribeCombatEvent = gameWebSocket.on('combat_event', (msg: WSMessage) => {
      const ev = msg.payload as { type: string; amount?: number; targetId?: string };
      if (cancelled || !ev) return;
      if (ev.type === 'damage' && typeof ev.amount === 'number') {
        addCombatText(String(ev.amount), player.x, player.y, '#ef4444', 'damage');
      } else if (ev.type === 'heal' && typeof ev.amount === 'number') {
        addCombatText(`+${ev.amount}`, player.x, player.y, '#22c55e', 'heal');
      }
    });

    const unsubscribeChat = gameWebSocket.on('chat', (msg: WSMessage) => {
      const c = msg.payload as { channel?: string; sender?: string; text?: string };
      if (cancelled || !c?.text) return;
      addChatMessage(c.text, (c.channel as any) || 'global', c.sender || 'Server');
    });

    const unsubscribeZoneChange = gameWebSocket.on('zone_change', (msg: WSMessage) => {
      const z = msg.payload as { zoneId?: string; x?: number; y?: number };
      if (cancelled || !z?.zoneId) return;
      setCurrentZoneId(z.zoneId as ZoneId);
      setPlayer((prev) => ({
        ...prev,
        x: z.x ?? prev.x,
        y: z.y ?? prev.y,
      }));
    });

    const unsubscribePong = gameWebSocket.on('pong', (msg: WSMessage) => {
      if (!cancelled) applyTelemetryFromMessage(msg.payload, msg.timestamp);
    });

    gameWebSocket.connect().catch(() => {
      // Offline fallback: local-only play continues.
    });

    return () => {
      cancelled = true;
      unsubscribePlayerState();
      unsubscribeEntityUpdate();
      unsubscribeCombatEvent();
      unsubscribeChat();
      unsubscribeZoneChange();
      unsubscribePong();
      gameWebSocket.disconnect();
    };
  }, [
    portalMode,
    player.id,
    currentZoneId,
    addChatMessage,
    addCombatText,
    applyTelemetryFromMessage,
    refreshTelemetry,
  ]);

  // --- Award Quest Progress ---
  const trackQuestKill = useCallback(
    (templateId: string, isBoss?: boolean) => {
      setPlayer((prev) => {
        let updated = false;
        const newQuests = prev.activeQuests.map((aq) => {
          const questDef = QUESTS_DATA[aq.questId];
          if (!questDef || questDef.targetType !== 'kill') return aq;

          // Check target match
          const match =
            (questDef.targetName.toLowerCase().includes('bandit') && templateId === 'bandit') ||
            (questDef.targetName.toLowerCase().includes('wolf') && templateId === 'wolf') ||
            (questDef.targetName.toLowerCase().includes('netherlord') && isBoss);

          if (match && aq.progress < questDef.requiredCount) {
            updated = true;
            const newProg = aq.progress + 1;
            addChatMessage(
              `Quest Progress: ${questDef.title} (${newProg}/${questDef.requiredCount})`,
              'system'
            );
            if (newProg === questDef.requiredCount) {
              soundEngine.playQuestComplete();
              addChatMessage(
                `Quest Objective Complete: ${questDef.title}! Speak to the quest giver.`,
                'system'
              );
            }
            return { ...aq, progress: newProg };
          }
          return aq;
        });

        if (!updated) return prev;
        return { ...prev, activeQuests: newQuests };
      });
    },
    [addChatMessage]
  );

  // --- Check Achievements ---
  const checkAchievement = useCallback(
    (achId: string, title: string) => {
      setPlayer((prev) => {
        if (prev.unlockedAchievements.includes(achId)) return prev;
        soundEngine.playLevelUp();
        addChatMessage(
          `Achievement Unlocked: "${title}"! Check your Hall of Valor [H].`,
          'system'
        );
        return {
          ...prev,
          unlockedAchievements: [...prev.unlockedAchievements, achId],
        };
      });
    },
    [addChatMessage]
  );

  // --- Award XP & Handle Level Up ---
  const awardExperience = useCallback(
    (xpAmount: number) => {
      setPlayer((prev) => {
        let newXp = prev.xp + xpAmount;
        let newLevel = prev.level;
        let newMaxXp = prev.maxXp;
        let leveledUp = false;

        while (newXp >= newMaxXp) {
          newXp -= newMaxXp;
          newLevel += 1;
          newMaxXp = Math.floor(newMaxXp * 1.4);
          leveledUp = true;
        }

        if (leveledUp) {
          soundEngine.playLevelUp();
          addChatMessage(
            `DING! You achieved Level ${newLevel}! Your health and resources are restored!`,
            'system'
          );
          addCombatText(`LEVEL UP! (Lv.${newLevel})`, prev.x, prev.y - 30, '#facc15', 'crit');
          return {
            ...prev,
            level: newLevel,
            xp: newXp,
            maxXp: newMaxXp,
            maxHp: prev.maxHp + 25,
            hp: prev.maxHp + 25,
            maxMp: prev.maxMp + 15,
            mp: prev.maxMp + 15,
            stats: {
              ...prev.stats,
              strength: prev.stats.strength + 2,
              vitality: prev.stats.vitality + 2,
              agility: prev.stats.agility + 1,
              intelligence: prev.stats.intelligence + 1,
            },
          };
        }

        return { ...prev, xp: newXp };
      });
    },
    [addChatMessage, addCombatText]
  );

  // --- Main Real-time Simulation Engine Tick (every 100ms) ---
  useEffect(() => {
    const simulationInterval = setInterval(() => {
      const dt = 0.1; // 100ms

      // 1. Skill Cooldown Tick
      setCooldowns((prev) => {
        const next: Record<string, number> = {};
        let changed = false;
        Object.entries(prev).forEach(([key, val]) => {
          if (val > 0) {
            next[key] = Math.max(0, val - dt);
            changed = true;
          }
        });
        return changed ? next : prev;
      });

      // 2. Active Buffs Timer & Passive Regeneration
      setPlayer((prev) => {
        let changed = false;
        let newBuffs = prev.activeBuffs
          .map((b) => ({ ...b, duration: b.duration - dt }))
          .filter((b) => b.duration > 0);

        if (newBuffs.length !== prev.activeBuffs.length) {
          changed = true;
        }

        // Natural out-of-combat regeneration
        let newHp = prev.hp;
        let newMp = prev.mp;
        let newStamina = prev.stamina;

        if (newHp < prev.maxHp) {
          newHp = Math.min(prev.maxHp, newHp + 0.8 * dt);
          changed = true;
        }
        if (newMp < prev.maxMp) {
          newMp = Math.min(prev.maxMp, newMp + 1.2 * dt);
          changed = true;
        }
        if (newStamina < prev.maxStamina) {
          newStamina = Math.min(prev.maxStamina, newStamina + 4.0 * dt);
          changed = true;
        }

        if (changed) {
          return {
            ...prev,
            hp: newHp,
            mp: newMp,
            stamina: newStamina,
            activeBuffs: newBuffs,
          };
        }
        return prev;
      });

      // 3. Enemy AI & Combat Engine
      setEnemies((prevEnemies) => {
        return prevEnemies.map((enemy) => {
          if (enemy.hp <= 0) return enemy;

          const distToPlayer = Math.hypot(player.x - enemy.x, player.y - enemy.y);
          let newEnemy = { ...enemy };

          // Cooldown tick
          if (newEnemy.attackCooldown > 0) {
            newEnemy.attackCooldown = Math.max(0, newEnemy.attackCooldown - dt);
          }

          // Aggro check (unless safe zone)
          const canAggro = currentZone.pvpMode !== 'safe';

          if (canAggro && distToPlayer <= enemy.aggroRadius) {
            // Chase or Attack
            if (distToPlayer <= enemy.attackRange) {
              newEnemy.state = 'attack';
              // Perform Attack if cooldown is 0
              if (newEnemy.attackCooldown <= 0 && player.hp > 0) {
                newEnemy.attackCooldown = 1.8;
                soundEngine.playHitImpact();

                // Compute enemy damage vs player armor
                const rawDamage = newEnemy.attackPower;
                const playerArmor = Math.round(player.stats.endurance * 1.2);
                const actualDamage = Math.max(3, Math.round(rawDamage - playerArmor * 0.3));

                addCombatText(`-${actualDamage}`, player.x, player.y, '#ef4444', 'damage');
                addChatMessage(
                  `${newEnemy.name} hits you for ${actualDamage} physical damage!`,
                  'combat'
                );

                setPlayer((p) => {
                  const remainingHp = Math.max(0, p.hp - actualDamage);
                  if (remainingHp === 0 && p.hp > 0) {
                    // Player Death Handling & Respawn
                    soundEngine.playHitImpact();
                    addChatMessage(
                      'You have fallen in battle! The spirits guide your essence back to Easthollow Village.',
                      'system'
                    );
                    setTimeout(() => {
                      setCurrentZoneId('zone_village_center');
                      setPlayer((deadPlayer) => ({
                        ...deadPlayer,
                        x: 500,
                        y: 400,
                        hp: deadPlayer.maxHp,
                        mp: deadPlayer.maxMp,
                      }));
                    }, 1200);
                  }
                  return { ...p, hp: remainingHp };
                });
              }
            } else {
              // Move towards player
              newEnemy.state = 'chase';
              const speed = 2.0;
              const angle = Math.atan2(player.y - enemy.y, player.x - enemy.x);
              newEnemy.x += Math.cos(angle) * speed;
              newEnemy.y += Math.sin(angle) * speed;
            }
          } else {
            // Return to patrol spawn
            const distToSpawn = Math.hypot(enemy.spawnX - enemy.x, enemy.spawnY - enemy.y);
            if (distToSpawn > 10) {
              newEnemy.state = 'patrol';
              const speed = 1.0;
              const angle = Math.atan2(enemy.spawnY - enemy.y, enemy.spawnX - enemy.x);
              newEnemy.x += Math.cos(angle) * speed;
              newEnemy.y += Math.sin(angle) * speed;
            }
          }

          return newEnemy;
        });
      });

      // 4. Gateway portal proximity check
      for (const gw of currentZone.gateways) {
        const dist = Math.hypot(player.x - gw.x, player.y - gw.y);
        if (dist < 32) {
          soundEngine.playSpellCast();
          setCurrentZoneId(gw.targetZoneId);
          setPlayer((p) => ({
            ...p,
            x: gw.targetX,
            y: gw.targetY,
          }));
          addChatMessage(`You entered the portal to ${gw.name}.`, 'system');
          break;
        }
      }
    }, 100);

    return () => clearInterval(simulationInterval);
  }, [player, currentZone, addCombatText, addChatMessage]);

  // --- Keyboard Shortcuts ---
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        document.activeElement?.tagName === 'INPUT' ||
        document.activeElement?.tagName === 'TEXTAREA'
      ) {
        return;
      }

      const key = e.key.toLowerCase();

      // Hotkeys 1-6 for skills
      const slotNumber = parseInt(key, 10);
      if (slotNumber >= 1 && slotNumber <= classSkills.length) {
        handleUseSkill(classSkills[slotNumber - 1]);
        return;
      }

      // Quick potion on 7
      if (key === '7') {
        handleUsePotion();
        return;
      }

      // Menu Shortcuts
      if (key === 'c') setIsCharSheetOpen((prev) => !prev);
      if (key === 'b') setIsInventoryOpen((prev) => !prev);
      if (key === 'l') setIsQuestOpen((prev) => !prev);
      if (key === 'm') setIsMapOpen((prev) => !prev);
      if (key === 'h') setIsAchievementsOpen((prev) => !prev);

      // Escape to close open dialogs or deselect
      if (key === 'escape') {
        setIsCharSheetOpen(false);
        setIsInventoryOpen(false);
        setIsQuestOpen(false);
        setIsShopOpen(false);
        setIsBlacksmithOpen(false);
        setIsMapOpen(false);
        setIsAchievementsOpen(false);
        setSelectedEnemy(null);
        setSelectedNpc(null);
      }

      // Tab to target nearest enemy
      if (key === 'tab') {
        e.preventDefault();
        const aliveEnemies = enemies.filter((en) => en.hp > 0);
        if (aliveEnemies.length > 0) {
          aliveEnemies.sort(
            (a, b) =>
              Math.hypot(a.x - player.x, a.y - player.y) -
              Math.hypot(b.x - player.x, b.y - player.y)
          );
          setSelectedEnemy(aliveEnemies[0]);
          setSelectedNpc(null);
          soundEngine.playHitImpact();
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });

  // --- Player Click Move Handler ---
  const handlePlayerMove = useCallback(
    (targetX: number, targetY: number) => {
      setPlayer((prev) => {
        const clampedX = Math.max(20, Math.min(currentZone.width - 20, targetX));
        const clampedY = Math.max(20, Math.min(currentZone.height - 20, targetY));
        return {
          ...prev,
          x: clampedX,
          y: clampedY,
        };
      });
    },
    [currentZone]
  );

  // --- Execute Skill in Combat ---
  const handleUseSkill = useCallback(
    (skill: Skill) => {
      // Check cooldown
      if (cooldowns[skill.id] && cooldowns[skill.id] > 0) return;

      // Check costs
      if (player.mp < skill.manaCost || player.stamina < skill.staminaCost) {
        addChatMessage('Insufficient Mana or Stamina!', 'system');
        return;
      }

      const skillType = skill.type || skill.effectType;

      // 1. Self buffs or heals
      if (skillType === 'heal' || skillType === 'buff') {
        soundEngine.playHeal();
        setCooldowns((cd) => ({ ...cd, [skill.id]: skill.cooldown }));

        setPlayer((prev) => {
          let healedHp = prev.hp;
          if (skill.healAmount) {
            healedHp = Math.min(prev.maxHp, prev.hp + skill.healAmount);
            addCombatText(`+${skill.healAmount} HP`, prev.x, prev.y, '#22c55e', 'heal');
          }

          let newBuffs = [...prev.activeBuffs];
          if (skill.buffEffect) {
            newBuffs.push({
              id: `${skill.id}_${Date.now()}`,
              name: skill.name,
              stat: skill.buffEffect.stat,
              value: skill.buffEffect.value,
              duration: skill.buffEffect.duration,
            });
          }

          return {
            ...prev,
            hp: healedHp,
            mp: prev.mp - skill.manaCost,
            stamina: prev.stamina - skill.staminaCost,
            activeBuffs: newBuffs,
          };
        });

        addChatMessage(`You cast ${skill.name}!`, 'combat');
        return;
      }

      // 2. Offensive skills require target (or auto-targets closest)
      let target = selectedEnemy;
      if (!target || target.hp <= 0) {
        const alive = enemies.filter((en) => en.hp > 0);
        if (alive.length > 0) {
          alive.sort(
            (a, b) =>
              Math.hypot(a.x - player.x, a.y - player.y) -
              Math.hypot(b.x - player.x, b.y - player.y)
          );
          target = alive[0];
          setSelectedEnemy(target);
        }
      }

      if (!target || target.hp <= 0) {
        addChatMessage('No enemy target in range!', 'system');
        return;
      }

      const dist = Math.hypot(target.x - player.x, target.y - player.y);
      if (dist > skill.range) {
        addChatMessage(`Target is too far away (${Math.round(dist)} > ${skill.range})!`, 'system');
        return;
      }

      // Play Sound
      if (skillType === 'spell' || skill.manaCost > 0) {
        soundEngine.playSpellCast();
      } else {
        soundEngine.playSwordSlash();
      }

      // Deduct resource & start cooldown
      setCooldowns((cd) => ({ ...cd, [skill.id]: skill.cooldown }));
      setPlayer((prev) => ({
        ...prev,
        mp: prev.mp - skill.manaCost,
        stamina: prev.stamina - skill.staminaCost,
      }));

      // Calculate Damage
      const isCrit = Math.random() < 0.22;
      const baseDamage = skill.damage || (skill.damageMultiplier ? Math.round(skill.damageMultiplier * 18) : 18);
      const bonusDamage =
        skillType === 'spell' || skill.manaCost > 0
          ? Math.round(player.stats.intelligence * 1.4)
          : Math.round(player.stats.strength * 1.5 + player.stats.agility * 0.5);

      let finalDamage = Math.max(
        1,
        Math.round((baseDamage + bonusDamage) * (isCrit ? 1.8 : 1.0) - target.armor * 0.4)
      );

      addCombatText(
        isCrit ? `CRIT! -${finalDamage}` : `-${finalDamage}`,
        target.x,
        target.y,
        isCrit ? '#facc15' : '#f87171',
        isCrit ? 'crit' : 'damage'
      );

      addChatMessage(
        `You hit ${target.name} with ${skill.name} for ${finalDamage} damage!`,
        'combat'
      );

      // Apply damage to target
      setEnemies((prev) =>
        prev.map((en) => {
          if (en.id !== target!.id) return en;
          const nextHp = Math.max(0, en.hp - finalDamage);

          if (nextHp === 0 && en.hp > 0) {
            // Defeated Enemy
            soundEngine.playCoins();
            addChatMessage(
              `You vanquished ${en.name}! Earned ${en.xpReward} XP and ${en.goldReward} Gold.`,
              'system'
            );
            addCombatText(`+${en.xpReward} XP`, player.x, player.y - 15, '#38bdf8', 'xp');

            // Check Achievements
            checkAchievement('ach_first_blood', 'First Blood');
            if (en.templateId === 'bandit') {
              checkAchievement('ach_bandit_scourge', 'Scourge of the Outlaws');
            }
            if (en.isBoss) {
              checkAchievement('ach_boss_slayer', 'Conqueror of the Depths');
            }

            // Award XP & Gold
            awardExperience(en.xpReward);
            setPlayer((p) => ({
              ...p,
              gold: p.gold + en.goldReward,
            }));

            // Track quest
            trackQuestKill(en.templateId, en.isBoss);

            // Respawn after 12s
            setTimeout(() => {
              setEnemies((live) =>
                live.map((r) =>
                  r.id === en.id
                    ? {
                        ...r,
                        hp: r.maxHp,
                        x: r.spawnX,
                        y: r.spawnY,
                        state: 'patrol' as const,
                      }
                    : r
                )
              );
            }, 12000);
          }

          return { ...en, hp: nextHp };
        })
      );
    },
    [
      cooldowns,
      player,
      selectedEnemy,
      enemies,
      addChatMessage,
      addCombatText,
      checkAchievement,
      awardExperience,
      trackQuestKill,
    ]
  );

  // --- Quick Potion Drink ---
  const handleUsePotion = useCallback(() => {
    const potionIdx = player.inventory.findIndex(
      (item) => item?.type === 'consumable' && item.healAmount
    );
    if (potionIdx === -1) {
      addChatMessage('You have no healing potions remaining!', 'system');
      return;
    }

    const potion = player.inventory[potionIdx]!;
    soundEngine.playHeal();

    setPlayer((prev) => {
      const heal = potion.healAmount || 50;
      const newHp = Math.min(prev.maxHp, prev.hp + heal);
      addCombatText(`+${heal} HP`, prev.x, prev.y, '#22c55e', 'heal');
      addChatMessage(`You drank ${potion.name} and recovered ${heal} HP.`, 'combat');

      const newInv = [...prev.inventory];
      if (potion.quantity && potion.quantity > 1) {
        newInv[potionIdx] = { ...potion, quantity: potion.quantity - 1 };
      } else {
        newInv.splice(potionIdx, 1);
      }

      return {
        ...prev,
        hp: newHp,
        inventory: newInv,
      };
    });
  }, [player.inventory, addChatMessage, addCombatText]);

  // --- Inventory Actions ---
  const handleEquipItem = (item: Item, slot: EquipSlot) => {
    setPlayer((prev) => {
      const oldEquip = prev.equipment[slot];
      const newInv = prev.inventory.filter((i) => i?.id !== item.id);
      if (oldEquip) {
        newInv.push(oldEquip);
      }
      return {
        ...prev,
        inventory: newInv,
        equipment: {
          ...prev.equipment,
          [slot]: item,
        },
      };
    });
    addChatMessage(`Equipped ${item.name}.`, 'system');
  };

  const handleUnequipItem = (slot: EquipSlot) => {
    const item = player.equipment[slot];
    if (!item) return;

    setPlayer((prev) => ({
      ...prev,
      inventory: [...prev.inventory, item],
      equipment: {
        ...prev.equipment,
        [slot]: null,
      },
    }));
    addChatMessage(`Unequipped ${item.name} to inventory.`, 'system');
  };

  const handleUseInventoryItem = (item: Item) => {
    if (item.healAmount) {
      handleUsePotion();
    } else if (item.manaAmount) {
      soundEngine.playHeal();
      setPlayer((prev) => ({
        ...prev,
        mp: Math.min(prev.maxMp, prev.mp + (item.manaAmount || 30)),
        inventory: prev.inventory.filter((i) => i?.id !== item.id),
      }));
      addChatMessage(`Used ${item.name}, restored ${item.manaAmount} Mana.`, 'combat');
    }
  };

  const handleDropItem = (index: number) => {
    setPlayer((prev) => {
      const newInv = [...prev.inventory];
      const dropped = newInv.splice(index, 1)[0];
      if (dropped) {
        addChatMessage(`Discarded ${dropped.name}.`, 'system');
      }
      return { ...prev, inventory: newInv };
    });
  };

  // --- Shop Actions ---
  const handleBuyShopItem = (item: Item) => {
    if (player.gold < item.value) return;
    setPlayer((prev) => ({
      ...prev,
      gold: prev.gold - item.value,
      inventory: [...prev.inventory, { ...item, id: `${item.id}_${Date.now()}` }],
    }));
    addChatMessage(`Purchased ${item.name} for ${item.value} Gold.`, 'system');
  };

  const handleSellInventoryItem = (index: number) => {
    const item = player.inventory[index];
    if (!item) return;
    const price = Math.max(1, Math.floor(item.value * 0.6));

    setPlayer((prev) => {
      const newInv = [...prev.inventory];
      newInv.splice(index, 1);
      return {
        ...prev,
        gold: prev.gold + price,
        inventory: newInv,
      };
    });
    addChatMessage(`Sold ${item.name} for ${price} Gold.`, 'system');
  };

  // --- Blacksmith Actions ---
  const handleUpgradeWeapon = () => {
    const weapon = player.equipment.main_hand;
    if (!weapon) return;

    // Deduct 2 ore and 30 gold
    setPlayer((prev) => {
      let oresNeeded = 2;
      const newInv = prev.inventory
        .map((it) => {
          if (it?.id === 'iron_ore' && oresNeeded > 0) {
            const count = it.quantity || 1;
            if (count > oresNeeded) {
              const updated = { ...it, quantity: count - oresNeeded };
              oresNeeded = 0;
              return updated;
            } else {
              oresNeeded -= count;
              return null;
            }
          }
          return it;
        })
        .filter(Boolean) as Item[];

      const currentAp = weapon.stats?.attackPower || 10;
      const upgradedWeapon: Item = {
        ...weapon,
        name: weapon.name.includes('+')
          ? weapon.name.replace(/\+\d+/, (m) => `+${parseInt(m.slice(1)) + 1}`)
          : `${weapon.name} +1`,
        stats: {
          ...weapon.stats,
          attackPower: currentAp + 4,
        },
      };

      return {
        ...prev,
        gold: prev.gold - 30,
        inventory: newInv,
        equipment: {
          ...prev.equipment,
          main_hand: upgradedWeapon,
        },
      };
    });

    checkAchievement('ach_master_smith', 'Dwarven Temper');
    addChatMessage(`Torvald tempered your ${weapon.name}! (+4 Attack Power)`, 'system');
  };

  const handleCraftItem = (item: Item, oreCost: number, goldCost: number) => {
    setPlayer((prev) => {
      let remainingOres = oreCost;
      const newInv = prev.inventory
        .map((it) => {
          if (it?.id === 'iron_ore' && remainingOres > 0) {
            const count = it.quantity || 1;
            if (count > remainingOres) {
              const updated = { ...it, quantity: count - remainingOres };
              remainingOres = 0;
              return updated;
            } else {
              remainingOres -= count;
              return null;
            }
          }
          return it;
        })
        .filter(Boolean) as Item[];

      newInv.push({ ...item, id: `${item.id}_${Date.now()}` });

      return {
        ...prev,
        gold: prev.gold - goldCost,
        inventory: newInv,
      };
    });

    checkAchievement('ach_master_smith', 'Dwarven Temper');
    addChatMessage(`Successfully forged ${item.name}!`, 'system');
  };

  // --- Quest Completion Turn-In ---
  const handleCompleteQuest = (questId: string) => {
    const quest = QUESTS_DATA[questId];
    if (!quest) return;

    soundEngine.playQuestComplete();
    awardExperience(quest.rewards.xp);

    setPlayer((prev) => ({
      ...prev,
      gold: prev.gold + quest.rewards.gold,
      activeQuests: prev.activeQuests.filter((q) => q.questId !== questId),
      completedQuests: [...prev.completedQuests, questId],
    }));

    addChatMessage(
      `Turned in quest: "${quest.title}"! Received ${quest.rewards.xp} XP and ${quest.rewards.gold} Gold!`,
      'system'
    );
  };

  // --- Fast Travel / Teleport ---
  const handleTeleportToZone = (zoneId: string) => {
    const targetZone = ZONES_DATA[zoneId as ZoneId];
    if (!targetZone) return;

    setCurrentZoneId(zoneId as ZoneId);
    setPlayer((prev) => ({
      ...prev,
      x: targetZone.width / 2,
      y: targetZone.height / 2,
    }));

    checkAchievement('ach_realm_traveler', 'Wayfarer of the Shards');
    addChatMessage(`Teleported to ${targetZone.name}.`, 'system');
    setIsMapOpen(false);
  };

  // --- NPC Interaction Handler ---
  const handleSelectNpc = (npc: NPC | null) => {
    setSelectedNpc(npc);
    if (!npc) return;

    if (npc.role === 'blacksmith') {
      setIsBlacksmithOpen(true);
      addChatMessage(`${npc.name}: "Need an edge ground or iron forged?"`, 'global');
    } else if (npc.role === 'merchant') {
      setIsShopOpen(true);
      addChatMessage(`${npc.name}: "Welcome! Browse my finest stock of tonics and reagents."`, 'global');
    } else if (npc.role === 'elder') {
      setIsQuestOpen(true);
      addChatMessage(`${npc.name}: "Greetings hero! Synmergia requires your steadfast blade."`, 'global');
    }
  };

  // --- Chat Input & Slash Commands ---
  const handleSendChat = (text: string) => {
    if (text.startsWith('/')) {
      const parts = text.split(' ');
      const cmd = parts[0].toLowerCase();

      if (cmd === '/help') {
        addChatMessage('Commands: /heal (restore health), /gold (grant 50g), /zone (zone info), /unstuck, /roll', 'system');
      } else if (cmd === '/heal') {
        soundEngine.playHeal();
        setPlayer((p) => ({ ...p, hp: p.maxHp, mp: p.maxMp }));
        addChatMessage('Restored to full Health and Mana!', 'system');
      } else if (cmd === '/gold') {
        soundEngine.playCoins();
        setPlayer((p) => ({ ...p, gold: p.gold + 50 }));
        addChatMessage('Granted 50 Gold.', 'system');
      } else if (cmd === '/zone') {
        addChatMessage(`Current Zone: ${currentZone.name} (${currentZone.levelRange}, ${currentZone.pvpMode})`, 'system');
      } else if (cmd === '/unstuck') {
        setPlayer((p) => ({ ...p, x: 500, y: 400 }));
        addChatMessage('Teleported to town square safely.', 'system');
      } else if (cmd === '/roll') {
        const roll = Math.floor(Math.random() * 100) + 1;
        addChatMessage(`${player.name} rolls ${roll} (1-100).`, 'global');
      } else {
        addChatMessage(`Unknown command ${cmd}. Type /help for assistance.`, 'system');
      }
      return;
    }

    addChatMessage(text, 'global', player.name);
  };

  // --- Character Creation / Switch ---
  const handleCreateOrSwitchCharacter = (name: string, species: SpeciesId, classId: ClassId) => {
    const spec = SPECIES_DATA[species];
    const cls = CLASS_DATA[classId];

    const freshChar: PlayerCharacter = {
      ...createDefaultCharacter(),
      name,
      species,
      classId,
      hp: 100 + spec.defaultStats.vitality * 5,
      maxHp: 100 + spec.defaultStats.vitality * 5,
      mp: 50 + spec.defaultStats.intelligence * 4,
      maxMp: 50 + spec.defaultStats.intelligence * 4,
      stats: {
        ...spec.defaultStats,
      },
    };

    setPlayer(freshChar);
    setIsCharSelectOpen(false);
    addChatMessage(
      `Character created: ${name} the ${spec.name} ${cls.name}! Welcome to the world.`,
      'system'
    );
  };

  return (
    <div
      id="synmergia-root"
      className="relative w-screen h-screen overflow-hidden bg-slate-950 font-sans select-none flex flex-col"
    >
      {/* Top Multi-Mode Portal Header */}
      <PortalHeader
        currentMode={portalMode}
        onSelectMode={setPortalMode}
        crossOriginIsolated={crossOriginIsolated}
        activePlayerCount={activePlayerCount}
        serverTickRate={serverTickRate}
      />

      {/* Mode 1: Godot WASM Web Client */}
      {portalMode === 'wasm' && (
        <GodotClientView onSwitchToCompanion={() => setPortalMode('companion')} />
      )}

      {/* Mode 2: Admin & Ops Dashboard */}
      {portalMode === 'admin' && <AdminDashboardView />}

      {/* Mode 3: 2D Companion RPG Client */}
      {portalMode === 'companion' && (
        <div className="relative flex-1 w-full h-full overflow-hidden">
          {/* 1. Main Interactive 2D World Canvas */}
      <GameCanvas
        player={player}
        enemies={enemies}
        npcs={npcs}
        currentZone={currentZone}
        combatTexts={combatTexts}
        selectedEnemy={selectedEnemy}
        selectedNpc={selectedNpc}
        onSelectEnemy={setSelectedEnemy}
        onSelectNpc={handleSelectNpc}
        onMovePlayer={(dx, dy) => handlePlayerMove(player.x + dx, player.y + dy)}
        onPlayerClickMove={handlePlayerMove}
        onUseSkill={handleUseSkill}
        activeSkillCast={activeSkillCast}
        joystickVector={joystickVector}
      />

      {/* 2. Heads-Up Display (Unit frames, Action bar, Buffs, Status) */}
      <HUD
        player={player}
        selectedEnemy={selectedEnemy}
        selectedNpc={selectedNpc}
        currentZone={currentZone}
        skills={classSkills}
        cooldowns={cooldowns}
        onUseSkill={handleUseSkill}
        onUsePotion={handleUsePotion}
        potionCount={potionCount}
        onToggleCharacter={() => setIsCharSheetOpen((prev) => !prev)}
        onToggleInventory={() => setIsInventoryOpen((prev) => !prev)}
        onToggleQuests={() => setIsQuestOpen((prev) => !prev)}
        onToggleMap={() => setIsMapOpen((prev) => !prev)}
        onToggleAchievements={() => setIsAchievementsOpen((prev) => !prev)}
        onClearTarget={() => {
          setSelectedEnemy(null);
          setSelectedNpc(null);
        }}
        isMuted={isMuted}
        onToggleMute={() => {
          soundEngine.isMuted = !isMuted;
          setIsMuted(!isMuted);
        }}
      />

      {/* 3. Multi-channel Live Chat & Command Console */}
      <ChatBox
        messages={chatMessages}
        onSendMessage={handleSendChat}
        playerLevel={player.level}
      />

      {/* 4. Touch Screen Virtual Joystick */}
      <VirtualJoystick onMove={setJoystickVector} />

      {/* 5. Modals & Dialogs */}
      <CharacterSelectModal
        isOpen={isCharSelectOpen}
        onSelectCharacter={handleCreateOrSwitchCharacter}
        onClose={() => setIsCharSelectOpen(false)}
        canCancel={true}
      />

      <CharacterSheetModal
        isOpen={isCharSheetOpen}
        player={player}
        onClose={() => setIsCharSheetOpen(false)}
      />

      <InventoryModal
        isOpen={isInventoryOpen}
        player={player}
        onEquipItem={handleEquipItem}
        onUnequipItem={handleUnequipItem}
        onUseItem={handleUseInventoryItem}
        onDropItem={handleDropItem}
        onClose={() => setIsInventoryOpen(false)}
      />

      <QuestModal
        isOpen={isQuestOpen}
        player={player}
        onClose={() => setIsQuestOpen(false)}
        onCompleteQuest={handleCompleteQuest}
      />

      <ShopModal
        isOpen={isShopOpen}
        player={player}
        onBuyItem={handleBuyShopItem}
        onSellItem={handleSellInventoryItem}
        onClose={() => setIsShopOpen(false)}
      />

      <BlacksmithModal
        isOpen={isBlacksmithOpen}
        player={player}
        onUpgradeWeapon={handleUpgradeWeapon}
        onCraftItem={handleCraftItem}
        onClose={() => setIsBlacksmithOpen(false)}
      />

      <WorldMapModal
        isOpen={isMapOpen}
        currentZoneId={currentZoneId}
        onTeleportToZone={handleTeleportToZone}
        onClose={() => setIsMapOpen(false)}
      />

      <AchievementsModal
        isOpen={isAchievementsOpen}
        unlockedIds={player.unlockedAchievements}
        onClose={() => setIsAchievementsOpen(false)}
      />
        </div>
      )}
    </div>
  );
}
