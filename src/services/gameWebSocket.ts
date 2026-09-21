/**
 * Synmergia Game WebSocket Client
 *
 * A lightweight, JSON-framed WebSocket client for real-time server sync.
 * Connects to the Godot NetworkManager (WebSocketMultiplayerPeer) through
 * the `/ws` endpoint exposed by nginx and proxied by the Cloudflare worker.
 *
 * Protocol: every frame is a JSON object of shape:
 *   { type: WSMessageType, payload: any, timestamp: number, seq?: number }
 *
 * Not a replacement for the Godot binary multiplayer protocol; this is the
 * typed, JSON-only path used by the React companion client.
 */

export type WSMessageType =
  | 'auth' // { token, playerId }
  | 'player_state' // { x, y, hp, mp, stamina, zone }
  | 'entity_update' // { entities: [...] }
  | 'combat_event' // { type: 'damage' | 'heal' | 'cast', ... }
  | 'chat' // { channel, sender, text }
  | 'zone_change' // { zoneId, x, y }
  | 'achievement_unlocked' // { achievementId | id, title, playerId }
  | 'ping'
  | 'pong';

export interface WSMessage<T = any> {
  type: WSMessageType;
  payload: T;
  timestamp: number;
  seq?: number;
}

export interface AuthPayload {
  token: string;
  playerId: string;
}

export interface PlayerStatePayload {
  x: number;
  y: number;
  hp: number;
  mp: number;
  stamina: number;
  zone: string;
}

export interface EntityUpdatePayload {
  entities: unknown[];
}

export interface CombatEventPayload {
  type: 'damage' | 'heal' | 'cast';
  attackerId?: string;
  targetId?: string;
  amount?: number;
  skillId?: string;
}

export interface ChatPayload {
  channel: string;
  sender: string;
  text: string;
}

export interface ZoneChangePayload {
  zoneId: string;
  x: number;
  y: number;
}

type Handler<T> = (msg: WSMessage<T>) => void;

const PING_INTERVAL_MS = 30_000;
const PONG_TIMEOUT_MS = 10_000;
const BASE_RECONNECT_MS = 1000;
const MAX_RECONNECT_ATTEMPTS = 5;

export class GameWebSocket {
  private ws: WebSocket | null = null;
  private url: string;
  private reconnectAttempts = 0;
  private maxReconnect = MAX_RECONNECT_ATTEMPTS;
  private reconnectDelay = BASE_RECONNECT_MS;
  private handlers: Map<WSMessageType, Set<Handler<any>>> = new Map();
  private onOpenCb?: () => void;
  private onCloseCb?: (code: number, reason: string) => void;
  private onErrorCb?: (err: Event) => void;
  private seq = 0;
  private pingInterval?: number;
  private pongTimeout?: number;
  private closedByUser = false;

  constructor(url?: string) {
    this.url = url || resolveServerUrl();
  }

  /** Resolve the configured server URL, falling back to a relative /ws path. */
  private static resolveUrl(): string {
    return resolveServerUrl();
  }

  /** Open the WebSocket connection. Resolves once the `open` event fires. */
  connect(): Promise<void> {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      return Promise.resolve();
    }

    this.closedByUser = false;
    return new Promise<void>((resolve, reject) => {
      let settled = false;

      try {
        this.ws = new WebSocket(this.url);
      } catch (err) {
        reject(err);
        return;
      }

      this.ws.onopen = () => {
        this.reconnectAttempts = 0;
        this.reconnectDelay = BASE_RECONNECT_MS;
        this.startPing();
        if (this.onOpenCb) this.onOpenCb();
        if (!settled) {
          settled = true;
          resolve();
        }
      };

      this.ws.onmessage = (event: MessageEvent) => this.handleMessage(event);
      this.ws.onclose = (event: CloseEvent) => {
        this.stopPing();
        if (this.onCloseCb) this.onCloseCb(event.code, event.reason || '');
        if (!settled) {
          settled = true;
          reject(new Error('WebSocket closed before open'));
        }
        this.scheduleReconnect();
      };
      this.ws.onerror = (event: Event) => {
        if (this.onErrorCb) this.onErrorCb(event);
        if (!settled) {
          settled = true;
          reject(event);
        }
      };
    });
  }

  /** Close the socket. Subsequent `connect()` calls will start fresh. */
  disconnect(): void {
    this.closedByUser = true;
    this.stopPing();
    if (this.ws) {
      this.ws.onopen = null;
      this.ws.onmessage = null;
      this.ws.onclose = null;
      this.ws.onerror = null;
      try {
        this.ws.close();
      } catch {
        // ignore
      }
      this.ws = null;
    }
  }

  /** Send a typed message. Adds a monotonic `seq` and `timestamp`. */
  send(type: WSMessageType, payload: any): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }
    const msg: WSMessage = {
      type,
      payload,
      timestamp: Date.now(),
      seq: ++this.seq,
    };
    try {
      this.ws.send(JSON.stringify(msg));
    } catch {
      // Best-effort; the next ping will surface a broken connection.
    }
  }

  /** Register a typed handler. Returns an unsubscribe function. */
  on(type: WSMessageType, handler: Handler<any>): () => void {
    let set = this.handlers.get(type);
    if (!set) {
      set = new Set();
      this.handlers.set(type, set);
    }
    set.add(handler);
    return () => {
      set?.delete(handler);
    };
  }

  onOpen(cb: () => void): void {
    this.onOpenCb = cb;
  }

  onClose(cb: (code: number, reason: string) => void): void {
    this.onCloseCb = cb;
  }

  onError(cb: (err: Event) => void): void {
    this.onErrorCb = cb;
  }

  get readyState(): number {
    return this.ws?.readyState ?? WebSocket.CLOSED;
  }

  /** True while the socket is open and ready to send. */
  get isOpen(): boolean {
    return this.readyState === WebSocket.OPEN;
  }

  // --- internals ---

  private handleMessage(event: MessageEvent): void {
    let msg: WSMessage;
    try {
      msg = JSON.parse(event.data) as WSMessage;
    } catch {
      return;
    }
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'pong') {
      if (this.pongTimeout !== undefined) {
        window.clearTimeout(this.pongTimeout);
        this.pongTimeout = undefined;
      }
    }

    const set = this.handlers.get(msg.type as WSMessageType);
    if (set) {
      for (const handler of set) {
        try {
          handler(msg);
        } catch {
          // isolate handler failures
        }
      }
    }
  }

  private startPing(): void {
    this.stopPing();
    this.pingInterval = window.setInterval(() => {
      this.send('ping', {});
      this.startPongTimeout();
    }, PING_INTERVAL_MS);
  }

  private startPongTimeout(): void {
    if (this.pongTimeout !== undefined) {
      window.clearTimeout(this.pongTimeout);
    }
    this.pongTimeout = window.setTimeout(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.close(4000, 'Pong timeout');
      }
    }, PONG_TIMEOUT_MS);
  }

  private stopPing(): void {
    if (this.pingInterval !== undefined) {
      window.clearInterval(this.pingInterval);
      this.pingInterval = undefined;
    }
    if (this.pongTimeout !== undefined) {
      window.clearTimeout(this.pongTimeout);
      this.pongTimeout = undefined;
    }
  }

  private scheduleReconnect(): void {
    if (this.closedByUser) return;
    if (this.reconnectAttempts >= this.maxReconnect) {
      return;
    }
    this.reconnectAttempts++;
    const delay = this.reconnectDelay;
    this.reconnectDelay = Math.min(this.reconnectDelay * 2, 30_000);
    window.setTimeout(() => {
      if (this.closedByUser) return;
      this.connect().catch(() => {
        // failure handled by onclose -> scheduleReconnect
      });
    }, delay);
  }
}

function resolveServerUrl(): string {
  if (typeof window === 'undefined') return '/ws';
  const cfg = (window as any).SynmergiaConfig;
  if (cfg && cfg.serverUrl) return cfg.serverUrl as string;
  const proto = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
  return proto + window.location.host + '/ws';
}

/** Shared singleton instance for the companion client. */
export const gameWebSocket = new GameWebSocket();