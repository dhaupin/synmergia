import React, { useState, useRef, useEffect } from 'react';
import { ChatMessage } from '../types';
import { MessageSquare, Send, ChevronDown, ChevronUp } from 'lucide-react';

interface ChatBoxProps {
  messages: ChatMessage[];
  onSendMessage: (text: string) => void;
  playerLevel: number;
}

export const ChatBox: React.FC<ChatBoxProps> = ({
  messages,
  onSendMessage,
  playerLevel,
}) => {
  const [inputText, setInputText] = useState('');
  const [activeChannel, setActiveChannel] = useState<'all' | 'global' | 'system' | 'combat'>('all');
  const [isCollapsed, setIsCollapsed] = useState(false);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isCollapsed]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputText.trim()) return;
    onSendMessage(inputText.trim());
    setInputText('');
  };

  const filteredMessages = messages.filter((msg) => {
    if (activeChannel === 'all') return true;
    return msg.channel === activeChannel;
  });

  return (
    <div
      id="chat-box-container"
      className="absolute bottom-16 left-3 sm:bottom-4 sm:left-4 z-20 w-80 sm:w-96 bg-slate-950/90 border border-slate-800/90 rounded-xl shadow-2xl backdrop-blur-md flex flex-col transition-all duration-200"
    >
      {/* Header with channel tabs and collapse toggle */}
      <div className="flex items-center justify-between px-2.5 py-1.5 border-b border-slate-800 text-[11px]">
        <div className="flex items-center gap-1 font-fantasy">
          {(['all', 'global', 'system', 'combat'] as const).map((ch) => (
            <button
              key={ch}
              onClick={() => setActiveChannel(ch)}
              className={`px-2 py-0.5 rounded capitalize transition ${
                activeChannel === ch
                  ? 'bg-slate-800 text-amber-300 font-bold'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {ch}
            </button>
          ))}
        </div>

        <button
          onClick={() => setIsCollapsed(!isCollapsed)}
          className="text-slate-400 hover:text-slate-200 p-0.5"
          title={isCollapsed ? 'Expand Chat' : 'Collapse Chat'}
        >
          {isCollapsed ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
        </button>
      </div>

      {!isCollapsed && (
        <>
          {/* Message List */}
          <div
            ref={scrollRef}
            className="h-36 sm:h-44 overflow-y-auto p-2.5 space-y-1.5 text-xs font-sans leading-relaxed"
          >
            {filteredMessages.map((msg) => {
              let tagColor = 'text-sky-400';
              if (msg.channel === 'combat') tagColor = 'text-red-400';
              if (msg.channel === 'system') tagColor = 'text-amber-400';
              if (msg.channel === 'party') tagColor = 'text-emerald-400';

              return (
                <div key={msg.id} className="break-words">
                  <span className={`font-bold text-[10px] uppercase mr-1.5 ${tagColor}`}>
                    [{msg.channel}]
                  </span>
                  {msg.sender && (
                    <span className="font-semibold text-slate-300 mr-1.5">
                      {msg.sender}:
                    </span>
                  )}
                  <span
                    className={
                      msg.channel === 'combat'
                        ? 'text-red-200/90 font-mono text-[11px]'
                        : msg.channel === 'system'
                        ? 'text-amber-200'
                        : 'text-slate-200'
                    }
                  >
                    {msg.text}
                  </span>
                </div>
              );
            })}
          </div>

          {/* Input Form */}
          <form
            onSubmit={handleSubmit}
            className="flex items-center gap-1.5 p-1.5 border-t border-slate-800"
          >
            <input
              id="chat-input"
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder="Press Enter to chat or type /help..."
              maxLength={120}
              className="flex-1 bg-slate-900 border border-slate-700/80 rounded-lg px-2.5 py-1 text-xs text-slate-100 placeholder:text-slate-500 focus:outline-none focus:border-amber-500"
            />
            <button
              id="send-chat-btn"
              type="submit"
              className="p-1.5 bg-amber-600 hover:bg-amber-500 text-slate-950 rounded-lg transition"
            >
              <Send className="w-3.5 h-3.5" />
            </button>
          </form>
        </>
      )}
    </div>
  );
};
