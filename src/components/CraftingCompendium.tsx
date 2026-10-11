import React, { useMemo, useState } from 'react';
import { Anvil, CupSoda, Flame, Hammer, Hand, Timer, Wrench } from 'lucide-react';
import { RAW } from '../data/loadGodotData';

interface CraftingCompendiumProps {
  isOpen: boolean;
  onClose: () => void;
}

// Mirrors RecipeData.Station order (core/schemas/recipe_data.gd).
const STATIONS: Record<number, string> = {
  0: 'Hand craft (anywhere)',
  1: 'The Forge',
  2: 'The Workbench',
  3: 'The Cauldron',
};

const STATION_ICONS: Record<number, React.ComponentType<{ className?: string }>> = {
  0: Hand,
  1: Flame,
  2: Hammer,
  3: CupSoda,
};

// Item display names come from the SAME sync payload (resources/items),
// so the recipe browser never invents an id it cannot cite.
function itemName(id: string): string {
  const fromResources = RAW.resources?.[id];
  if (fromResources?.display_name) return fromResources.display_name;
  const fromWeapons = RAW.weapons?.[id];
  if (fromWeapons?.display_name) return fromWeapons.display_name;
  const fromArmors = RAW.armors?.[id];
  if (fromArmors?.display_name) return fromArmors.display_name;
  const fromConsumables = RAW.consumables?.[id];
  if (fromConsumables?.display_name) return fromConsumables.display_name;
  const fromItems = RAW.items?.[id];
  if (fromItems?.display_name) return fromItems.display_name;
  return id;
}

export const CraftingCompendium: React.FC<CraftingCompendiumProps> = ({ isOpen, onClose }) => {
  const [stationFilter, setStationFilter] = useState<number | null>(null);

  const recipes = useMemo(() => {
    if (!isOpen) return [];
    return Object.entries(RAW.recipes || {})
      .map(([, r]: [string, any]) => r as any)
      .filter((r) => r?.id)
      .sort((a, b) => (a.display_name || a.id).localeCompare(b.display_name || b.id));
  }, [isOpen]);

  const visible = useMemo(
    () => (stationFilter === null ? recipes : recipes.filter((r) => Number(r.station) === stationFilter)),
    [recipes, stationFilter]
  );

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="crafting-compendium"
        className="relative w-full max-w-2xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <Anvil className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">The Crafting Codex</h2>
              <p className="text-[11px] text-slate-400">
                Every lawful bill &mdash; straight from the game's own recipe data ({recipes.length} recipes)
              </p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-200 text-lg p-1" aria-label="Close crafting codex">
            ✕
          </button>
        </div>

        {/* Station filter */}
        <div className="flex flex-wrap gap-1.5 mb-4">
          <button
            onClick={() => setStationFilter(null)}
            className={`px-2.5 py-1 rounded-lg text-xs font-semibold border transition-colors ${
              stationFilter === null
                ? 'bg-amber-500/20 text-amber-300 border-amber-500/40'
                : 'bg-slate-950/60 text-slate-400 border-slate-700 hover:text-slate-200'
            }`}
          >
            All stations
          </button>
          {Object.entries(STATIONS).map(([num, label]) => {
            const n = Number(num);
            const Icon = STATION_ICONS[n] ?? Wrench;
            const active = stationFilter === n;
            return (
              <button
                key={num}
                onClick={() => setStationFilter(active ? null : n)}
                className={`flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-semibold border transition-colors ${
                  active
                    ? 'bg-amber-500/20 text-amber-300 border-amber-500/40'
                    : 'bg-slate-950/60 text-slate-400 border-slate-700 hover:text-slate-200'
                }`}
              >
                <Icon className="w-3 h-3" />
                {label}
              </button>
            );
          })}
        </div>

        {/* Recipe cards */}
        <div className="space-y-3">
          {visible.length === 0 && (
            <p className="text-sm text-slate-500 italic py-6 text-center">
              No recipes at this station yet — the reclaim is still young.
            </p>
          )}
          {visible.map((r) => {
            const station = Number(r.station ?? 0);
            const Icon = STATION_ICONS[station] ?? Wrench;
            const failureRate = Number(r.failure_rate ?? 0);
            const inputs: Array<{ item_id: string; qty: number }> = Array.isArray(r.inputs) ? r.inputs : [];
            const out = r.output?.item_id ? r.output : null;
            const bynames: Array<string> = Array.isArray(r.byproducts)
              ? r.byproducts.map((b: any) => itemName(b.item_id))
              : [];
            return (
              <div key={r.id} className="bg-slate-950/70 border border-slate-800 rounded-xl p-4">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Icon className="w-4 h-4 text-amber-400" />
                    <span className="font-bold text-slate-100">{r.display_name || r.id}</span>
                  </div>
                  <span className="text-[10px] uppercase tracking-wider text-slate-500 bg-slate-900 px-2 py-0.5 rounded border border-slate-800">
                    {STATIONS[station] ?? 'Anywhere'}
                  </span>
                </div>

                {r.description && (
                  <p className="text-xs text-slate-400 italic mb-3">{r.description}</p>
                )}

                <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 text-sm">
                  {/* Bill (inputs) */}
                  <div className="space-y-1">
                    {inputs.map((inp) => (
                      <div key={inp.item_id} className="flex justify-between bg-slate-900/80 rounded px-2 py-1 border border-slate-800">
                        <span className="text-slate-300">{itemName(inp.item_id)}</span>
                        <span className="text-slate-500 font-mono text-xs">×{inp.qty}</span>
                      </div>
                    ))}
                  </div>

                  {/* Arrow */}
                  <div className="text-amber-500/70 font-bold text-lg px-1">→</div>

                  {/* Output */}
                  <div className="space-y-1">
                    {out && (
                      <div className="flex justify-between bg-amber-500/10 rounded px-2 py-1 border border-amber-600/30">
                        <span className="text-amber-200">{itemName(out.item_id)}</span>
                        <span className="text-amber-300/70 font-mono text-xs">×{out.qty ?? 1}</span>
                      </div>
                    )}
                    {bynames.length > 0 && (
                      <div className="flex justify-between bg-slate-900/80 rounded px-2 py-1 border border-slate-800">
                        <span className="text-slate-500 text-xs">{bynames.join(', ')}</span>
                        <span className="text-slate-600 font-mono text-[10px]">yield</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Posture line */}
                <div className="flex items-center gap-3 mt-3 text-[11px] text-slate-500">
                  {failureRate > 0 ? (
                    <span className="text-rose-400/80 flex items-center gap-1">
                      <Timer className="w-3 h-3" /> {Math.round(failureRate * 100)}% failure
                    </span>
                  ) : (
                    <span className="text-emerald-500/70">never fails</span>
                  )}
                  {Number(r.craft_time_sec) > 0 && (
                    <span className="text-sky-400/70 flex items-center gap-1">
                      <Timer className="w-3 h-3" /> {Number(r.craft_time_sec)}s forge
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
