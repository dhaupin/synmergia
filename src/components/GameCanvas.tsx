import React, { useRef, useEffect, useCallback } from 'react';
import { PlayerCharacter, Enemy, NPC, Zone, CombatText, Skill } from '../types';
import { soundEngine } from '../soundEngine';

interface GameCanvasProps {
  player: PlayerCharacter;
  enemies: Enemy[];
  npcs: NPC[];
  currentZone: Zone;
  combatTexts: CombatText[];
  selectedEnemy: Enemy | null;
  selectedNpc: NPC | null;
  onSelectEnemy: (enemy: Enemy | null) => void;
  onSelectNpc: (npc: NPC | null) => void;
  onMovePlayer: (dx: number, dy: number) => void;
  onPlayerClickMove: (targetX: number, targetY: number) => void;
  onUseSkill: (skill: Skill) => void;
  activeSkillCast: { skill: Skill; progress: number } | null;
  joystickVector?: { x: number; y: number } | null;
}

export const GameCanvas: React.FC<GameCanvasProps> = ({
  player,
  enemies,
  npcs,
  currentZone,
  combatTexts,
  selectedEnemy,
  selectedNpc,
  onSelectEnemy,
  onSelectNpc,
  onPlayerClickMove,
  joystickVector,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const animationFrameRef = useRef<number | null>(null);

  // Target destination for click-to-move
  const moveDestinationRef = useRef<{ x: number; y: number } | null>(null);

  // Sync canvas size with container
  useEffect(() => {
    const updateSize = () => {
      if (!canvasRef.current || !containerRef.current) return;
      const { width, height } = containerRef.current.getBoundingClientRect();
      canvasRef.current.width = width;
      canvasRef.current.height = height;
    };

    updateSize();
    const observer = new ResizeObserver(updateSize);
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }
    return () => observer.disconnect();
  }, []);

  // Handle keyboard movement
  useEffect(() => {
    const keysPressed: Record<string, boolean> = {};

    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't intercept if typing in chat
      if (
        document.activeElement?.tagName === 'INPUT' ||
        document.activeElement?.tagName === 'TEXTAREA'
      ) {
        return;
      }
      keysPressed[e.key.toLowerCase()] = true;
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      keysPressed[e.key.toLowerCase()] = false;
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    const moveInterval = setInterval(() => {
      let dx = 0;
      let dy = 0;

      if (keysPressed['w'] || keysPressed['arrowup']) dy -= 1;
      if (keysPressed['s'] || keysPressed['arrowdown']) dy += 1;
      if (keysPressed['a'] || keysPressed['arrowleft']) dx -= 1;
      if (keysPressed['d'] || keysPressed['arrowright']) dx += 1;

      // Also factor in virtual joystick if active
      if (joystickVector && (joystickVector.x !== 0 || joystickVector.y !== 0)) {
        dx = joystickVector.x;
        dy = joystickVector.y;
      }

      if (dx !== 0 || dy !== 0) {
        // Clear click destination on manual key press
        moveDestinationRef.current = null;
        const speed = 4.2;
        const length = Math.hypot(dx, dy) || 1;
        const normDx = (dx / length) * speed;
        const normDy = (dy / length) * speed;
        onPlayerClickMove(player.x + normDx, player.y + normDy);
      } else if (moveDestinationRef.current) {
        // Interpolate toward destination
        const dest = moveDestinationRef.current;
        const dist = Math.hypot(dest.x - player.x, dest.y - player.y);
        if (dist > 6) {
          const speed = 4.5;
          const stepX = ((dest.x - player.x) / dist) * speed;
          const stepY = ((dest.y - player.y) / dist) * speed;
          onPlayerClickMove(player.x + stepX, player.y + stepY);
        } else {
          moveDestinationRef.current = null;
        }
      }
    }, 20);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      clearInterval(moveInterval);
    };
  }, [player.x, player.y, onPlayerClickMove, joystickVector]);

  // Handle canvas click to select or move
  const handleCanvasClick = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (!canvasRef.current) return;
      const rect = canvasRef.current.getBoundingClientRect();
      const clickScreenX = e.clientX - rect.left;
      const clickScreenY = e.clientY - rect.top;

      // Transform screen coord to world coord based on player center
      const cameraX = player.x - canvasRef.current.width / 2;
      const cameraY = player.y - canvasRef.current.height / 2;
      const worldClickX = clickScreenX + cameraX;
      const worldClickY = clickScreenY + cameraY;

      // 1. Check if clicked an enemy
      for (const enemy of enemies) {
        if (enemy.hp <= 0) continue;
        const dist = Math.hypot(enemy.x - worldClickX, enemy.y - worldClickY);
        if (dist < 30) {
          onSelectEnemy(enemy);
          onSelectNpc(null);
          soundEngine.playHitImpact();
          return;
        }
      }

      // 2. Check if clicked an NPC
      for (const npc of npcs) {
        const dist = Math.hypot(npc.x - worldClickX, npc.y - worldClickY);
        if (dist < 32) {
          onSelectNpc(npc);
          onSelectEnemy(null);
          soundEngine.playQuestComplete();
          return;
        }
      }

      // 3. Move destination
      moveDestinationRef.current = {
        x: Math.max(30, Math.min(currentZone.width - 30, worldClickX)),
        y: Math.max(30, Math.min(currentZone.height - 30, worldClickY)),
      };
    },
    [player.x, player.y, enemies, npcs, currentZone, onSelectEnemy, onSelectNpc]
  );

  // Main Render Loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let time = 0;

    const render = () => {
      time += 0.03;
      const width = canvas.width;
      const height = canvas.height;

      // Camera centered on player
      const cameraX = player.x - width / 2;
      const cameraY = player.y - height / 2;

      // Clear screen with zone background
      ctx.fillStyle = currentZone.bgColor;
      ctx.fillRect(0, 0, width, height);

      ctx.save();
      ctx.translate(-cameraX, -cameraY);

      // --- 1. Draw World Grid & Terrain ---
      const tileSize = 60;
      const startCol = Math.floor(cameraX / tileSize);
      const endCol = Math.ceil((cameraX + width) / tileSize);
      const startRow = Math.floor(cameraY / tileSize);
      const endRow = Math.ceil((cameraY + height) / tileSize);

      for (let c = startCol; c <= endCol; c++) {
        for (let r = startRow; r <= endRow; r++) {
          const tileX = c * tileSize;
          const tileY = r * tileSize;

          // Zone-specific tile variations
          if (currentZone.id === 'zone_village_center') {
            // Cobblestone town plaza
            const isPath = (c + r) % 2 === 0;
            ctx.fillStyle = isPath ? '#1e293b' : '#0f172a';
            ctx.fillRect(tileX, tileY, tileSize - 1, tileSize - 1);
          } else if (currentZone.id === 'zone_starter_plains') {
            // Rolling grass with flora spots
            const isEven = (c * 7 + r * 13) % 5 === 0;
            ctx.fillStyle = isEven ? '#14532d' : '#166534';
            ctx.fillRect(tileX, tileY, tileSize, tileSize);
          } else if (currentZone.id === 'zone_forest_meadow') {
            // Dark mystical woods
            const isDark = (c + r) % 3 === 0;
            ctx.fillStyle = isDark ? '#142a1f' : '#0d1f16';
            ctx.fillRect(tileX, tileY, tileSize, tileSize);
          } else if (currentZone.id === 'zone_dungeon_forest_depths') {
            // Void dungeon cavern stone
            const isVoid = (c * 3 + r * 5) % 4 === 0;
            ctx.fillStyle = isVoid ? '#231433' : '#170c24';
            ctx.fillRect(tileX, tileY, tileSize - 1, tileSize - 1);
          } else {
            // Akkan volcanic crags
            const isLava = (c + r) % 4 === 0;
            ctx.fillStyle = isLava ? '#3b1010' : '#220808';
            ctx.fillRect(tileX, tileY, tileSize, tileSize);
          }
        }
      }

      // Draw Zone Boundaries
      ctx.strokeStyle = currentZone.ambientColor;
      ctx.lineWidth = 3;
      ctx.strokeRect(0, 0, currentZone.width, currentZone.height);

      // --- 2. Draw Gateways / Portals ---
      currentZone.gateways.forEach((gw) => {
        const pulse = Math.sin(time * 3) * 6;
        ctx.save();
        ctx.beginPath();
        ctx.arc(gw.x, gw.y, 28 + pulse, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(56, 189, 248, 0.15)';
        ctx.fill();
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 3;
        ctx.stroke();

        // Inner glowing core
        ctx.beginPath();
        ctx.arc(gw.x, gw.y, 14, 0, Math.PI * 2);
        ctx.fillStyle = '#bae6fd';
        ctx.fill();

        // Gateway Label
        ctx.fillStyle = '#e0f2fe';
        ctx.font = 'bold 12px Plus Jakarta Sans, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(gw.name, gw.x, gw.y - 36);
        ctx.restore();
      });

      // --- 3. Draw Click Destination Marker ---
      if (moveDestinationRef.current) {
        ctx.save();
        const dest = moveDestinationRef.current;
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 2;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.arc(dest.x, dest.y, 12, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }

      // --- 4. Draw NPCs ---
      npcs.forEach((npc) => {
        const isSelected = selectedNpc?.id === npc.id;

        // Selection ring
        if (isSelected) {
          ctx.save();
          ctx.strokeStyle = '#facc15';
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(npc.x, npc.y, 24, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }

        // Shadow
        ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
        ctx.beginPath();
        ctx.ellipse(npc.x, npc.y + 16, 16, 6, 0, 0, Math.PI * 2);
        ctx.fill();

        // NPC Body
        ctx.fillStyle =
          npc.role === 'elder'
            ? '#38bdf8'
            : npc.role === 'blacksmith'
            ? '#f97316'
            : '#a855f7';
        ctx.beginPath();
        ctx.arc(npc.x, npc.y, 16, 0, Math.PI * 2);
        ctx.fill();

        // Quest marker above head (! or ?)
        if (npc.questIds.length > 0) {
          const bounce = Math.sin(time * 4) * 3;
          ctx.fillStyle = '#facc15';
          ctx.font = 'bold 18px Cinzel, serif';
          ctx.textAlign = 'center';
          ctx.fillText('!', npc.x, npc.y - 28 + bounce);
        }

        // Name & Title tag
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 11px Plus Jakarta Sans, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(npc.name, npc.x, npc.y - 18);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '9px Plus Jakarta Sans, sans-serif';
        ctx.fillText(`<${npc.title}>`, npc.x, npc.y + 28);
      });

      // --- 5. Draw Enemies ---
      enemies.forEach((enemy) => {
        if (enemy.hp <= 0) return;

        const isSelected = selectedEnemy?.id === enemy.id;

        // Aggro / Chase aura
        if (enemy.state === 'chase' || enemy.state === 'attack') {
          ctx.save();
          ctx.strokeStyle = 'rgba(239, 68, 68, 0.6)';
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.arc(enemy.x, enemy.y, 22 + Math.sin(time * 6) * 3, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }

        // Selected Target Ring
        if (isSelected) {
          ctx.save();
          ctx.strokeStyle = '#ef4444';
          ctx.lineWidth = 2.5;
          ctx.beginPath();
          ctx.arc(enemy.x, enemy.y, 26, 0, Math.PI * 2);
          ctx.stroke();
          ctx.restore();
        }

        // Shadow
        ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
        ctx.beginPath();
        ctx.ellipse(enemy.x, enemy.y + 16, 18, 7, 0, 0, Math.PI * 2);
        ctx.fill();

        // Enemy Body
        ctx.save();
        if (enemy.isBoss) {
          ctx.fillStyle = '#831843'; // Deep crimson boss
        } else if (enemy.isElite) {
          ctx.fillStyle = '#7c2d12'; // Amber elite
        } else if (enemy.templateId === 'wolf') {
          ctx.fillStyle = '#475569'; // Slate wolf
        } else if (enemy.templateId === 'slime') {
          ctx.fillStyle = '#10b981'; // Green slime
        } else {
          ctx.fillStyle = '#b91c1c'; // Red bandit
        }

        const size = enemy.isBoss ? 24 : enemy.isElite ? 18 : 14;
        ctx.beginPath();
        ctx.arc(enemy.x, enemy.y, size, 0, Math.PI * 2);
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = enemy.isBoss ? '#facc15' : '#1e293b';
        ctx.stroke();
        ctx.restore();

        // Boss Crown
        if (enemy.isBoss) {
          ctx.fillStyle = '#facc15';
          ctx.font = 'bold 16px Cinzel';
          ctx.textAlign = 'center';
          ctx.fillText('👑', enemy.x, enemy.y - size - 14);
        }

        // Enemy Health Bar
        const barWidth = size * 2.4;
        const barHeight = 4;
        const healthPercent = Math.max(0, enemy.hp / enemy.maxHp);
        ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
        ctx.fillRect(enemy.x - barWidth / 2, enemy.y - size - 8, barWidth, barHeight);
        ctx.fillStyle = enemy.isBoss ? '#f43f5e' : '#ef4444';
        ctx.fillRect(enemy.x - barWidth / 2, enemy.y - size - 8, barWidth * healthPercent, barHeight);

        // Name & Level
        ctx.fillStyle = enemy.isBoss ? '#facc15' : '#f87171';
        ctx.font = 'bold 10px Plus Jakarta Sans, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(`Lv.${enemy.level} ${enemy.name}`, enemy.x, enemy.y - size - 12);
      });

      // --- 6. Draw Player Character ---
      ctx.save();

      // Active Buff Auras
      if (player.activeBuffs.length > 0) {
        ctx.save();
        ctx.strokeStyle = 'rgba(56, 189, 248, 0.5)';
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 6]);
        ctx.beginPath();
        ctx.arc(player.x, player.y, 26 + Math.sin(time * 3) * 2, 0, Math.PI * 2);
        ctx.stroke();
        ctx.restore();
      }

      // Shadow
      ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
      ctx.beginPath();
      ctx.ellipse(player.x, player.y + 18, 20, 8, 0, 0, Math.PI * 2);
      ctx.fill();

      // Species Color Styling
      let speciesColor = '#3b82f6';
      if (player.species === 'akkan') speciesColor = '#a855f7';
      if (player.species === 'synthetic') speciesColor = '#06b6d4';

      // Player Body
      ctx.fillStyle = speciesColor;
      ctx.beginPath();
      ctx.arc(player.x, player.y, 16, 0, Math.PI * 2);
      ctx.fill();
      ctx.lineWidth = 2.5;
      ctx.strokeStyle = '#ffffff';
      ctx.stroke();

      // Class Weapon Glow / Ornament
      ctx.fillStyle = '#facc15';
      ctx.beginPath();
      ctx.arc(player.x + 10, player.y - 6, 5, 0, Math.PI * 2);
      ctx.fill();

      // Player Name & Title
      ctx.fillStyle = '#ffffff';
      ctx.font = 'bold 12px Cinzel, serif';
      ctx.textAlign = 'center';
      ctx.fillText(`Lv.${player.level} ${player.name}`, player.x, player.y - 24);

      // Player Mini HP Bar
      const playerBarWidth = 40;
      const playerHpPercent = Math.max(0, player.hp / player.maxHp);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
      ctx.fillRect(player.x - playerBarWidth / 2, player.y - 20, playerBarWidth, 4);
      ctx.fillStyle = '#22c55e';
      ctx.fillRect(player.x - playerBarWidth / 2, player.y - 20, playerBarWidth * playerHpPercent, 4);

      ctx.restore();

      // --- 7. Draw Floating Combat Text ---
      const now = Date.now();
      combatTexts.forEach((ct) => {
        const age = (now - ct.createdAt) / 1000;
        if (age > 1.2) return;

        const alpha = Math.max(0, 1 - age / 1.2);
        const floatY = ct.y - age * 40;

        ctx.save();
        ctx.globalAlpha = alpha;
        ctx.fillStyle = ct.color;
        ctx.font = ct.type === 'crit' ? 'bold 16px Cinzel' : 'bold 13px Plus Jakarta Sans';
        ctx.textAlign = 'center';
        ctx.fillText(ct.text, ct.x, floatY);
        ctx.restore();
      });

      ctx.restore();

      animationFrameRef.current = requestAnimationFrame(render);
    };

    animationFrameRef.current = requestAnimationFrame(render);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, [
    player,
    enemies,
    npcs,
    currentZone,
    combatTexts,
    selectedEnemy,
    selectedNpc,
  ]);

  return (
    <div
      ref={containerRef}
      id="game-canvas-container"
      className="relative w-full h-full overflow-hidden bg-slate-950 cursor-crosshair"
    >
      <canvas
        ref={canvasRef}
        id="synmergia-canvas"
        onClick={handleCanvasClick}
        className="block w-full h-full"
      />
    </div>
  );
};
