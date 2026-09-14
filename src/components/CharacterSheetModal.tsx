import React from 'react';
import { PlayerCharacter, EquipSlot } from '../types';
import { SPECIES_DATA, CLASS_DATA } from '../gameData';
import { Shield, Swords, Sparkles, Heart, Zap, Award, Coins } from 'lucide-react';

interface CharacterSheetModalProps {
  isOpen: boolean;
  player: PlayerCharacter;
  onClose: () => void;
}

export const CharacterSheetModal: React.FC<CharacterSheetModalProps> = ({
  isOpen,
  player,
  onClose,
}) => {
  if (!isOpen) return null;

  const speciesInfo = SPECIES_DATA[player.species];
  const classInfo = CLASS_DATA[player.classId];

  // Calculate total gear stats
  let bonusAttack = 0;
  let bonusSpell = 0;
  let bonusArmor = 0;
  let bonusVit = 0;

  Object.values(player.equipment).forEach((item) => {
    if (!item?.stats) return;
    bonusAttack += item.stats.attackPower || 0;
    bonusSpell += item.stats.spellPower || 0;
    bonusArmor += item.stats.armor || 0;
    bonusVit += item.stats.vitality || 0;
  });

  const totalAttackPower =
    Math.round(player.stats.strength * 1.5 + player.stats.agility * 0.8) +
    bonusAttack;
  const totalSpellPower =
    Math.round(player.stats.intelligence * 1.6 + player.stats.wisdom * 0.7) +
    bonusSpell;
  const totalArmor =
    Math.round(player.stats.endurance * 1.2 + player.stats.vitality * 0.4) +
    bonusArmor;

  const equipSlots: { slot: EquipSlot; label: string }[] = [
    { slot: 'head', label: 'Headgear' },
    { slot: 'chest', label: 'Armor / Robe' },
    { slot: 'main_hand', label: 'Main Hand' },
    { slot: 'off_hand', label: 'Off Hand / Shield' },
    { slot: 'accessory', label: 'Accessory / Ring' },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="character-profile-modal"
        className="relative w-full max-w-xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[90vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-amber-500/20 border border-amber-500 flex items-center justify-center font-fantasy text-xl font-bold text-amber-400">
              {player.species[0].toUpperCase()}
            </div>
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">
                {player.name}
              </h2>
              <p className="text-xs text-amber-400 font-medium capitalize">
                Level {player.level} {speciesInfo.name} {classInfo.name}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-200 text-lg p-1"
          >
            ✕
          </button>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {/* Attributes Box */}
          <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-4 space-y-2.5">
            <h3 className="text-xs font-fantasy font-bold text-slate-300 uppercase tracking-wider border-b border-slate-800 pb-1.5 flex items-center gap-1.5">
              <Award className="w-3.5 h-3.5 text-amber-400" />
              Primary Attributes
            </h3>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Strength:</span>
                <span className="font-bold text-slate-200">{player.stats.strength}</span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Agility:</span>
                <span className="font-bold text-slate-200">{player.stats.agility}</span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Intelligence:</span>
                <span className="font-bold text-slate-200">{player.stats.intelligence}</span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Vitality:</span>
                <span className="font-bold text-slate-200">
                  {player.stats.vitality} {bonusVit > 0 ? `(+${bonusVit})` : ''}
                </span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Endurance:</span>
                <span className="font-bold text-slate-200">{player.stats.endurance}</span>
              </div>
              <div className="flex justify-between py-1 border-b border-slate-900">
                <span className="text-slate-400">Wisdom:</span>
                <span className="font-bold text-slate-200">{player.stats.wisdom}</span>
              </div>
            </div>

            {/* Derived Combat Ratings */}
            <h3 className="text-xs font-fantasy font-bold text-slate-300 uppercase tracking-wider pt-2 border-b border-slate-800 pb-1 flex items-center gap-1.5">
              <Swords className="w-3.5 h-3.5 text-red-400" />
              Combat Ratings
            </h3>
            <div className="space-y-1 text-xs">
              <div className="flex justify-between">
                <span className="text-slate-400">Attack Power:</span>
                <span className="font-bold text-red-400">{totalAttackPower}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Spell Power:</span>
                <span className="font-bold text-purple-400">{totalSpellPower}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Armor Rating:</span>
                <span className="font-bold text-sky-400">{totalArmor}</span>
              </div>
            </div>
          </div>

          {/* Equipped Gear & Wealth */}
          <div className="bg-slate-950/70 border border-slate-800 rounded-xl p-4 space-y-3">
            <h3 className="text-xs font-fantasy font-bold text-slate-300 uppercase tracking-wider border-b border-slate-800 pb-1.5 flex items-center gap-1.5">
              <Shield className="w-3.5 h-3.5 text-sky-400" />
              Equipped Artifacts
            </h3>

            <div className="space-y-1.5">
              {equipSlots.map(({ slot, label }) => {
                const item = player.equipment[slot];
                return (
                  <div
                    key={slot}
                    className="flex items-center justify-between p-2 rounded-lg bg-slate-900/80 border border-slate-800 text-xs"
                  >
                    <span className="text-slate-400 text-[11px]">{label}:</span>
                    {item ? (
                      <span className="font-semibold text-amber-300 truncate max-w-[140px]">
                        {item.name}
                      </span>
                    ) : (
                      <span className="text-slate-600 italic text-[10px]">Empty</span>
                    )}
                  </div>
                );
              })}
            </div>

            <div className="pt-2 border-t border-slate-800 flex items-center justify-between">
              <span className="text-xs text-slate-400 flex items-center gap-1">
                <Coins className="w-4 h-4 text-amber-400" />
                Coin Purse:
              </span>
              <span className="font-bold text-amber-400 text-sm">
                {player.gold} Gold
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
