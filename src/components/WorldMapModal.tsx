import React from 'react';
import { Zone } from '../types';
import { ZONES_DATA } from '../gameData';
import { MapPin, Navigation, Compass, ShieldAlert } from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface WorldMapModalProps {
  isOpen: boolean;
  currentZoneId: string;
  onTeleportToZone: (zoneId: string) => void;
  onClose: () => void;
}

export const WorldMapModal: React.FC<WorldMapModalProps> = ({
  isOpen,
  currentZoneId,
  onTeleportToZone,
  onClose,
}) => {
  if (!isOpen) return null;

  const zonesList = Object.values(ZONES_DATA);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div
        id="world-map-modal"
        className="relative w-full max-w-3xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[90vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-5">
          <div className="flex items-center gap-2.5">
            <Compass className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">
                Continent of Synmergia
              </h2>
              <p className="text-[11px] text-slate-400">
                Waypoint nexus & territory atlas
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

        {/* Map Visualization Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5 mb-4">
          {zonesList.map((zone) => {
            const isCurrent = zone.id === currentZoneId;

            return (
              <div
                key={zone.id}
                className={`relative p-4 rounded-xl border transition flex flex-col justify-between ${
                  isCurrent
                    ? 'border-amber-500 bg-amber-950/25 shadow-lg ring-1 ring-amber-500/50'
                    : 'border-slate-800 bg-slate-950/80 hover:border-slate-700'
                }`}
              >
                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <span className="font-fantasy font-bold text-sm text-slate-100 flex items-center gap-1.5">
                      <MapPin
                        className={`w-4 h-4 ${
                          isCurrent ? 'text-amber-400 fill-amber-400' : 'text-slate-400'
                        }`}
                      />
                      {zone.name}
                    </span>
                    <span
                      className={`text-[9px] font-bold uppercase px-1.5 py-0.5 rounded ${
                        zone.pvpMode === 'safe'
                          ? 'bg-emerald-950 text-emerald-400 border border-emerald-800'
                          : zone.pvpMode === 'contested'
                          ? 'bg-amber-950 text-amber-400 border border-amber-800'
                          : 'bg-red-950 text-red-400 border border-red-800'
                      }`}
                    >
                      {zone.pvpMode}
                    </span>
                  </div>

                  <span className="text-[11px] font-semibold text-amber-300 block mb-1">
                    {zone.levelRange} • {zone.subtitle}
                  </span>

                  <p className="text-xs text-slate-400 line-clamp-2 mb-3">
                    {zone.description}
                  </p>
                </div>

                <div className="pt-2 border-t border-slate-800/80 flex items-center justify-between">
                  {isCurrent ? (
                    <span className="text-xs font-bold text-amber-400 flex items-center gap-1">
                      Current Location
                    </span>
                  ) : (
                    <button
                      onClick={() => {
                        onTeleportToZone(zone.id);
                        soundEngine.playSpellCast();
                      }}
                      className="bg-sky-600 hover:bg-sky-500 text-white font-bold text-xs px-3.5 py-1.5 rounded-lg flex items-center gap-1.5 transition"
                    >
                      <Navigation className="w-3.5 h-3.5" />
                      Travel to Waypoint
                    </button>
                  )}
                  <span className="text-[10px] text-slate-500">
                    {zone.gateways.length} Outbound Portals
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
