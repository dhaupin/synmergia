import React, { useState } from 'react';
import { Item, PlayerCharacter } from '../types';
import { ITEMS_DATA as SHOP_ITEMS } from '../gameData';
import { Coins, ShoppingCart, DollarSign, Package } from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface ShopModalProps {
  isOpen: boolean;
  player: PlayerCharacter;
  onBuyItem: (item: Item) => void;
  onSellItem: (index: number) => void;
  onClose: () => void;
}

export const ShopModal: React.FC<ShopModalProps> = ({
  isOpen,
  player,
  onBuyItem,
  onSellItem,
  onClose,
}) => {
  const [tab, setTab] = useState<'buy' | 'sell'>('buy');

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="merchant-shop-modal"
        className="relative w-full max-w-2xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <ShoppingCart className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">
                Easthollow Provisions
              </h2>
              <p className="text-[11px] text-slate-400">
                Theron’s fine wares & adventurer requisitions
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
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

        {/* Tab switch */}
        <div className="flex gap-2 border-b border-slate-800 pb-3 mb-4">
          <button
            onClick={() => setTab('buy')}
            className={`px-4 py-1.5 rounded-lg text-xs font-bold font-fantasy transition ${
              tab === 'buy'
                ? 'bg-amber-600 text-slate-950 shadow'
                : 'bg-slate-800 text-slate-400 hover:text-slate-200'
            }`}
          >
            Buy Wares
          </button>
          <button
            onClick={() => setTab('sell')}
            className={`px-4 py-1.5 rounded-lg text-xs font-bold font-fantasy transition ${
              tab === 'sell'
                ? 'bg-amber-600 text-slate-950 shadow'
                : 'bg-slate-800 text-slate-400 hover:text-slate-200'
            }`}
          >
            Sell Treasures
          </button>
        </div>

        {tab === 'buy' ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {SHOP_ITEMS.map((item: Item) => {
              const canAfford = player.gold >= item.value;
              return (
                <div
                  key={item.id}
                  className="p-3.5 rounded-xl border border-slate-800 bg-slate-950/80 flex flex-col justify-between hover:border-slate-700 transition"
                >
                  <div className="mb-2">
                    <div className="flex items-center justify-between">
                      <span className="font-fantasy font-bold text-sm text-slate-100">
                        {item.name}
                      </span>
                      <span className="text-xs font-bold text-amber-400 flex items-center gap-1">
                        <Coins className="w-3.5 h-3.5" />
                        {item.value}g
                      </span>
                    </div>
                    <span className="text-[10px] text-slate-400 capitalize block mb-1">
                      {item.type} {item.slot ? `• ${item.slot}` : ''}
                    </span>
                    <p className="text-xs text-slate-300 line-clamp-2">
                      {item.description}
                    </p>
                  </div>

                  <button
                    onClick={() => {
                      if (canAfford) {
                        onBuyItem(item);
                        soundEngine.playCoins();
                      }
                    }}
                    disabled={!canAfford}
                    className={`w-full py-1.5 rounded-lg font-bold text-xs transition ${
                      canAfford
                        ? 'bg-amber-600 hover:bg-amber-500 text-slate-950'
                        : 'bg-slate-800 text-slate-500 cursor-not-allowed'
                    }`}
                  >
                    {canAfford ? 'Purchase' : 'Insufficient Gold'}
                  </button>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="space-y-2">
            {player.inventory.filter(Boolean).length === 0 ? (
              <div className="text-center p-6 text-xs text-slate-400">
                Your inventory satchel is empty.
              </div>
            ) : (
              player.inventory.map((item, index) => {
                if (!item) return null;
                const sellPrice = Math.max(1, Math.floor(item.value * 0.6));
                return (
                  <div
                    key={index}
                    className="p-2.5 rounded-xl border border-slate-800 bg-slate-950/80 flex items-center justify-between"
                  >
                    <div>
                      <span className="font-fantasy font-bold text-xs text-slate-100 block">
                        {item.name}
                      </span>
                      <span className="text-[10px] text-slate-400 capitalize">
                        {item.type} {item.quantity ? `(x${item.quantity})` : ''}
                      </span>
                    </div>
                    <div className="flex items-center gap-3">
                      <span className="text-xs font-bold text-amber-400 flex items-center gap-1">
                        <Coins className="w-3.5 h-3.5" />
                        +{sellPrice}g
                      </span>
                      <button
                        onClick={() => {
                          onSellItem(index);
                          soundEngine.playCoins();
                        }}
                        className="bg-slate-800 hover:bg-amber-600 hover:text-slate-950 text-slate-200 text-xs px-3 py-1 rounded-lg border border-slate-700 transition"
                      >
                        Sell
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        )}
      </div>
    </div>
  );
};
