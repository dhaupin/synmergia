import React from 'react';
import { PlayerCharacter, Quest } from '../types';
import { QUESTS_DATA } from '../gameData';
import { ScrollText, CheckCircle2, Award, Coins, Sparkles } from 'lucide-react';

interface QuestModalProps {
  isOpen: boolean;
  player: PlayerCharacter;
  onClose: () => void;
  onCompleteQuest?: (questId: string) => void;
}

export const QuestModal: React.FC<QuestModalProps> = ({
  isOpen,
  player,
  onClose,
  onCompleteQuest,
}) => {
  if (!isOpen) return null;

  const activeQuestDetails = player.activeQuests
    .map((aq) => ({
      quest: QUESTS_DATA[aq.questId],
      progress: aq.progress,
    }))
    .filter((q) => Boolean(q.quest));

  const completedQuestDetails = player.completedQuests
    .map((cqId) => QUESTS_DATA[cqId])
    .filter(Boolean);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="quest-log-modal"
        className="relative w-full max-w-xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <ScrollText className="w-5 h-5 text-amber-400" />
            <h2 className="text-lg font-fantasy font-bold text-slate-100">
              Synmergia Quest Chronicle
            </h2>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-200 text-lg p-1"
          >
            ✕
          </button>
        </div>

        <div className="space-y-4">
          {/* Active Quests */}
          <div>
            <h3 className="text-xs font-fantasy font-bold text-amber-400 uppercase tracking-wider mb-2.5">
              Active Objectives ({activeQuestDetails.length})
            </h3>

            {activeQuestDetails.length === 0 ? (
              <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 text-center text-xs text-slate-400">
                No active quests. Speak to Elder Garrick or Theron in Easthollow Village.
              </div>
            ) : (
              <div className="space-y-3">
                {activeQuestDetails.map(({ quest, progress }) => {
                  const isReadyToTurnIn = progress >= quest.requiredCount;

                  return (
                    <div
                      key={quest.id}
                      className={`p-4 rounded-xl border transition ${
                        isReadyToTurnIn
                          ? 'border-emerald-500 bg-emerald-950/20'
                          : 'border-slate-800 bg-slate-950/80'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-1.5">
                        <h4 className="font-fantasy font-bold text-sm text-slate-100">
                          {quest.title}
                        </h4>
                        <span
                          className={`text-[10px] font-bold px-2 py-0.5 rounded ${
                            isReadyToTurnIn
                              ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40'
                              : 'bg-sky-500/20 text-sky-300'
                          }`}
                        >
                          {isReadyToTurnIn ? 'Ready to Complete' : 'In Progress'}
                        </span>
                      </div>

                      <p className="text-xs text-slate-300 mb-3 leading-relaxed">
                        {quest.description}
                      </p>

                      {/* Progress Bar */}
                      <div className="space-y-1 mb-3">
                        <div className="flex justify-between text-[11px] text-slate-400">
                          <span>
                            Objective: {quest.targetType === 'kill' ? 'Defeat' : 'Gather'}{' '}
                            {quest.targetName}
                          </span>
                          <span className="font-bold text-slate-200">
                            {progress} / {quest.requiredCount}
                          </span>
                        </div>
                        <div className="w-full h-2 bg-slate-900 rounded-full overflow-hidden border border-slate-800">
                          <div
                            className={`h-full transition-all ${
                              isReadyToTurnIn ? 'bg-emerald-400' : 'bg-sky-400'
                            }`}
                            style={{
                              width: `${Math.min(
                                100,
                                (progress / quest.requiredCount) * 100
                              )}%`,
                            }}
                          />
                        </div>
                      </div>

                      {/* Rewards Strip */}
                      <div className="pt-2 border-t border-slate-800/80 flex items-center justify-between">
                        <div className="flex items-center gap-3 text-xs">
                          <span className="flex items-center gap-1 text-sky-400">
                            <Sparkles className="w-3.5 h-3.5" />
                            {quest.rewards.xp} XP
                          </span>
                          <span className="flex items-center gap-1 text-amber-400">
                            <Coins className="w-3.5 h-3.5" />
                            {quest.rewards.gold} Gold
                          </span>
                        </div>

                        {isReadyToTurnIn && onCompleteQuest && (
                          <button
                            onClick={() => onCompleteQuest(quest.id)}
                            className="bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs px-3 py-1.5 rounded-lg transition"
                          >
                            Claim Reward
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Completed Quests */}
          {completedQuestDetails.length > 0 && (
            <div className="pt-3 border-t border-slate-800">
              <h3 className="text-xs font-fantasy font-bold text-slate-400 uppercase tracking-wider mb-2">
                Completed Chronicles ({completedQuestDetails.length})
              </h3>
              <div className="space-y-1.5">
                {completedQuestDetails.map((quest) => (
                  <div
                    key={quest.id}
                    className="flex items-center justify-between p-2 rounded-lg bg-slate-950/40 border border-slate-800/60 text-xs"
                  >
                    <span className="text-slate-300 font-medium flex items-center gap-1.5">
                      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                      {quest.title}
                    </span>
                    <span className="text-slate-500 text-[10px]">Accomplished</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
