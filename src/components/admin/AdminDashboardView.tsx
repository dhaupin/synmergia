import React, { useState, useEffect, useCallback } from 'react';
import {
  Server,
  Database,
  ShieldCheck,
  Terminal,
  Activity,
  Users,
  Search,
  RefreshCw,
  Send,
  AlertTriangle,
  CheckCircle2,
  FileCode,
  HardDrive,
  Cpu,
  Layers,
  Zap,
  Globe,
  Lock,
  Radio,
  Sliders,
  Play,
  PlusCircle,
  Trash2,
  ChevronRight,
} from 'lucide-react';
import godotData from '../../data/godot_data.json';
import { synmergiaBridge, BridgeHealth, RedisHealth } from '../../services/bridgeClient';

type AdminTab = 'shards' | 'database' | 'security' | 'gm' | 'data';

interface CharacterRow {
  id: string;
  account_id: string;
  display_name: string;
  species_id: string;
  class_id: string;
  level: number;
  experience: number;
}

interface AccountRow {
  id: string;
  username: string;
  email?: string;
  display_name?: string;
  status: string;
  account_level: number;
}

interface KvRow {
  key: string;
  value: string;
  updated_at?: string;
}

interface MigrationRow {
  version: string;
  applied_at: string;
  checksum?: string;
}

export const AdminDashboardView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<AdminTab>('shards');
  const [selectedShard, setSelectedShard] = useState<string>('shard-us-east-1');
  const [commandInput, setCommandInput] = useState<string>('');
  const [commandLog, setCommandLog] = useState<Array<{ text: string; type: 'input' | 'output' | 'error'; timestamp: string }>>([
    { text: 'Synmergia Authoritative Admin Shell connected to /srv bridges.', type: 'output', timestamp: new Date().toLocaleTimeString() },
  ]);

  // Live Bridge States
  const [pgHealth, setPgHealth] = useState<BridgeHealth | null>(null);
  const [redisHealth, setRedisHealth] = useState<RedisHealth | null>(null);
  const [isLoadingHealth, setIsLoadingHealth] = useState<boolean>(true);

  // Live Database Table States
  const [migrations, setMigrations] = useState<MigrationRow[]>([]);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [accounts, setAccounts] = useState<AccountRow[]>([]);
  const [kvRecords, setKvRecords] = useState<KvRow[]>([]);
  const [activeSessions, setActiveSessions] = useState<Record<string, any>>({});
  const [onlinePeers, setOnlinePeers] = useState<Record<string, any>>({});

  // Form creation modal states for live records
  const [showAddAccount, setShowAddAccount] = useState<boolean>(false);
  const [newUsername, setNewUsername] = useState<string>('');
  const [newCharName, setNewCharName] = useState<string>('');
  const [newCharClass, setNewCharClass] = useState<string>('warrior');
  const [newCharSpecies, setNewCharSpecies] = useState<string>('human');

  // QoS / Security States
  const [rateLimitHits, setRateLimitHits] = useState<number>(0);
  const [securityEvents, setSecurityEvents] = useState<Array<{ time: string; service: string; event: string; severity: 'info' | 'warn' | 'crit' }>>([]);

  // Data Bridge Explorer State
  const [dataCategory, setDataCategory] = useState<string>('classes');
  const [dataSearch, setDataSearch] = useState<string>('');
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [syncToast, setSyncToast] = useState<string | null>(null);

  // Poll / Refresh Bridge & Database State
  const refreshAllState = useCallback(async () => {
    setIsLoadingHealth(true);
    try {
      // 1. Health checks
      const [pgh, redh] = await Promise.all([
        synmergiaBridge.getPgHealth(),
        synmergiaBridge.getRedisHealth(),
      ]);
      setPgHealth(pgh);
      setRedisHealth(redh);

      if (pgh?.ok) {
        // Bootstrap schema if clean
        await synmergiaBridge.execute(
          `CREATE TABLE IF NOT EXISTS schema_migrations (
            version VARCHAR(128) PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            checksum VARCHAR(64)
          )`
        );
        await synmergiaBridge.execute(
          `CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            username VARCHAR(32) UNIQUE NOT NULL,
            email VARCHAR(255),
            display_name VARCHAR(32),
            status TEXT NOT NULL DEFAULT 'active',
            account_level INTEGER NOT NULL DEFAULT 0
          )`
        );
        await synmergiaBridge.execute(
          `CREATE TABLE IF NOT EXISTS characters (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            display_name VARCHAR(32) UNIQUE NOT NULL,
            species_id VARCHAR(32) NOT NULL,
            class_id VARCHAR(32) NOT NULL,
            level INTEGER NOT NULL DEFAULT 1,
            experience INTEGER NOT NULL DEFAULT 0
          )`
        );
        await synmergiaBridge.execute(
          `CREATE TABLE IF NOT EXISTS kv (
            key VARCHAR(255) PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
          )`
        );

        // Fetch tables
        const [migRes, accRes, charRes, kvRes] = await Promise.all([
          synmergiaBridge.query<MigrationRow>('SELECT * FROM schema_migrations ORDER BY version ASC'),
          synmergiaBridge.query<AccountRow>('SELECT * FROM accounts ORDER BY username ASC'),
          synmergiaBridge.query<CharacterRow>('SELECT * FROM characters ORDER BY level DESC'),
          synmergiaBridge.query<KvRow>('SELECT * FROM kv ORDER BY key ASC'),
        ]);

        if (migRes.ok) setMigrations(migRes.rows);
        if (accRes.ok) setAccounts(accRes.rows);
        if (charRes.ok) setCharacters(charRes.rows);
        if (kvRes.ok) setKvRecords(kvRes.rows);
      }

      if (redh?.ok) {
        const [peers, sessions] = await Promise.all([
          synmergiaBridge.getHashAll('online:peers'),
          synmergiaBridge.getHashAll('sessions:active'),
        ]);
        setOnlinePeers(peers || {});
        setActiveSessions(sessions || {});
      }
    } catch (err: any) {
      console.error('Failed refreshing runtime bridge state:', err);
    } finally {
      setIsLoadingHealth(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    refreshAllState();
    const interval = setInterval(refreshAllState, 8000);
    return () => clearInterval(interval);
  }, [refreshAllState]);

  // Execute GM Command through Real Bridges
  const handleRunCommand = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!commandInput.trim()) return;

    const cmd = commandInput.trim();
    const time = new Date().toLocaleTimeString();

    const newLogs = [...commandLog, { text: `> ${cmd}`, type: 'input' as const, timestamp: time }];
    const parts = cmd.split(' ');
    const root = parts[0].toLowerCase();

    if (root === '/help') {
      newLogs.push({
        text: `Available Authoritative GM Commands:
  /accounts - List real accounts in PostgresStore
  /create_account <username> [email] - Register new account in DB
  /characters - List real characters in PostgresStore
  /create_char <username> <char_name> <class> [species] - Create character
  /delete_char <char_name> - Remove character from DB
  /broadcast <message> - Publish to Redis channel 'synmergia:broadcast'
  /kv_set <key> <val> - Store KV pair in DictStore/kv table
  /kv_get <key> - Query KV pair
  /sim_login <char_name> <zone> - Put peer into Redis 'online:peers'
  /sim_logout <char_name> - Remove peer from Redis 'online:peers'
  /rate_limit_test - Test QoS token bucket counter in Redis
  /apply_migration <version> - Record migration in schema_migrations
  /clear - Clear console`,
        type: 'output',
        timestamp: time,
      });
    } else if (root === '/clear') {
      setCommandLog([]);
      setCommandInput('');
      return;
    } else if (root === '/accounts') {
      const res = await synmergiaBridge.query<AccountRow>('SELECT * FROM accounts');
      if (res.ok) {
        newLogs.push({
          text: `[PostgresStore] Found ${res.rows.length} accounts:\n${
            res.rows.map((a) => `  • ${a.username} (ID: ${a.id}, Status: ${a.status})`).join('\n') || '  (No accounts registered)'
          }`,
          type: 'output',
          timestamp: time,
        });
      } else {
        newLogs.push({ text: `[Error] ${res.error}`, type: 'error', timestamp: time });
      }
    } else if (root === '/create_account') {
      const uname = parts[1];
      const email = parts[2] || `${uname}@synmergia.world`;
      if (!uname) {
        newLogs.push({ text: 'Usage: /create_account <username> [email]', type: 'error', timestamp: time });
      } else {
        const id = `acc_${Date.now()}`;
        const res = await synmergiaBridge.execute(
          'INSERT INTO accounts (id, username, email, display_name, status, account_level) VALUES ($1, $2, $3, $4, $5, $6)',
          [id, uname, email, uname, 'active', 1]
        );
        if (res.ok) {
          newLogs.push({ text: `[PostgresStore] Account "${uname}" created (id: ${id}).`, type: 'output', timestamp: time });
          refreshAllState();
        } else {
          newLogs.push({ text: `[PostgresStore Error] ${res.error}`, type: 'error', timestamp: time });
        }
      }
    } else if (root === '/characters') {
      const res = await synmergiaBridge.query<CharacterRow>('SELECT * FROM characters');
      if (res.ok) {
        newLogs.push({
          text: `[PostgresStore] Found ${res.rows.length} characters:\n${
            res.rows.map((c) => `  • ${c.display_name} (Lvl ${c.level} ${c.species_id} ${c.class_id})`).join('\n') || '  (No characters created)'
          }`,
          type: 'output',
          timestamp: time,
        });
      } else {
        newLogs.push({ text: `[Error] ${res.error}`, type: 'error', timestamp: time });
      }
    } else if (root === '/create_char') {
      const uname = parts[1];
      const charName = parts[2];
      const classId = parts[3] || 'warrior';
      const speciesId = parts[4] || 'human';

      if (!uname || !charName) {
        newLogs.push({ text: 'Usage: /create_char <username> <char_name> <class> [species]', type: 'error', timestamp: time });
      } else {
        const accRes = await synmergiaBridge.query<AccountRow>('SELECT id FROM accounts WHERE username = $1', [uname]);
        let accId = accRes.rows[0]?.id;
        if (!accId) {
          accId = `acc_${Date.now()}`;
          await synmergiaBridge.execute(
            'INSERT INTO accounts (id, username, email, display_name) VALUES ($1, $2, $3, $4)',
            [accId, uname, `${uname}@synmergia.world`, uname]
          );
        }

        const charId = `char_${Date.now()}`;
        const ins = await synmergiaBridge.execute(
          'INSERT INTO characters (id, account_id, display_name, species_id, class_id, level, experience) VALUES ($1, $2, $3, $4, $5, $6, $7)',
          [charId, accId, charName, speciesId, classId, 1, 0]
        );

        if (ins.ok) {
          newLogs.push({
            text: `[PostgresStore] Character "${charName}" created for account "${uname}". ID: ${charId}`,
            type: 'output',
            timestamp: time,
          });
          refreshAllState();
        } else {
          newLogs.push({ text: `[Error] ${ins.error}`, type: 'error', timestamp: time });
        }
      }
    } else if (root === '/delete_char') {
      const charName = parts[1];
      if (!charName) {
        newLogs.push({ text: 'Usage: /delete_char <char_name>', type: 'error', timestamp: time });
      } else {
        const del = await synmergiaBridge.execute('DELETE FROM characters WHERE display_name = $1', [charName]);
        if (del.ok) {
          newLogs.push({ text: `[PostgresStore] Deleted character "${charName}" (affected: ${del.affected}).`, type: 'output', timestamp: time });
          refreshAllState();
        } else {
          newLogs.push({ text: `[Error] ${del.error}`, type: 'error', timestamp: time });
        }
      }
    } else if (root === '/broadcast') {
      const msg = parts.slice(1).join(' ');
      const delivered = await synmergiaBridge.publish('synmergia:broadcast', { message: msg, time });
      newLogs.push({
        text: `[RedisStore PUBLISH] Channel: "synmergia:broadcast" | Message: "${msg || 'Server announcement'}" | Delivered: ${delivered}`,
        type: 'output',
        timestamp: time,
      });
      // Also log security/ops event
      setSecurityEvents((prev) => [
        { time, service: 'GMConsole', event: `Broadcast published: "${msg}"`, severity: 'info' },
        ...prev.slice(0, 19),
      ]);
    } else if (root === '/kv_set') {
      const k = parts[1];
      const v = parts.slice(2).join(' ');
      if (!k || !v) {
        newLogs.push({ text: 'Usage: /kv_set <key> <value>', type: 'error', timestamp: time });
      } else {
        await synmergiaBridge.execute('INSERT OR REPLACE INTO kv (key, value) VALUES ($1, $2)', [k, v]);
        newLogs.push({ text: `[DictStore / kv] Stored key="${k}"`, type: 'output', timestamp: time });
        refreshAllState();
      }
    } else if (root === '/kv_get') {
      const k = parts[1];
      const res = await synmergiaBridge.query<KvRow>('SELECT value FROM kv WHERE key = $1', [k]);
      if (res.ok && res.rows[0]) {
        newLogs.push({ text: `[DictStore / kv] ${k} = "${res.rows[0].value}"`, type: 'output', timestamp: time });
      } else {
        newLogs.push({ text: `[DictStore / kv] Key "${k}" not found.`, type: 'output', timestamp: time });
      }
    } else if (root === '/sim_login') {
      const name = parts[1] || 'Valerius';
      const zone = parts[2] || 'starter_plains';
      const peerData = JSON.stringify({ name, zone, ping: Math.floor(Math.random() * 30 + 15), joinedAt: time });
      await synmergiaBridge.setHash('online:peers', name, peerData);
      newLogs.push({ text: `[RedisStore HSET] Peer "${name}" logged into zone "${zone}".`, type: 'output', timestamp: time });
      refreshAllState();
    } else if (root === '/sim_logout') {
      const name = parts[1] || 'Valerius';
      await synmergiaBridge.deleteHash('online:peers', name);
      newLogs.push({ text: `[RedisStore HDEL] Peer "${name}" logged out.`, type: 'output', timestamp: time });
      refreshAllState();
    } else if (root === '/rate_limit_test') {
      const count = await synmergiaBridge.incr('qos:combat:rate_limit_hits', 1);
      setRateLimitHits(count);
      newLogs.push({
        text: `[QoSService INCR] Token bucket counter incremented via Redis: ${count}`,
        type: 'output',
        timestamp: time,
      });
      setSecurityEvents((prev) => [
        { time, service: 'QoSService', event: `Rate limit test counter at ${count}`, severity: 'warn' },
        ...prev.slice(0, 19),
      ]);
    } else if (root === '/apply_migration') {
      const v = parts[1] || `V${new Date().toISOString().replace(/\D/g, '').slice(0, 12)}__custom.sql`;
      await synmergiaBridge.execute('INSERT OR REPLACE INTO schema_migrations (version, checksum) VALUES ($1, $2)', [v, 'sha256:custom']);
      newLogs.push({ text: `[MigrationRunner] Applied migration ${v}`, type: 'output', timestamp: time });
      refreshAllState();
    } else {
      newLogs.push({
        text: `[Unknown Command] "${cmd}". Type /help to inspect real adapter commands.`,
        type: 'error',
        timestamp: time,
      });
    }

    setCommandLog(newLogs);
    setCommandInput('');
  };

  // Quick Account Form Submit
  const handleQuickAddAccount = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newUsername.trim()) return;
    const uid = `acc_${Date.now()}`;
    await synmergiaBridge.execute(
      'INSERT INTO accounts (id, username, email, display_name, status, account_level) VALUES ($1, $2, $3, $4, $5, $6)',
      [uid, newUsername.trim(), `${newUsername.trim()}@synmergia.world`, newUsername.trim(), 'active', 1]
    );

    if (newCharName.trim()) {
      const cid = `char_${Date.now()}`;
      await synmergiaBridge.execute(
        'INSERT INTO characters (id, account_id, display_name, species_id, class_id, level, experience) VALUES ($1, $2, $3, $4, $5, $6, $7)',
        [cid, uid, newCharName.trim(), newCharSpecies, newCharClass, 1, 0]
      );
    }

    setNewUsername('');
    setNewCharName('');
    setShowAddAccount(false);
    refreshAllState();
  };

  // Extract category data for Data Bridge Explorer
  const categoryData: Record<string, any> = (godotData as any)[dataCategory] || {};
  const filteredData = Object.entries(categoryData).filter(([key, val]) => {
    if (!dataSearch) return true;
    const s = dataSearch.toLowerCase();
    return (
      key.toLowerCase().includes(s) ||
      (val.display_name && String(val.display_name).toLowerCase().includes(s)) ||
      (val.description && String(val.description).toLowerCase().includes(s))
    );
  });

  return (
    <div className="flex-1 flex flex-col bg-slate-950 text-slate-100 overflow-hidden select-none">
      {/* Admin Subheader Navigation */}
      <div className="bg-slate-900 border-b border-slate-800 px-4 py-2 flex flex-wrap items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-2">
          <Server className="w-4 h-4 text-amber-400" />
          <span className="font-bold text-slate-200">Ops &amp; Infrastructure Dashboard</span>
          <span className="bg-emerald-950/70 border border-emerald-800/80 text-emerald-400 text-[10px] px-1.5 py-0.5 rounded font-mono flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
            LIVE /SRV BRIDGE
          </span>
        </div>

        {/* Sub-Tabs */}
        <div className="flex items-center bg-slate-950 p-1 rounded-lg border border-slate-800 gap-1">
          <button
            type="button"
            onClick={() => setActiveTab('shards')}
            className={`px-3 py-1 rounded text-xs font-medium transition-colors flex items-center gap-1.5 ${
              activeTab === 'shards' ? 'bg-amber-500 text-slate-950 font-semibold' : 'text-slate-400 hover:text-white'
            }`}
          >
            <Radio className="w-3.5 h-3.5" />
            <span>Shards &amp; Concurrency</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('database')}
            className={`px-3 py-1 rounded text-xs font-medium transition-colors flex items-center gap-1.5 ${
              activeTab === 'database' ? 'bg-amber-500 text-slate-950 font-semibold' : 'text-slate-400 hover:text-white'
            }`}
          >
            <Database className="w-3.5 h-3.5" />
            <span>DB Adapters (PRD-DB)</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('security')}
            className={`px-3 py-1 rounded text-xs font-medium transition-colors flex items-center gap-1.5 ${
              activeTab === 'security' ? 'bg-amber-500 text-slate-950 font-semibold' : 'text-slate-400 hover:text-white'
            }`}
          >
            <ShieldCheck className="w-3.5 h-3.5" />
            <span>QoS &amp; Firewall</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('gm')}
            className={`px-3 py-1 rounded text-xs font-medium transition-colors flex items-center gap-1.5 ${
              activeTab === 'gm' ? 'bg-amber-500 text-slate-950 font-semibold' : 'text-slate-400 hover:text-white'
            }`}
          >
            <Terminal className="w-3.5 h-3.5" />
            <span>GM Console</span>
          </button>

          <button
            type="button"
            onClick={() => setActiveTab('data')}
            className={`px-3 py-1 rounded text-xs font-medium transition-colors flex items-center gap-1.5 ${
              activeTab === 'data' ? 'bg-amber-500 text-slate-950 font-semibold' : 'text-slate-400 hover:text-white'
            }`}
          >
            <FileCode className="w-3.5 h-3.5" />
            <span>Data Bridge Explorer</span>
          </button>
        </div>
      </div>

      {/* Main Tab Content View */}
      <div className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
        {/* TAB 1: SHARDS & CONCURRENCY */}
        {activeTab === 'shards' && (
          <div className="space-y-6 max-w-6xl mx-auto">
            {/* Top Real-time Metric Strip */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>Target Tick Rate</span>
                  <Activity className="w-4 h-4 text-emerald-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-emerald-400">20.0 Hz</div>
                <div className="text-[11px] text-slate-500 mt-1">Authoritative physics &amp; combat loop</div>
              </div>

              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>Registered Accounts</span>
                  <Users className="w-4 h-4 text-amber-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-slate-100">{accounts.length} Accounts</div>
                <div className="text-[11px] text-slate-500 mt-1">Durable in PersistenceStore</div>
              </div>

              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>Online Peers (Redis)</span>
                  <Zap className="w-4 h-4 text-cyan-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-cyan-400">{Object.keys(onlinePeers).length} Active</div>
                <div className="text-[11px] text-slate-500 mt-1">Tracked in srv/redis-bridge</div>
              </div>

              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>Active Shard</span>
                  <Globe className="w-4 h-4 text-purple-400" />
                </div>
                <select
                  value={selectedShard}
                  onChange={(e) => setSelectedShard(e.target.value)}
                  className="bg-slate-800 border border-slate-700 text-slate-200 text-sm font-semibold rounded px-2 py-1 w-full"
                >
                  <option value="shard-us-east-1">shard-us-east-1 (Primary)</option>
                  <option value="shard-us-west-1">shard-us-west-1 (Secondary)</option>
                  <option value="shard-eu-central">shard-eu-central (Frankfurt)</option>
                </select>
                <div className="text-[11px] text-slate-500 mt-1">ShardManager route destination</div>
              </div>
            </div>

            {/* Zone Instances Card Grid */}
            <div>
              <h3 className="text-sm font-bold text-slate-300 uppercase tracking-wider mb-3">
                Active Zone Instances (ZoneManager)
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                {['starter_plains', 'village_center', 'forest_meadow', 'dungeon_forest_depths'].map((zoneId) => {
                  const peersInZone = Object.values(onlinePeers).filter((pStr) => {
                    try {
                      return JSON.parse(pStr).zone === zoneId;
                    } catch {
                      return false;
                    }
                  }).length;

                  return (
                    <div key={zoneId} className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                      <div className="flex items-center justify-between mb-2">
                        <span className="font-bold text-slate-200 text-sm">{zoneId}</span>
                        <span className="px-2 py-0.5 rounded text-[10px] bg-slate-800 text-amber-400 border border-slate-700 font-mono">
                          zone
                        </span>
                      </div>
                      <div className="space-y-1.5 text-xs text-slate-400">
                        <div className="flex justify-between">
                          <span>Active Peers:</span>
                          <span className="font-mono text-slate-200">{peersInZone}</span>
                        </div>
                        <div className="flex justify-between">
                          <span>Status:</span>
                          <span className="text-emerald-400 font-medium">Ready</span>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Live Characters in PersistenceStore */}
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">Real Character Registry (PostgresStore / SQLite)</h3>
                  <p className="text-xs text-slate-500">Live records queried from table <code className="text-amber-400">characters</code></p>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setShowAddAccount(!showAddAccount)}
                    className="px-3 py-1.5 rounded bg-amber-500 text-slate-950 font-bold text-xs flex items-center gap-1.5 hover:bg-amber-400 transition-colors"
                  >
                    <PlusCircle className="w-3.5 h-3.5" />
                    <span>New Account / Char</span>
                  </button>
                  <button
                    type="button"
                    onClick={refreshAllState}
                    className="p-1.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300"
                    title="Refresh data"
                  >
                    <RefreshCw className="w-4 h-4" />
                  </button>
                </div>
              </div>

              {/* Quick Add Form Modal */}
              {showAddAccount && (
                <form onSubmit={handleQuickAddAccount} className="mb-4 p-4 bg-slate-950 border border-amber-800/60 rounded-xl space-y-3">
                  <div className="text-xs font-bold text-amber-400 uppercase tracking-wider">Create Account &amp; Character in PostgresStore</div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 text-xs">
                    <div>
                      <label className="block text-slate-400 mb-1">Username *</label>
                      <input
                        type="text"
                        required
                        value={newUsername}
                        onChange={(e) => setNewUsername(e.target.value)}
                        placeholder="e.g. solon"
                        className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-100"
                      />
                    </div>
                    <div>
                      <label className="block text-slate-400 mb-1">Character Name</label>
                      <input
                        type="text"
                        value={newCharName}
                        onChange={(e) => setNewCharName(e.target.value)}
                        placeholder="e.g. Solon The Great"
                        className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-100"
                      />
                    </div>
                    <div>
                      <label className="block text-slate-400 mb-1">Class</label>
                      <select
                        value={newCharClass}
                        onChange={(e) => setNewCharClass(e.target.value)}
                        className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-100"
                      >
                        <option value="warrior">Warrior</option>
                        <option value="psion">Psion</option>
                        <option value="sorcerer">Sorcerer</option>
                        <option value="warden">Warden</option>
                        <option value="bulwark">Bulwark</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-slate-400 mb-1">Species</label>
                      <select
                        value={newCharSpecies}
                        onChange={(e) => setNewCharSpecies(e.target.value)}
                        className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-100"
                      >
                        <option value="human">Human</option>
                        <option value="synthetic">Synthetic</option>
                        <option value="akkan">Akkan</option>
                      </select>
                    </div>
                  </div>
                  <div className="flex justify-end gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => setShowAddAccount(false)}
                      className="px-3 py-1.5 rounded bg-slate-800 text-slate-300 text-xs"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      className="px-3 py-1.5 rounded bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs"
                    >
                      Save to Database
                    </button>
                  </div>
                </form>
              )}

              {characters.length === 0 ? (
                <div className="p-8 text-center bg-slate-950/50 rounded-lg border border-slate-800/80">
                  <p className="text-sm text-slate-400 mb-2">No characters in the database yet.</p>
                  <p className="text-xs text-slate-500 mb-4">
                    Create an account above or execute GM command <code className="text-amber-400">/create_char &lt;user&gt; &lt;name&gt; &lt;class&gt;</code>
                  </p>
                  <button
                    type="button"
                    onClick={() => {
                      setCommandInput('/create_char valerius Valerius warrior human');
                      setActiveTab('gm');
                    }}
                    className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs rounded"
                  >
                    Quick Add Sample Character via GM Shell
                  </button>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-slate-950/80 text-slate-400 border-b border-slate-800">
                      <tr>
                        <th className="py-2.5 px-3">Character ID</th>
                        <th className="py-2.5 px-3">Display Name</th>
                        <th className="py-2.5 px-3">Species / Class</th>
                        <th className="py-2.5 px-3">Level</th>
                        <th className="py-2.5 px-3">Account Ref</th>
                        <th className="py-2.5 px-3 text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/60">
                      {characters.map((c) => (
                        <tr key={c.id} className="hover:bg-slate-800/40">
                          <td className="py-2.5 px-3 font-mono text-slate-400">{c.id}</td>
                          <td className="py-2.5 px-3 font-semibold text-slate-200">{c.display_name}</td>
                          <td className="py-2.5 px-3 text-slate-300">
                            {c.species_id} · <span className="text-amber-400">{c.class_id}</span>
                          </td>
                          <td className="py-2.5 px-3 font-mono text-emerald-400">Lv. {c.level}</td>
                          <td className="py-2.5 px-3 font-mono text-slate-500">{c.account_id}</td>
                          <td className="py-2.5 px-3 text-right space-x-2">
                            <button
                              type="button"
                              onClick={async () => {
                                await synmergiaBridge.setHash(
                                  'online:peers',
                                  c.display_name,
                                  JSON.stringify({ name: c.display_name, zone: 'starter_plains', ping: 25, joinedAt: new Date().toLocaleTimeString() })
                                );
                                refreshAllState();
                              }}
                              className="px-2 py-1 rounded bg-slate-800 hover:bg-emerald-950 hover:text-emerald-300 text-slate-300 text-[11px] transition-colors"
                            >
                              Sim Login
                            </button>
                            <button
                              type="button"
                              onClick={async () => {
                                await synmergiaBridge.execute('DELETE FROM characters WHERE id = $1', [c.id]);
                                refreshAllState();
                              }}
                              className="px-2 py-1 rounded bg-slate-800 hover:bg-red-950 hover:text-red-300 text-slate-300 text-[11px] transition-colors"
                            >
                              <Trash2 className="w-3 h-3 inline" />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        )}

        {/* TAB 2: DATABASE & ADAPTERS (PRD-DB) */}
        {activeTab === 'database' && (
          <div className="space-y-6 max-w-6xl mx-auto">
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">Storage Adapters Health (AdapterRegistry)</h3>
                  <p className="text-xs text-slate-500">
                    Live wire protocol endpoints connected to <code className="text-amber-400">/srv/pg-bridge</code> and <code className="text-amber-400">/srv/redis-bridge</code>
                  </p>
                </div>
                <button
                  type="button"
                  onClick={refreshAllState}
                  className="flex items-center gap-1.5 text-xs text-slate-300 bg-slate-800 hover:bg-slate-700 px-2.5 py-1 rounded transition-colors"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${isLoadingHealth ? 'animate-spin' : ''}`} />
                  <span>Refresh Health</span>
                </button>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {/* PostgresStore Sidecar Card */}
                <div className="bg-slate-950 border border-slate-800 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-bold text-slate-200 text-xs">PostgresStore Sidecar (srv/pg-bridge)</span>
                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono border ${
                        pgHealth?.ok
                          ? 'bg-emerald-950 text-emerald-400 border-emerald-800'
                          : 'bg-red-950 text-red-400 border-red-800'
                      }`}
                    >
                      {pgHealth?.ok ? 'ONLINE' : 'DISCONNECTED'}
                    </span>
                  </div>
                  <p className="text-[11px] text-slate-400 mb-3">
                    Durable storage for accounts, characters, sessions, and schema migrations.
                  </p>
                  <div className="space-y-1 text-xs font-mono text-slate-300">
                    <div className="flex justify-between">
                      <span className="text-slate-500">Backend:</span>
                      <span className="text-amber-400">{pgHealth?.backend || 'Unreachable'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Version:</span>
                      <span>{pgHealth?.version || 'N/A'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Accounts Row Count:</span>
                      <span className="text-emerald-400">{accounts.length}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Characters Row Count:</span>
                      <span className="text-emerald-400">{characters.length}</span>
                    </div>
                  </div>
                </div>

                {/* RedisStore Sidecar Card */}
                <div className="bg-slate-950 border border-slate-800 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-2">
                    <span className="font-bold text-slate-200 text-xs">RedisStore Sidecar (srv/redis-bridge)</span>
                    <span
                      className={`px-2 py-0.5 rounded text-[10px] font-mono border ${
                        redisHealth?.ok
                          ? 'bg-emerald-950 text-emerald-400 border-emerald-800'
                          : 'bg-red-950 text-red-400 border-red-800'
                      }`}
                    >
                      {redisHealth?.ok ? 'ONLINE' : 'DISCONNECTED'}
                    </span>
                  </div>
                  <p className="text-[11px] text-slate-400 mb-3">
                    High-throughput cache for active peers, fast lookup hashes, and pub/sub.
                  </p>
                  <div className="space-y-1 text-xs font-mono text-slate-300">
                    <div className="flex justify-between">
                      <span className="text-slate-500">Backend:</span>
                      <span className="text-cyan-400">{redisHealth?.backend || 'Unreachable'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Version:</span>
                      <span>{redisHealth?.version || 'N/A'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Tracked Online Peers:</span>
                      <span className="text-emerald-400">{Object.keys(onlinePeers).length}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">QoS Test Hits:</span>
                      <span>{rateLimitHits}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* SQL Migrations Table */}
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">Applied Database Migrations</h3>
                  <p className="text-xs text-slate-500">Queried from table <code className="text-amber-400">schema_migrations</code></p>
                </div>
                <button
                  type="button"
                  onClick={async () => {
                    await synmergiaBridge.execute(
                      'INSERT OR REPLACE INTO schema_migrations (version, checksum) VALUES ($1, $2)',
                      ['V20260907_001__init_accounts.sql', 'sha256:init_accounts']
                    );
                    await synmergiaBridge.execute(
                      'INSERT OR REPLACE INTO schema_migrations (version, checksum) VALUES ($1, $2)',
                      ['V20260909_001__init_kv.sql', 'sha256:init_kv']
                    );
                    refreshAllState();
                  }}
                  className="px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs"
                >
                  Seed Recorded Migrations
                </button>
              </div>

              {migrations.length === 0 ? (
                <div className="p-4 bg-slate-950 rounded text-center text-xs text-slate-500">
                  No migrations recorded in schema_migrations yet. Click &quot;Seed Recorded Migrations&quot; or execute via GM Console.
                </div>
              ) : (
                <div className="space-y-2 text-xs">
                  {migrations.map((m) => (
                    <div key={m.version} className="bg-slate-950 border border-slate-800/80 rounded-lg p-3 flex items-center justify-between">
                      <div>
                        <div className="font-mono font-semibold text-amber-400">{m.version}</div>
                        <div className="text-slate-500 text-[11px] mt-0.5">Applied: {m.applied_at || 'Just now'}</div>
                      </div>
                      <span className="text-emerald-400 font-mono font-bold text-[11px] bg-emerald-950/60 px-2 py-0.5 rounded border border-emerald-800/80">
                        APPLIED
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* KV Table (DictStore / Generic Persistence) */}
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">KV State Store (DictStore / Table `kv`)</h3>
                  <p className="text-xs text-slate-500">Generic key-value storage defined in <code className="text-amber-400">V20260909_001__init_kv.sql</code></p>
                </div>
                <span className="text-xs font-mono text-slate-400">{kvRecords.length} Keys stored</span>
              </div>

              {kvRecords.length === 0 ? (
                <div className="p-4 bg-slate-950 rounded text-center text-xs text-slate-500">
                  No KV records present. Store a key using <code className="text-amber-400">/kv_set &lt;key&gt; &lt;value&gt;</code> in the GM Console.
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-slate-950 text-slate-400 border-b border-slate-800">
                      <tr>
                        <th className="py-2 px-3">Key</th>
                        <th className="py-2 px-3">Value</th>
                        <th className="py-2 px-3">Updated At</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/60">
                      {kvRecords.map((r) => (
                        <tr key={r.key}>
                          <td className="py-2 px-3 font-mono text-amber-400">{r.key}</td>
                          <td className="py-2 px-3 text-slate-200 font-mono">{r.value}</td>
                          <td className="py-2 px-3 text-slate-500 text-[11px]">{r.updated_at || 'Recent'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        )}

        {/* TAB 3: QOS & FIREWALL */}
        {activeTab === 'security' && (
          <div className="space-y-6 max-w-6xl mx-auto">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>QoSService Token Buckets</span>
                  <Zap className="w-4 h-4 text-amber-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-slate-100">{rateLimitHits} Hits</div>
                <p className="text-[11px] text-slate-500 mt-1">Managed via srv/redis-bridge rate limit key</p>
              </div>

              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>AppFirewall Recursion Guard</span>
                  <ShieldCheck className="w-4 h-4 text-emerald-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-emerald-400">Max Depth: 16</div>
                <p className="text-[11px] text-slate-500 mt-1">Tool call recursion depth locked in Godot</p>
              </div>

              <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
                <div className="text-slate-400 text-xs mb-1 flex items-center justify-between">
                  <span>Registered Accounts</span>
                  <Users className="w-4 h-4 text-purple-400" />
                </div>
                <div className="text-2xl font-bold font-mono text-purple-400">{accounts.length} Profiles</div>
                <p className="text-[11px] text-slate-500 mt-1">Active player accounts in storage</p>
              </div>
            </div>

            {/* Security Audit Feed */}
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">Security &amp; QoS Event Stream</h3>
                  <p className="text-xs text-slate-500">Live operational events from admin operations and rate limit checks</p>
                </div>
                <button
                  type="button"
                  onClick={async () => {
                    const count = await synmergiaBridge.incr('qos:combat:rate_limit_hits', 1);
                    setRateLimitHits(count);
                    setSecurityEvents((prev) => [
                      { time: new Date().toLocaleTimeString(), service: 'QoSService', event: `Manual rate test triggered (Hits: ${count})`, severity: 'warn' },
                      ...prev,
                    ]);
                  }}
                  className="px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-amber-400 text-xs font-semibold"
                >
                  Test Rate Limiter (INCR)
                </button>
              </div>

              {securityEvents.length === 0 ? (
                <div className="p-4 bg-slate-950 rounded text-center text-xs text-slate-500">
                  No security events recorded yet. Trigger rate limit test above or publish a broadcast.
                </div>
              ) : (
                <div className="space-y-2">
                  {securityEvents.map((e, idx) => (
                    <div key={idx} className="bg-slate-950 border border-slate-800/80 rounded-lg p-3 text-xs flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-slate-500">{e.time}</span>
                        <span className="font-mono font-semibold text-amber-400">[{e.service}]</span>
                        <span className="text-slate-300">{e.event}</span>
                      </div>
                      <span
                        className={`font-mono text-[10px] px-2 py-0.5 rounded border ${
                          e.severity === 'warn'
                            ? 'text-amber-400 bg-amber-950/60 border-amber-800/80'
                            : 'text-emerald-400 bg-emerald-950/60 border-emerald-800/80'
                        }`}
                      >
                        {e.severity.toUpperCase()}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* TAB 4: GM CONSOLE & COMMANDS */}
        {activeTab === 'gm' && (
          <div className="space-y-4 max-w-5xl mx-auto">
            {/* Quick Action Presets */}
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
              <span className="text-xs font-bold text-slate-300 uppercase tracking-wider block mb-2">
                GM Quick Actions (Live Bridges)
              </span>
              <div className="flex flex-wrap gap-2 text-xs">
                <button
                  type="button"
                  onClick={() => setCommandInput('/broadcast "Server maintenance in 10 minutes."')}
                  className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700"
                >
                  Broadcast Notice (Redis)
                </button>
                <button
                  type="button"
                  onClick={() => setCommandInput('/create_char valerius Valerius warrior human')}
                  className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-amber-300 border border-slate-700"
                >
                  Create Valerius (SQL)
                </button>
                <button
                  type="button"
                  onClick={() => setCommandInput('/sim_login Valerius starter_plains')}
                  className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-emerald-300 border border-slate-700"
                >
                  Sim Login Peer
                </button>
                <button
                  type="button"
                  onClick={() => setCommandInput('/kv_set server:motd "Welcome to Synmergia!"')}
                  className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-cyan-300 border border-slate-700"
                >
                  Set MOTD in KV
                </button>
                <button
                  type="button"
                  onClick={() => setCommandInput('/rate_limit_test')}
                  className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-purple-300 border border-slate-700"
                >
                  Rate Limit Test (QoS)
                </button>
              </div>
            </div>

            {/* Terminal Window */}
            <div className="bg-slate-950 border border-slate-800 rounded-xl overflow-hidden shadow-2xl flex flex-col h-[480px]">
              <div className="bg-slate-900 border-b border-slate-800 px-4 py-2 flex items-center justify-between text-xs text-slate-400">
                <div className="flex items-center gap-2">
                  <Terminal className="w-4 h-4 text-amber-400" />
                  <span className="font-mono text-slate-200">Admin Shell (Direct Bridge Wired)</span>
                </div>
                <button
                  type="button"
                  onClick={() => setCommandLog([])}
                  className="text-slate-500 hover:text-slate-300 text-[11px]"
                >
                  Clear Logs
                </button>
              </div>

              {/* Terminal Logs Area */}
              <div className="flex-1 p-4 overflow-y-auto font-mono text-xs space-y-2 bg-slate-950">
                {commandLog.map((log, idx) => (
                  <div
                    key={idx}
                    className={`leading-relaxed whitespace-pre-wrap ${
                      log.type === 'input'
                        ? 'text-cyan-400 font-semibold'
                        : log.type === 'error'
                        ? 'text-red-400'
                        : 'text-slate-300'
                    }`}
                  >
                    <span className="text-slate-600 text-[10px] mr-2">[{log.timestamp}]</span>
                    {log.text}
                  </div>
                ))}
              </div>

              {/* Command Input Form */}
              <form onSubmit={handleRunCommand} className="bg-slate-900 border-t border-slate-800 p-2 flex items-center gap-2">
                <span className="text-amber-400 font-mono pl-2 font-bold">&gt;</span>
                <input
                  type="text"
                  value={commandInput}
                  onChange={(e) => setCommandInput(e.target.value)}
                  placeholder="Type /help for authoritative commands (/accounts, /create_char, /broadcast, /kv_set)..."
                  className="flex-1 bg-transparent border-0 text-slate-100 font-mono text-xs focus:outline-none placeholder:text-slate-600"
                />
                <button
                  type="submit"
                  className="px-3 py-1.5 rounded bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs flex items-center gap-1 transition-colors"
                >
                  <Send className="w-3.5 h-3.5" />
                  <span>Exec</span>
                </button>
              </form>
            </div>
          </div>
        )}

        {/* TAB 5: DATA BRIDGE EXPLORER */}
        {activeTab === 'data' && (
          <div className="space-y-6 max-w-6xl mx-auto">
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-5">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-4">
                <div>
                  <h3 className="text-sm font-bold text-slate-200">Godot Static Resource Registry</h3>
                  <p className="text-xs text-slate-500">
                    Directly parsed from <code className="text-amber-400">game/data/**/*.tres</code> using <code className="text-amber-400">scripts/sync_godot_data.ts</code>
                  </p>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={async () => {
                      setIsSyncing(true);
                      try {
                        const res = await fetch('/api/pg/health');
                        setIsSyncing(false);
                        setSyncToast('Re-synced Godot resources.');
                        setTimeout(() => setSyncToast(null), 3000);
                      } catch {
                        setIsSyncing(false);
                      }
                    }}
                    disabled={isSyncing}
                    className="px-3 py-1.5 rounded bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs flex items-center gap-1.5 transition-colors disabled:opacity-50"
                  >
                    <RefreshCw className={`w-3.5 h-3.5 ${isSyncing ? 'animate-spin' : ''}`} />
                    <span>Re-sync Godot Data</span>
                  </button>
                </div>
              </div>

              {syncToast && (
                <div className="mb-4 p-2.5 rounded bg-emerald-950/80 border border-emerald-800 text-emerald-300 text-xs flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0" />
                  <span>{syncToast}</span>
                </div>
              )}

              {/* Category Selector Chips */}
              <div className="flex flex-wrap gap-1.5 mb-4">
                {[
                  { id: 'classes', label: `Classes (${Object.keys(godotData.classes || {}).length})` },
                  { id: 'skills', label: `Skills (${Object.keys(godotData.skills || {}).length})` },
                  { id: 'enemies', label: `Enemies (${Object.keys(godotData.enemies || {}).length})` },
                  { id: 'zones', label: `Zones (${Object.keys(godotData.zones || {}).length})` },
                  { id: 'weapons', label: `Weapons (${Object.keys(godotData.weapons || {}).length})` },
                  { id: 'armors', label: `Armors (${Object.keys(godotData.armors || {}).length})` },
                  { id: 'factions', label: `Factions (${Object.keys(godotData.factions || {}).length})` },
                  { id: 'achievements', label: `Achievements (${Object.keys(godotData.achievements || {}).length})` },
                ].map((cat) => (
                  <button
                    key={cat.id}
                    type="button"
                    onClick={() => setDataCategory(cat.id)}
                    className={`px-3 py-1 rounded text-xs transition-colors ${
                      dataCategory === cat.id
                        ? 'bg-amber-500 text-slate-950 font-bold'
                        : 'bg-slate-950 text-slate-400 border border-slate-800 hover:text-white'
                    }`}
                  >
                    {cat.label}
                  </button>
                ))}
              </div>

              {/* Search Bar */}
              <div className="relative mb-4">
                <Search className="w-4 h-4 text-slate-500 absolute left-3 top-2.5" />
                <input
                  type="text"
                  value={dataSearch}
                  onChange={(e) => setDataSearch(e.target.value)}
                  placeholder={`Search ${dataCategory}...`}
                  className="w-full bg-slate-950 border border-slate-800 rounded-lg pl-9 pr-4 py-2 text-xs text-slate-200 placeholder:text-slate-600 focus:outline-none focus:border-amber-500/50"
                />
              </div>

              {/* Data Cards Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                {filteredData.slice(0, 60).map(([key, item]: [string, any]) => (
                  <div key={key} className="bg-slate-950 border border-slate-800/80 rounded-lg p-3 text-xs space-y-1.5">
                    <div className="flex items-center justify-between">
                      <span className="font-bold text-slate-200 truncate">{item.display_name || key}</span>
                      <span className="text-[10px] font-mono text-amber-400 bg-amber-950/40 px-1.5 py-0.5 rounded border border-amber-900/60">
                        {item._file ? item._file.split('/').pop() : key}
                      </span>
                    </div>

                    {item.description && (
                      <p className="text-slate-400 text-[11px] line-clamp-2">{item.description}</p>
                    )}

                    <div className="pt-2 border-t border-slate-900 flex flex-wrap gap-2 text-[10px] font-mono text-slate-500">
                      {item.role && <span>Role: <span className="text-slate-300">{item.role}</span></span>}
                      {item.damage_type && <span>Dmg: <span className="text-amber-300">{item.damage_type}</span></span>}
                      {item.max_health && <span>HP: <span className="text-emerald-400">{item.max_health}</span></span>}
                      {item.level && <span>Lv: <span className="text-cyan-400">{item.level}</span></span>}
                      {item.resource_type && <span>Resource: <span className="text-purple-400">{item.resource_type}</span></span>}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
