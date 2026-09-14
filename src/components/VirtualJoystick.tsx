import React, { useRef, useState, useEffect } from 'react';

interface VirtualJoystickProps {
  onMove: (vector: { x: number; y: number } | null) => void;
}

export const VirtualJoystick: React.FC<VirtualJoystickProps> = ({ onMove }) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [touchPos, setTouchPos] = useState<{ x: number; y: number } | null>(null);
  const [isTouchDevice, setIsTouchDevice] = useState(false);

  useEffect(() => {
    if ('ontouchstart' in window || navigator.maxTouchPoints > 0) {
      setIsTouchDevice(true);
    }
  }, []);

  if (!isTouchDevice) return null;

  const handleTouchStart = (e: React.TouchEvent) => {
    handleTouchMove(e);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!containerRef.current) return;
    const touch = e.touches[0];
    const rect = containerRef.current.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;

    const dx = touch.clientX - centerX;
    const dy = touch.clientY - centerY;
    const distance = Math.hypot(dx, dy);
    const maxRadius = 45;

    const clampedDist = Math.min(distance, maxRadius);
    const angle = Math.atan2(dy, dx);
    const clampedX = Math.cos(angle) * clampedDist;
    const clampedY = Math.sin(angle) * clampedDist;

    setTouchPos({ x: clampedX, y: clampedY });
    onMove({
      x: clampedDist > 5 ? clampedX / maxRadius : 0,
      y: clampedDist > 5 ? clampedY / maxRadius : 0,
    });
  };

  const handleTouchEnd = () => {
    setTouchPos(null);
    onMove(null);
  };

  return (
    <div
      ref={containerRef}
      id="virtual-joystick"
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      onTouchCancel={handleTouchEnd}
      className="absolute bottom-24 right-6 z-30 w-28 h-28 rounded-full bg-slate-900/60 border-2 border-slate-700/70 backdrop-blur-sm flex items-center justify-center select-none touch-none"
    >
      <div
        className="w-12 h-12 rounded-full bg-amber-500/80 border-2 border-white shadow-lg pointer-events-none transition-transform duration-75"
        style={{
          transform: touchPos
            ? `translate(${touchPos.x}px, ${touchPos.y}px)`
            : 'translate(0px, 0px)',
        }}
      />
    </div>
  );
};
