import React, { useState } from 'react';
import { SpeciesId, ClassId } from '../types';
import { SPECIES_DATA, CLASS_DATA } from '../gameData';
import { User, Shield, Cpu, Swords, Sparkles, Crosshair, Zap, HeartHandshake, ShieldAlert } from 'lucide-react';
import { soundEngine } from '../soundEngine';

interface CharacterSelectModalProps {
  isOpen: boolean;
  onSelectCharacter: (name: string, species: SpeciesId, classId: ClassId) => void;
  onClose: () => void;
  canCancel?: boolean;
}

export const CharacterSelectModal: React.FC<CharacterSelectModalProps> = ({
  isOpen,
  onSelectCharacter,
  onClose,
  canCancel = false,
}) => {
  const [name, setName] = useState('Valerius');
  const [selectedSpecies, setSelectedSpecies] = useState<SpeciesId>('human');
  const [selectedClass, setSelectedClass] = useState<ClassId>('warrior');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    soundEngine.playLevelUp();
    onSelectCharacter(name.trim(), selectedSpecies, selectedClass);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
      <div
        id="character-creation-card"
        className="relative w-full max-w-2xl bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[90vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-5">
          <div>
            <h2 className="text-xl font-fantasy font-bold text-amber-300">
              Synmergia Character Archive
            </h2>
            <p className="text-xs text-slate-400">
              Forge your hero’s lineage and martial discipline
            </p>
          </div>
          {canCancel && (
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-slate-200 text-lg p-1"
            >
              ✕
            </button>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Character Name */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1.5 uppercase tracking-wider">
              Character Name
            </label>
            <input
              id="character-name-input"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={16}
              required
              className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3.5 py-2.5 text-sm text-slate-100 focus:outline-none focus:border-amber-500 transition"
              placeholder="Enter character name..."
            />
          </div>

          {/* 1. Species Selection */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-2 uppercase tracking-wider">
              Choose Species
            </label>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {(['human', 'akkan', 'synthetic'] as SpeciesId[]).map((speciesId) => {
                const spec = SPECIES_DATA[speciesId];
                const isSelected = selectedSpecies === speciesId;
                return (
                  <button
                    key={speciesId}
                    type="button"
                    onClick={() => {
                      setSelectedSpecies(speciesId);
                      soundEngine.playSpellCast();
                    }}
                    className={`p-3 rounded-xl border text-left transition relative flex flex-col justify-between ${
                      isSelected
                        ? 'border-amber-500 bg-amber-950/30 shadow-lg'
                        : 'border-slate-800 bg-slate-950/60 hover:border-slate-700 hover:bg-slate-800/50'
                    }`}
                  >
                    <div className="flex items-center gap-2 mb-2">
                      {speciesId === 'human' && <User className="w-5 h-5 text-blue-400" />}
                      {speciesId === 'akkan' && <Shield className="w-5 h-5 text-purple-400" />}
                      {speciesId === 'synthetic' && <Cpu className="w-5 h-5 text-cyan-400" />}
                      <span className="font-fantasy font-bold text-sm text-slate-100">
                        {spec.name}
                      </span>
                    </div>
                    <p className="text-[11px] text-slate-400 leading-relaxed mb-2">
                      {spec.description}
                    </p>
                    <div className="space-y-0.5">
                      {spec.bonuses.map((bonus: string, i: number) => (
                        <span
                          key={i}
                          className="block text-[10px] text-amber-300 font-medium"
                        >
                          • {bonus}
                        </span>
                      ))}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>

          {/* 2. Class Selection */}
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-2 uppercase tracking-wider">
              Choose Class & Archetype
            </label>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
              {(
                [
                  'warrior',
                  'guardian',
                  'sorcerer',
                  'cleric',
                  'stalker',
                  'overclocker',
                ] as ClassId[]
              ).map((clsId) => {
                const cls = CLASS_DATA[clsId];
                const isSelected = selectedClass === clsId;
                return (
                  <button
                    key={clsId}
                    type="button"
                    onClick={() => {
                      setSelectedClass(clsId);
                      soundEngine.playSwordSlash();
                    }}
                    className={`p-3 rounded-xl border text-left transition flex flex-col justify-between ${
                      isSelected
                        ? 'border-amber-500 bg-amber-950/30 shadow-md'
                        : 'border-slate-800 bg-slate-950/60 hover:border-slate-700 hover:bg-slate-800/40'
                    }`}
                  >
                    <div className="flex items-center gap-2 mb-1.5">
                      {clsId === 'warrior' && <Swords className="w-4 h-4 text-red-400" />}
                      {clsId === 'guardian' && <ShieldAlert className="w-4 h-4 text-yellow-400" />}
                      {clsId === 'sorcerer' && <Sparkles className="w-4 h-4 text-purple-400" />}
                      {clsId === 'cleric' && <HeartHandshake className="w-4 h-4 text-emerald-400" />}
                      {clsId === 'stalker' && <Crosshair className="w-4 h-4 text-orange-400" />}
                      {clsId === 'overclocker' && <Zap className="w-4 h-4 text-cyan-400" />}
                      <span className="font-fantasy font-bold text-xs text-slate-100">
                        {cls.name}
                      </span>
                    </div>
                    <span className="text-[10px] text-amber-400 font-semibold mb-1 block">
                      {cls.archetype}
                    </span>
                    <p className="text-[10px] text-slate-400 line-clamp-2">
                      {cls.description}
                    </p>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Submit Button */}
          <div className="pt-2">
            <button
              id="confirm-character-btn"
              type="submit"
              className="w-full bg-gradient-to-r from-amber-600 to-amber-500 hover:from-amber-500 hover:to-amber-400 text-slate-950 font-fantasy font-bold py-3 rounded-xl shadow-lg transition active:scale-[0.99]"
            >
              Enter The Realm of Synmergia
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
