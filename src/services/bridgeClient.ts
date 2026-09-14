/**
 * Synmergia Adapter Bridge Client
 * Connects directly to srv/pg-bridge (PersistenceStore) and srv/redis-bridge (CacheStore)
 * adhering to the wire protocol defined in labs/prd-db.md and game/adapters/.
 */

export interface BridgeHealth {
  ok: boolean;
  version: string;
  backend: string;
}

export interface SqlQueryResult<T = Record<string, any>> {
  ok: boolean;
  rows: T[];
  error?: string;
}

export interface SqlExecuteResult {
  ok: boolean;
  affected: number;
  error?: string;
}

export interface RedisHealth {
  ok: boolean;
  version: string;
  backend: string;
}

export interface RedisHashResult {
  fields: Record<string, any>;
  ok?: boolean;
}

export const synmergiaBridge = {
  // --- PostgresStore / SQLite Sidecar API ---
  async getPgHealth(): Promise<BridgeHealth | null> {
    try {
      const res = await fetch('/api/pg/health');
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  },

  async query<T = Record<string, any>>(sql: string, params: any[] = []): Promise<SqlQueryResult<T>> {
    try {
      const res = await fetch('/api/pg/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql, params }),
      });
      return await res.json();
    } catch (e: any) {
      return { ok: false, rows: [], error: e.message };
    }
  },

  async execute(sql: string, params: any[] = []): Promise<SqlExecuteResult> {
    try {
      const res = await fetch('/api/pg/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sql, params }),
      });
      return await res.json();
    } catch (e: any) {
      return { ok: false, affected: 0, error: e.message };
    }
  },

  // --- RedisStore / Cache Sidecar API ---
  async getRedisHealth(): Promise<RedisHealth | null> {
    try {
      const res = await fetch('/api/redis/health');
      if (!res.ok) return null;
      return await res.json();
    } catch {
      return null;
    }
  },

  async getCache(key: string): Promise<any> {
    try {
      const res = await fetch(`/api/redis/get?key=${encodeURIComponent(key)}`);
      if (!res.ok) return null;
      const data = await res.json();
      return data.value;
    } catch {
      return null;
    }
  },

  async setCache(key: string, value: any, ttlSec: number = 0): Promise<boolean> {
    try {
      const res = await fetch('/api/redis/set', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, value, ttl_sec: ttlSec }),
      });
      const data = await res.json();
      return !!data.ok;
    } catch {
      return false;
    }
  },

  async deleteCache(key: string): Promise<number> {
    try {
      const res = await fetch('/api/redis/del', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key }),
      });
      const data = await res.json();
      return data.deleted || 0;
    } catch {
      return 0;
    }
  },

  async getHashAll(key: string): Promise<Record<string, any>> {
    try {
      const res = await fetch(`/api/redis/hget_all?key=${encodeURIComponent(key)}`);
      if (!res.ok) return {};
      const data = await res.json();
      return data.fields || {};
    } catch {
      return {};
    }
  },

  async setHash(key: string, field: string, value: any): Promise<boolean> {
    try {
      const res = await fetch('/api/redis/hset', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, field, value }),
      });
      const data = await res.json();
      return !!data.ok;
    } catch {
      return false;
    }
  },

  async deleteHash(key: string, field: string): Promise<number> {
    try {
      const res = await fetch('/api/redis/hdel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, field }),
      });
      const data = await res.json();
      return data.deleted || 0;
    } catch {
      return 0;
    }
  },

  async incr(key: string, by: number = 1): Promise<number> {
    try {
      const res = await fetch('/api/redis/incr', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, by }),
      });
      const data = await res.json();
      return data.value || 0;
    } catch {
      return 0;
    }
  },

  async publish(channel: string, message: any): Promise<number> {
    try {
      const res = await fetch('/api/redis/publish', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel, message }),
      });
      const data = await res.json();
      return data.delivered || 0;
    } catch {
      return 0;
    }
  },
};
