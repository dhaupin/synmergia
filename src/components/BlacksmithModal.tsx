import React from 'react';
import { Item, PlayerCharacter } from '../types';
import { Anvil, Coins, Hammer, Shield, Sparkles } from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface BlacksmithModalProps {
  isOpen: boolean;
  player: PlayerCharacter;
  onUpgradeWeapon: () => void;
  onCraftItem: (item: Item, oreCost: number, goldCost: number) => void;
  onClose: () => void;
}

export const BlacksmithModal: React.FC<BlacksmithModalProps> = ({
  isOpen,
  player,
  onUpgradeWeapon,
  onCraftItem,
  onClose,
}) => {
  if (!isOpen) return null;

  // Count iron ores in player inventory
  let ironOreCount = 0;
  player.inventory.forEach((item) => {
    if (item && item.id === 'iron_ore') {
      ironOreCount += item.quantity || 1;
    }
  });

  const equippedWeapon = player.equipment.main_hand;

  const craftableRecipes: {
    item: Item;
    oreCost: number;
    goldCost: number;
  }[] = [
    {
      item: {
        id: 'crafted_broadsword',
        name: 'Refined Damascus Broadsword',
        type: 'weapon',
        rarity: 'rare',
        slot: 'main_hand',
        description: 'Folded steel blade tempered with dwarf embers.',
        stats: { attackPower: 18, strength: 5 },
        value: 120,
        icon: 'Sword',
      },
      oreCost: 5,
      goldCost: 60,
    },
    {
      item: {
        id: 'crafted_platemail',
        name: 'Aegis Vanguard Cuirass',
        type: 'armor',
        rarity: 'rare',
        slot: 'chest',
        description: 'Heavy plate armor etched with protective ward runes.',
        stats: { armor: 25, vitality: 8 },
        value: 150,
        icon: 'Shield',
      },
      oreCost: 8,
      goldCost: 80,
    },
    {
      item: {
        id: 'crafted_ring',
        name: 'Sunstone Infused Band',
        type: 'accessory',
        rarity: 'rare',
        slot: 'accessory',
        description: 'Ring set with a radiant ember that enhances life vigor.',
        stats: { spellPower: 12, vitality: 6 },
        value: 100,
        icon: 'CircleDot',
      },
      oreCost: 4,
      goldCost: 50,
    },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="blacksmith-forge-modal"
        className="relative w-full max-w-xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2.5">
            <Hammer className="w-5 h-5 text-amber-500" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">
                Torvald’s Iron Forge
              </h2>
              <p className="text-[11px] text-slate-400">
                Weapon tempering & masterwork metallurgy
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2 text-xs font-bold bg-slate-950 px-2.5 py-1 rounded-lg border border-slate-800">
              <span className="text-slate-300">Ore: {ironOreCount}</span>
              <span className="text-amber-400 flex items-center gap-0.5">
                <Coins className="w-3.5 h-3.5" />
                {player.gold}g
              </span>
            </div>
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-slate-200 text-lg p-1"
            >
              ✕
            </button>
          </div>
        </div>

        {/* Section 1: Weapon Tempering */}
        <div className="mb-5 bg-slate-950/70 border border-slate-800 rounded-xl p-4">
          <h3 className="text-xs font-fantasy font-bold text-amber-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
            <Sparkles className="w-3.5 h-3.5" />
            Temper Equipped Armament
          </h3>

          {equippedWeapon ? (
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
              <div>
                <span className="font-fantasy font-bold text-sm text-slate-100 block">
                  {equippedWeapon.name}
                </span>
                <span className="text-xs text-red-400 font-semibold">
                  Current Power: +{equippedWeapon.stats?.attackPower || 0} AP
                </span>
                <p className="text-[11px] text-slate-400 mt-0.5">
                  Enhancement grants +4 Attack Power
                </p>
              </div>

              <button
                onClick={() => {
                  if (ironOreCount >= 2 && player.gold >= 30) {
                    onUpgradeWeapon();
                    soundEngine.playLevelUp();
                  }
                }}
                disabled={ironOreCount < 2 || player.gold < 30}
                className={`px-4 py-2 rounded-lg text-xs font-bold transition flex items-center gap-1.5 ${
                  ironOreCount >= 2 && player.gold >= 30
                    ? 'bg-amber-600 hover:bg-amber-500 text-slate-950'
                    : 'bg-slate-800 text-slate-500 cursor-not-allowed'
                }`}
              >
                <Hammer className="w-3.5 h-3.5" />
                Temper (2 Ore + 30g)
              </button>
            </div>
          ) : (
            <p className="text-xs text-slate-500 italic">
              No weapon equipped in main hand. Equip a blade or staff first!
            </p>
          )}
        </div>

        {/* Section 2: Crafting Blueprints */}
        <div>
          <h3 className="text-xs font-fantasy font-bold text-slate-300 uppercase tracking-wider mb-2.5">
            Forge New Masterwork Wares
          </h3>

          <div className="space-y-2.5">
            {craftableRecipes.map(({ item, oreCost, goldCost }) => {
              const canCraft = ironOreCount >= oreCost && player.gold >= goldCost;

              return (
                <div
                  key={item.id}
                  className="p-3.5 rounded-xl border border-slate-800 bg-slate-950/80 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3"
                >
                  <div>
                    <span className="font-fantasy font-bold text-sm text-slate-100 block">
                      {item.name}
                    </span>
                    <span className="text-[11px] text-sky-400 font-medium">
                      {item.stats?.attackPower ? `+${item.stats.attackPower} AP ` : ''}
                      {item.stats?.armor ? `+${item.stats.armor} Armor ` : ''}
                      {item.stats?.vitality ? `+${item.stats.vitality} Vit ` : ''}
                    </span>
                    <p className="text-[11px] text-slate-400 mt-0.5">
                      {item.description}
                    </p>
                  </div>

                  <button
                    onClick={() => {
                      if (canCraft) {
                        onCraftItem(item, oreCost, goldCost);
                        soundEngine.playLevelUp();
                      }
                    }}
                    disabled={!canCraft}
                    className={`px-4 py-2 rounded-lg text-xs font-bold transition whitespace-nowrap ${
                      canCraft
                        ? 'bg-amber-600 hover:bg-amber-500 text-slate-950'
                        : 'bg-slate-800 text-slate-500 cursor-not-allowed'
                    }`}
                  >
                    Forge ({oreCost} Ore, {goldCost}g)
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
};
