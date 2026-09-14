import React, { useState } from 'react';
import { Item, PlayerCharacter, EquipSlot, ItemRarity } from '../types';
import {
  Shield,
  Swords,
  Coins,
  Trash2,
  CheckCircle,
  Package,
  Layers,
  Sparkles,
} from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface InventoryModalProps {
  isOpen: boolean;
  player: PlayerCharacter;
  onEquipItem: (item: Item, slot: EquipSlot) => void;
  onUnequipItem: (slot: EquipSlot) => void;
  onUseItem: (item: Item) => void;
  onDropItem: (index: number) => void;
  onClose: () => void;
}

const getRarityColor = (rarity: ItemRarity) => {
  switch (rarity) {
    case 'common':
      return 'border-slate-600 text-slate-300';
    case 'uncommon':
      return 'border-emerald-500 text-emerald-400';
    case 'rare':
      return 'border-sky-500 text-sky-400';
    case 'epic':
      return 'border-purple-500 text-purple-400';
    case 'legendary':
      return 'border-amber-400 text-amber-300';
    default:
      return 'border-slate-700 text-slate-400';
  }
};

export const InventoryModal: React.FC<InventoryModalProps> = ({
  isOpen,
  player,
  onEquipItem,
  onUnequipItem,
  onUseItem,
  onDropItem,
  onClose,
}) => {
  const [selectedSlotIndex, setSelectedSlotIndex] = useState<number | null>(null);
  const [selectedEquipSlot, setSelectedEquipSlot] = useState<EquipSlot | null>(null);

  if (!isOpen) return null;

  const selectedItem =
    selectedSlotIndex !== null ? player.inventory[selectedSlotIndex] : null;

  const equippedItem =
    selectedEquipSlot !== null ? player.equipment[selectedEquipSlot] : null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="inventory-modal-card"
        className="relative w-full max-w-2xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[90vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <Package className="w-5 h-5 text-amber-400" />
            <h2 className="text-lg font-fantasy font-bold text-slate-100">
              Adventurer’s Satchel
            </h2>
            <span className="text-xs text-slate-400">
              ({player.inventory.filter(Boolean).length} / {player.inventory.length} slots)
            </span>
          </div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-1.5 text-xs font-bold text-amber-400 bg-slate-950 px-2.5 py-1 rounded-lg border border-amber-500/30">
              <Coins className="w-4 h-4 text-amber-400" />
              <span>{player.gold} Gold</span>
            </div>
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-slate-200 text-lg p-1"
            >
              ✕
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          {/* Inventory Grid (2 columns on left) */}
          <div className="md:col-span-2 space-y-3">
            <div className="grid grid-cols-4 sm:grid-cols-5 gap-2.5">
              {player.inventory.map((item, index) => {
                const isSelected = selectedSlotIndex === index;
                const rarityStyle = item ? getRarityColor(item.rarity) : 'border-slate-800';

                return (
                  <button
                    key={index}
                    onClick={() => {
                      setSelectedSlotIndex(index);
                      setSelectedEquipSlot(null);
                      if (item) soundEngine.playHitImpact();
                    }}
                    className={`relative w-full aspect-square rounded-xl border flex flex-col items-center justify-center p-1.5 transition ${
                      isSelected
                        ? 'border-amber-400 bg-amber-950/40 ring-2 ring-amber-400/40'
                        : item
                        ? `${rarityStyle} bg-slate-950/80 hover:bg-slate-800/80`
                        : 'border-slate-800/80 bg-slate-950/40'
                    }`}
                  >
                    {item ? (
                      <>
                        <span className="text-xs font-bold text-slate-200 truncate max-w-full text-center">
                          {item.name.split(' ')[0]}
                        </span>
                        <span className="text-[9px] text-slate-400 capitalize">
                          {item.type}
                        </span>
                        {item.quantity && item.quantity > 1 && (
                          <span className="absolute bottom-1 right-1.5 bg-slate-900 border border-slate-700 text-[9px] font-mono px-1 rounded text-amber-300">
                            {item.quantity}
                          </span>
                        )}
                      </>
                    ) : (
                      <span className="text-slate-700 text-[10px]">—</span>
                    )}
                  </button>
                );
              })}
            </div>

            {/* Equipment Quick Strip */}
            <div className="pt-2 border-t border-slate-800">
              <span className="text-xs font-bold text-slate-400 uppercase tracking-wider block mb-2">
                Currently Equipped
              </span>
              <div className="grid grid-cols-3 sm:grid-cols-5 gap-2">
                {(['head', 'chest', 'main_hand', 'off_hand', 'accessory'] as EquipSlot[]).map(
                  (slot) => {
                    const item = player.equipment[slot];
                    const isSelected = selectedEquipSlot === slot;
                    return (
                      <button
                        key={slot}
                        onClick={() => {
                          setSelectedEquipSlot(slot);
                          setSelectedSlotIndex(null);
                        }}
                        className={`p-1.5 rounded-lg border text-center transition ${
                          isSelected
                            ? 'border-amber-400 bg-amber-950/30'
                            : item
                            ? 'border-slate-700 bg-slate-950'
                            : 'border-slate-800/60 bg-slate-950/40'
                        }`}
                      >
                        <span className="block text-[9px] text-slate-400 capitalize">
                          {slot.replace('_', ' ')}
                        </span>
                        <span className="block text-[10px] font-semibold text-amber-300 truncate">
                          {item ? item.name : 'Empty'}
                        </span>
                      </button>
                    );
                  }
                )}
              </div>
            </div>
          </div>

          {/* Item Inspector Panel */}
          <div className="bg-slate-950/80 border border-slate-800 rounded-xl p-4 flex flex-col justify-between">
            {selectedItem ? (
              <div className="space-y-3">
                <div className="border-b border-slate-800 pb-2">
                  <span
                    className={`inline-block text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded border mb-1 ${getRarityColor(
                      selectedItem.rarity
                    )}`}
                  >
                    {selectedItem.rarity}
                  </span>
                  <h3 className="font-fantasy font-bold text-sm text-slate-100">
                    {selectedItem.name}
                  </h3>
                  <span className="text-[11px] text-slate-400 capitalize">
                    {selectedItem.type} {selectedItem.slot ? `• ${selectedItem.slot}` : ''}
                  </span>
                </div>

                <p className="text-xs text-slate-300 leading-relaxed italic">
                  "{selectedItem.description}"
                </p>

                {/* Stats */}
                {selectedItem.stats && (
                  <div className="space-y-1 bg-slate-900/90 p-2.5 rounded-lg border border-slate-800 text-xs">
                    {selectedItem.stats.attackPower && (
                      <div className="text-red-400 font-semibold">
                        +{selectedItem.stats.attackPower} Attack Power
                      </div>
                    )}
                    {selectedItem.stats.spellPower && (
                      <div className="text-purple-400 font-semibold">
                        +{selectedItem.stats.spellPower} Spell Power
                      </div>
                    )}
                    {selectedItem.stats.armor && (
                      <div className="text-sky-400 font-semibold">
                        +{selectedItem.stats.armor} Armor
                      </div>
                    )}
                    {selectedItem.stats.vitality && (
                      <div className="text-emerald-400 font-semibold">
                        +{selectedItem.stats.vitality} Vitality
                      </div>
                    )}
                    {selectedItem.stats.strength && (
                      <div className="text-amber-400 font-semibold">
                        +{selectedItem.stats.strength} Strength
                      </div>
                    )}
                    {selectedItem.stats.agility && (
                      <div className="text-cyan-400 font-semibold">
                        +{selectedItem.stats.agility} Agility
                      </div>
                    )}
                  </div>
                )}

                {/* Consumable Effects */}
                {selectedItem.healAmount && (
                  <div className="text-xs text-emerald-400 font-semibold">
                    Restores {selectedItem.healAmount} Health
                  </div>
                )}
                {selectedItem.manaAmount && (
                  <div className="text-xs text-sky-400 font-semibold">
                    Restores {selectedItem.manaAmount} Mana
                  </div>
                )}

                <div className="text-xs text-slate-400 pt-1">
                  Vendor Value: <span className="text-amber-400 font-bold">{selectedItem.value} Gold</span>
                </div>

                {/* Actions */}
                <div className="space-y-1.5 pt-3">
                  {selectedItem.slot && (
                    <button
                      id="equip-item-btn"
                      onClick={() => {
                        onEquipItem(selectedItem, selectedItem.slot!);
                        setSelectedSlotIndex(null);
                        soundEngine.playLevelUp();
                      }}
                      className="w-full bg-amber-600 hover:bg-amber-500 text-slate-950 font-bold text-xs py-2 rounded-lg transition"
                    >
                      Equip Item
                    </button>
                  )}

                  {selectedItem.type === 'consumable' && (
                    <button
                      id="use-item-btn"
                      onClick={() => {
                        onUseItem(selectedItem);
                        setSelectedSlotIndex(null);
                        soundEngine.playHeal();
                      }}
                      className="w-full bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs py-2 rounded-lg transition"
                    >
                      Consume Item
                    </button>
                  )}

                  <button
                    onClick={() => {
                      if (selectedSlotIndex !== null) {
                        onDropItem(selectedSlotIndex);
                        setSelectedSlotIndex(null);
                      }
                    }}
                    className="w-full bg-slate-800 hover:bg-red-950/60 hover:text-red-400 text-slate-400 font-semibold text-xs py-1.5 rounded-lg border border-slate-700 transition"
                  >
                    Discard
                  </button>
                </div>
              </div>
            ) : equippedItem && selectedEquipSlot ? (
              <div className="space-y-3">
                <div className="border-b border-slate-800 pb-2">
                  <span className="text-[10px] uppercase font-bold text-amber-400">
                    Equipped {selectedEquipSlot}
                  </span>
                  <h3 className="font-fantasy font-bold text-sm text-slate-100">
                    {equippedItem.name}
                  </h3>
                </div>
                <p className="text-xs text-slate-300 italic">
                  "{equippedItem.description}"
                </p>
                <button
                  id="unequip-item-btn"
                  onClick={() => {
                    onUnequipItem(selectedEquipSlot);
                    setSelectedEquipSlot(null);
                    soundEngine.playHitImpact();
                  }}
                  className="w-full bg-slate-800 hover:bg-slate-700 text-amber-300 font-bold text-xs py-2 rounded-lg border border-slate-700 transition"
                >
                  Unequip to Bag
                </button>
              </div>
            ) : (
              <div className="h-full flex flex-col items-center justify-center text-center p-4">
                <Package className="w-8 h-8 text-slate-600 mb-2" />
                <p className="text-xs text-slate-400">
                  Select an item from your bag to inspect, equip, or consume.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
