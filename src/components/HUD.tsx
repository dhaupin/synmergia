import React from 'react';
import {
  PlayerCharacter,
  Enemy,
  NPC,
  Skill,
  Zone,
} from '../types';
import {
  Shield,
  Heart,
  Zap,
  Swords,
  Backpack,
  User,
  ScrollText,
  Map as MapIcon,
  Trophy,
  Volume2,
  VolumeX,
  Target,
  Sparkles,
  Flame,
  Sun,
  Crosshair,
  ChevronsRight,
  RotateCw,
  AlertCircle,
  ShieldAlert,
  ShieldCheck,
  Disc,
  HeartHandshake,
  Anchor,
  EyeOff,
  Activity,
  Clock,
} from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface HUDProps {
  player: PlayerCharacter;
  selectedEnemy: Enemy | null;
  selectedNpc: NPC | null;
  currentZone: Zone;
  skills: Skill[];
  cooldowns: Record<string, number>;
  onUseSkill: (skill: Skill) => void;
  onUsePotion: () => void;
  potionCount: number;
  onToggleCharacter: () => void;
  onToggleInventory: () => void;
  onToggleQuests: () => void;
  onToggleMap: () => void;
  onToggleAchievements: () => void;
  onClearTarget: () => void;
  isMuted: boolean;
  onToggleMute: () => void;
  /** Number of achievements unlocked (renders a badge on the trophy). */
  unlockedAchievementCount?: number;
}

// Icon helper mapping
const renderSkillIcon = (iconName: string) => {
  const iconProps = { className: 'w-5 h-5 text-amber-200' };
  switch (iconName) {
    case 'Sword':
      return <Swords {...iconProps} />;
    case 'ChevronsRight':
      return <ChevronsRight {...iconProps} />;
    case 'Flame':
      return <Flame {...iconProps} />;
    case 'RotateCw':
      return <RotateCw {...iconProps} />;
    case 'Shield':
      return <Shield {...iconProps} />;
    case 'AlertCircle':
      return <AlertCircle {...iconProps} />;
    case 'ShieldAlert':
      return <ShieldAlert {...iconProps} />;
    case 'Sparkles':
      return <Sparkles {...iconProps} />;
    case 'Disc':
      return <Disc {...iconProps} />;
    case 'Zap':
      return <Zap {...iconProps} />;
    case 'Sun':
      return <Sun {...iconProps} />;
    case 'HeartHandshake':
      return <HeartHandshake {...iconProps} />;
    case 'ShieldCheck':
      return <ShieldCheck {...iconProps} />;
    case 'Crosshair':
      return <Crosshair {...iconProps} />;
    case 'Anchor':
      return <Anchor {...iconProps} />;
    case 'EyeOff':
      return <EyeOff {...iconProps} />;
    case 'Activity':
      return <Activity {...iconProps} />;
    case 'Clock':
      return <Clock {...iconProps} />;
    default:
      return <Sparkles {...iconProps} />;
  }
};

export const HUD: React.FC<HUDProps> = ({
  player,
  selectedEnemy,
  selectedNpc,
  currentZone,
  skills,
  cooldowns,
  onUseSkill,
  onUsePotion,
  potionCount,
  onToggleCharacter,
  onToggleInventory,
  onToggleQuests,
  onToggleMap,
  onToggleAchievements,
  onClearTarget,
  isMuted,
  onToggleMute,
  unlockedAchievementCount,
}) => {
  const hpPercent = Math.max(0, Math.min(100, (player.hp / player.maxHp) * 100));
  const mpPercent = Math.max(0, Math.min(100, (player.mp / player.maxMp) * 100));
  const staminaPercent = Math.max(
    0,
    Math.min(100, (player.stamina / player.maxStamina) * 100)
  );
  const xpPercent = Math.max(0, Math.min(100, (player.xp / player.maxXp) * 100));

  return (
    <div className="pointer-events-none absolute inset-0 flex flex-col justify-between p-3 sm:p-4 select-none">
      {/* ================= TOP BAR ================= */}
      <div className="flex items-start justify-between gap-4 w-full">
        {/* --- Player Unit Frame --- */}
        <div
          id="player-unit-frame"
          className="pointer-events-auto bg-slate-900/90 border border-slate-700/80 rounded-xl p-3 shadow-2xl backdrop-blur-md flex items-center gap-3.5 min-w-[260px] sm:min-w-[310px]"
        >
          {/* Species Portrait Avatar */}
          <div
            onClick={onToggleCharacter}
            className="relative cursor-pointer w-13 h-13 rounded-lg flex items-center justify-center border-2 border-amber-500/80 bg-gradient-to-br from-slate-800 to-slate-950 shadow-md group hover:border-amber-400 transition"
          >
            <span className="text-xl font-fantasy text-amber-300 font-bold">
              {player.species[0].toUpperCase()}
            </span>
            <span className="absolute -bottom-2 -right-1.5 bg-amber-600 text-slate-950 font-bold text-[10px] px-1.5 py-0.5 rounded-full border border-slate-900">
              {player.level}
            </span>
          </div>

          {/* Name & Bars */}
          <div className="flex-1 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-sm font-fantasy font-semibold text-slate-100 tracking-wide">
                {player.name}
              </span>
              <span className="text-[11px] text-amber-400/90 font-medium capitalize">
                {player.species} {player.classId}
              </span>
            </div>

            {/* Health Bar */}
            <div className="relative w-full h-3.5 bg-slate-950 rounded overflow-hidden border border-red-950">
              <div
                className="h-full bg-gradient-to-r from-red-600 to-rose-500 transition-all duration-200"
                style={{ width: `${hpPercent}%` }}
              />
              <span className="absolute inset-0 flex items-center justify-center text-[10px] font-bold text-white drop-shadow">
                {Math.ceil(player.hp)} / {player.maxHp} HP
              </span>
            </div>

            {/* Resource Bar (Mana / Energy) */}
            <div className="relative w-full h-2.5 bg-slate-950 rounded overflow-hidden border border-sky-950">
              <div
                className="h-full bg-gradient-to-r from-sky-600 to-cyan-400 transition-all duration-200"
                style={{ width: `${mpPercent}%` }}
              />
              <span className="absolute inset-0 flex items-center justify-center text-[9px] font-semibold text-sky-100 drop-shadow">
                {Math.ceil(player.mp)} / {player.maxMp} MP
              </span>
            </div>

            {/* Stamina Bar */}
            <div className="relative w-full h-1.5 bg-slate-950 rounded overflow-hidden">
              <div
                className="h-full bg-amber-500 transition-all duration-150"
                style={{ width: `${staminaPercent}%` }}
              />
            </div>
          </div>
        </div>

        {/* --- Center: Target Frame (Enemy or NPC) --- */}
        {selectedEnemy && selectedEnemy.hp > 0 && (
          <div
            id="target-unit-frame"
            className="pointer-events-auto bg-slate-900/90 border border-red-600/50 rounded-xl p-3 shadow-2xl backdrop-blur-md flex items-center gap-3 min-w-[240px] sm:min-w-[280px]"
          >
            <div className="w-11 h-11 rounded-lg flex items-center justify-center border-2 border-red-500 bg-red-950/60">
              <Target className="w-6 h-6 text-red-400" />
            </div>
            <div className="flex-1">
              <div className="flex items-center justify-between">
                <span className="text-sm font-fantasy font-semibold text-red-200">
                  {selectedEnemy.name}
                </span>
                <span className="text-xs font-bold text-amber-400">
                  Lv.{selectedEnemy.level}
                </span>
              </div>
              <div className="relative w-full h-3 bg-slate-950 rounded overflow-hidden border border-red-950 mt-1">
                <div
                  className="h-full bg-gradient-to-r from-red-600 to-rose-500 transition-all duration-200"
                  style={{
                    width: `${Math.max(
                      0,
                      (selectedEnemy.hp / selectedEnemy.maxHp) * 100
                    )}%`,
                  }}
                />
                <span className="absolute inset-0 flex items-center justify-center text-[9px] font-bold text-white drop-shadow">
                  {Math.ceil(selectedEnemy.hp)} / {selectedEnemy.maxHp}
                </span>
              </div>
            </div>
            <button
              onClick={onClearTarget}
              className="text-slate-400 hover:text-slate-200 text-xs px-1"
            >
              ✕
            </button>
          </div>
        )}

        {selectedNpc && (
          <div
            id="target-npc-frame"
            className="pointer-events-auto bg-slate-900/90 border border-sky-500/50 rounded-xl p-3 shadow-2xl backdrop-blur-md flex items-center gap-3 min-w-[240px]"
          >
            <div className="w-11 h-11 rounded-lg flex items-center justify-center border-2 border-sky-400 bg-sky-950/60 text-sky-200 font-bold">
              NPC
            </div>
            <div className="flex-1">
              <span className="text-sm font-fantasy font-semibold text-sky-200 block">
                {selectedNpc.name}
              </span>
              <span className="text-[11px] text-slate-300">
                &lt;{selectedNpc.title}&gt;
              </span>
            </div>
            <button
              onClick={onClearTarget}
              className="text-slate-400 hover:text-slate-200 text-xs px-1"
            >
              ✕
            </button>
          </div>
        )}

        {/* --- Top Right: Zone Info & Controls --- */}
        <div className="flex flex-col items-end gap-2">
          <div
            id="zone-info-card"
            className="pointer-events-auto bg-slate-900/90 border border-slate-700/80 rounded-xl px-3.5 py-2 shadow-2xl backdrop-blur-md text-right"
          >
            <div className="flex items-center justify-end gap-2">
              <span className="text-xs font-fantasy font-bold text-slate-100">
                {currentZone.name}
              </span>
              <span
                className={`text-[9px] font-bold uppercase px-1.5 py-0.5 rounded ${
                  currentZone.pvpMode === 'safe'
                    ? 'bg-emerald-950 text-emerald-400 border border-emerald-800'
                    : currentZone.pvpMode === 'contested'
                    ? 'bg-amber-950 text-amber-400 border border-amber-800'
                    : 'bg-red-950 text-red-400 border border-red-800'
                }`}
              >
                {currentZone.pvpMode === 'safe'
                  ? 'Safe Zone'
                  : currentZone.pvpMode === 'contested'
                  ? 'Contested'
                  : 'Free PvP'}
              </span>
            </div>
            <span className="text-[10px] text-slate-400 block mt-0.5">
              {currentZone.levelRange} • {currentZone.subtitle}
            </span>
          </div>

          <button
            id="mute-sound-btn"
            onClick={onToggleMute}
            className="pointer-events-auto bg-slate-900/90 hover:bg-slate-800 border border-slate-700 p-2 rounded-lg text-slate-300 transition"
            title={isMuted ? 'Unmute Sound FX' : 'Mute Sound FX'}
          >
            {isMuted ? <VolumeX className="w-4 h-4 text-red-400" /> : <Volume2 className="w-4 h-4 text-emerald-400" />}
          </button>
        </div>
      </div>

      {/* ================= ACTIVE BUFFS ================= */}
      <div className="flex flex-wrap gap-1.5 max-w-md my-auto">
        {(player.activeBuffs || []).map((buff) => (
          <div
            key={buff.id}
            className="pointer-events-auto bg-slate-900/90 border border-sky-400/60 rounded px-2 py-0.5 flex items-center gap-1.5 text-xs text-sky-200 shadow"
          >
            <Sparkles className="w-3 h-3 text-sky-400" />
            <span className="font-medium text-[11px]">{buff.name}</span>
            <span className="text-[10px] text-sky-400/90 font-mono">
              {Math.ceil(buff.duration)}s
            </span>
          </div>
        ))}
      </div>

      {/* ================= BOTTOM BAR ================= */}
      <div className="flex flex-col items-center gap-2 w-full">
        {/* Experience Bar */}
        <div
          id="experience-bar"
          className="w-full max-w-xl h-2 bg-slate-950/80 rounded-full overflow-hidden border border-slate-800/80 relative shadow-inner"
        >
          <div
            className="h-full bg-gradient-to-r from-amber-600 via-amber-400 to-amber-300 transition-all duration-300"
            style={{ width: `${xpPercent}%` }}
          />
        </div>

        {/* Action Bar + Utility Buttons */}
        <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
          {/* Action Bar (Skills) */}
          <div
            id="action-bar"
            className="pointer-events-auto bg-slate-900/95 border border-amber-600/40 rounded-2xl p-2 shadow-2xl backdrop-blur-md flex items-center gap-1.5 sm:gap-2"
          >
            {(skills || []).map((skill, index) => {
              const cd = (cooldowns && cooldowns[skill.id]) || 0;
              const hasCd = cd > 0;
              const hasResource =
                player.mp >= skill.manaCost && player.stamina >= skill.staminaCost;

              return (
                <button
                  key={skill.id}
                  id={`skill-slot-${index + 1}`}
                  onClick={() => onUseSkill(skill)}
                  disabled={hasCd || !hasResource}
                  title={`${skill.name} [Hotkey ${index + 1}]\n${skill.description}\nCost: ${
                    skill.manaCost > 0 ? `${skill.manaCost} MP` : `${skill.staminaCost} Stamina`
                  }`}
                  className={`relative group w-11 h-11 sm:w-13 sm:h-13 rounded-xl flex flex-col items-center justify-center border transition-all ${
                    hasCd
                      ? 'border-slate-800 bg-slate-950/80 opacity-70'
                      : !hasResource
                      ? 'border-red-900 bg-slate-900 opacity-60'
                      : 'border-slate-700 bg-slate-800 hover:border-amber-400 hover:bg-slate-750 active:scale-95 shadow-md'
                  }`}
                >
                  {renderSkillIcon(skill.icon)}

                  {/* Hotkey Badge */}
                  <span className="absolute top-1 left-1.5 text-[9px] font-bold text-amber-300/80">
                    {index + 1}
                  </span>

                  {/* Cooldown Overlay */}
                  {hasCd && (
                    <div className="absolute inset-0 bg-black/75 rounded-xl flex items-center justify-center">
                      <span className="text-xs font-bold text-amber-400 font-mono">
                        {cd.toFixed(1)}
                      </span>
                    </div>
                  )}

                  {/* Cost Pill */}
                  <span className="absolute bottom-0.5 text-[8px] text-slate-400">
                    {skill.manaCost > 0 ? `${skill.manaCost}m` : `${skill.staminaCost}s`}
                  </span>
                </button>
              );
            })}

            {/* Quick Consumable Potion Slot */}
            <button
              id="potion-quick-slot"
              onClick={onUsePotion}
              disabled={potionCount <= 0}
              title={`Health Potion [Hotkey 7] (${potionCount} available)`}
              className="relative group w-11 h-11 sm:w-13 sm:h-13 rounded-xl flex flex-col items-center justify-center border border-red-700/60 bg-red-950/40 hover:border-red-400 active:scale-95 transition"
            >
              <Heart className="w-5 h-5 text-red-400" />
              <span className="absolute top-1 left-1.5 text-[9px] font-bold text-red-300">
                7
              </span>
              <span className="absolute bottom-0.5 right-1 text-[10px] font-bold text-amber-300">
                x{potionCount}
              </span>
            </button>
          </div>

          {/* Menus / Windows Quick Access */}
          <div
            id="hud-menu-bar"
            className="pointer-events-auto bg-slate-900/90 border border-slate-700/80 rounded-2xl p-1.5 shadow-2xl backdrop-blur-md flex items-center gap-1"
          >
            <button
              id="open-character-btn"
              onClick={onToggleCharacter}
              className="p-2 rounded-lg text-slate-300 hover:text-amber-300 hover:bg-slate-800 transition"
              title="Character Profile [C]"
            >
              <User className="w-5 h-5" />
            </button>
            <button
              id="open-inventory-btn"
              onClick={onToggleInventory}
              className="p-2 rounded-lg text-slate-300 hover:text-amber-300 hover:bg-slate-800 transition relative"
              title="Inventory Bag [B]"
            >
              <Backpack className="w-5 h-5" />
              <span className="absolute -top-1 -right-1 bg-amber-500 text-slate-950 text-[9px] font-bold px-1 rounded-full">
                {(player.inventory || []).filter(Boolean).length}
              </span>
            </button>
            <button
              id="open-quests-btn"
              onClick={onToggleQuests}
              className="p-2 rounded-lg text-slate-300 hover:text-amber-300 hover:bg-slate-800 transition relative"
              title="Quest Log [L]"
            >
              <ScrollText className="w-5 h-5" />
              {(player.activeQuests || []).length > 0 && (
                <span className="absolute -top-1 -right-1 bg-sky-500 text-white text-[9px] font-bold px-1 rounded-full">
                  {(player.activeQuests || []).length}
                </span>
              )}
            </button>
            <button
              id="open-map-btn"
              onClick={onToggleMap}
              className="p-2 rounded-lg text-slate-300 hover:text-amber-300 hover:bg-slate-800 transition"
              title="Continent Map [M]"
            >
              <MapIcon className="w-5 h-5" />
            </button>
            <button
              id="open-achievements-btn"
              onClick={onToggleAchievements}
              className="p-2 rounded-lg text-slate-300 hover:text-amber-300 hover:bg-slate-800 transition relative"
              title="Achievements [H]"
            >
              <Trophy className="w-5 h-5" />
              {(unlockedAchievementCount ?? 0) > 0 && (
                <span className="absolute -top-1 -right-1 bg-amber-500 text-slate-950 text-[9px] font-bold px-1 rounded-full border border-slate-900">
                  {unlockedAchievementCount}
                </span>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
