"""
backends.py -- Cache backends for the redis-bridge sidecar.

redis-bridge is an HTTP-to-Redis bridge. It talks HTTP (Godot's RedisStore
speaks HTTP) and Redis operations to a backend. Two backends:

  - InMemoryBackend : stdlib only. Used for local dev + unit tests.
  - RedisBackend    : redis-py. Prod (Docker image).

Both expose the same interface so the HTTP layer is backend-agnostic.

Wire protocol is defined in game/adapters/cache/redis_store.gd
and labs/prd-db.md sec.7.2.
"""
from __future__ import annotations

import threading
from abc import ABC, abstractmethod
from typing import Any


class CacheBackend(ABC):
    """Abstract cache backend shared by InMemory and Redis adapters."""

    @abstractmethod
    def connect(self, config: dict) -> int:
        ...

    @abstractmethod
    def close(self) -> None:
        ...

    @abstractmethod
    def healthy(self) -> bool:
        ...

    @abstractmethod
    def get(self, key: str) -> Any:
        ...

    @abstractmethod
    def set(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        ...

    @abstractmethod
    def set_nx(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        ...

    @abstractmethod
    def delete(self, key: str) -> int:
        ...

    @abstractmethod
    def exists(self, key: str) -> bool:
        ...

    @abstractmethod
    def expire(self, key: str, ttl_sec: int) -> int:
        ...

    @abstractmethod
    def incr(self, key: str, by: int = 1) -> int:
        ...

    @abstractmethod
    def incr_with_ttl(self, key: str, ttl_sec: int) -> int:
        ...

    @abstractmethod
    def hset(self, key: str, field: str, value: Any) -> bool:
        ...

    @abstractmethod
    def hget(self, key: str, field: str) -> Any:
        ...

    @abstractmethod
    def hget_all(self, key: str) -> dict:
        ...

    @abstractmethod
    def hdel(self, key: str, field: str) -> int:
        ...

    @abstractmethod
    def sadd(self, key: str, member: str) -> int:
        ...

    @abstractmethod
    def srem(self, key: str, member: str) -> int:
        ...

    @abstractmethod
    def smembers(self, key: str) -> list:
        ...

    @abstractmethod
    def sismember(self, key: str, member: str) -> bool:
        ...

    @abstractmethod
    def lpush(self, key: str, value: Any) -> int:
        ...

    @abstractmethod
    def rpush(self, key: str, value: Any) -> int:
        ...

    @abstractmethod
    def lpop(self, key: str) -> Any:
        ...

    @abstractmethod
    def lrange(self, key: str, start: int, stop: int) -> list:
        ...

    @abstractmethod
    def llen(self, key: str) -> int:
        ...

    @abstractmethod
    def publish(self, channel: str, message: Any) -> int:
        ...

# -- InMemory backend (stdlib only) ------------------------------

class InMemoryBackend(CacheBackend):
    """In-memory cache backend. Mirrors redis-bridge's op surface for dev/test."""

    def __init__(self) -> None:
        self._kv = {}
        self._expires = {}
        self._hashes = {}
        self._sets = {}
        self._lists = {}
        self._pubsub = {}
        self._lock = threading.RLock()

    def connect(self, config: dict) -> int:
        self._kv.clear()
        self._expires.clear()
        self._hashes.clear()
        self._sets.clear()
        self._lists.clear()
        self._pubsub.clear()
        return 0

    def close(self) -> None:
        self.connect({})

    def healthy(self) -> bool:
        return True

    def _is_expired(self, key: str) -> bool:
        if key not in self._expires:
            return False
        exp = self._expires[key]
        if exp <= 0:
            return False
        import time
        return time.time() >= exp

    def _sweep(self, key: str) -> None:
        if self._is_expired(key):
            self._kv.pop(key, None)
            self._expires.pop(key, None)

    def get(self, key: str) -> Any:
        with self._lock:
            self._sweep(key)
            return self._kv.get(key)

    def set(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        with self._lock:
            self._kv[key] = value
            if ttl_sec > 0:
                import time
                self._expires[key] = time.time() + ttl_sec
            else:
                self._expires.pop(key, None)
            return True

    def set_nx(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        with self._lock:
            self._sweep(key)
            if key in self._kv:
                return False
            self._kv[key] = value
            if ttl_sec > 0:
                import time
                self._expires[key] = time.time() + ttl_sec
            return True

    def delete(self, key: str) -> int:
        with self._lock:
            had = key in self._kv or key in self._hashes or key in self._sets or key in self._lists
            self._kv.pop(key, None)
            self._expires.pop(key, None)
            self._hashes.pop(key, None)
            self._sets.pop(key, None)
            self._lists.pop(key, None)
            return 1 if had else 0

    def exists(self, key: str) -> bool:
        with self._lock:
            self._sweep(key)
            return key in self._kv or key in self._hashes or key in self._sets or key in self._lists

    def expire(self, key: str, ttl_sec: int) -> int:
        with self._lock:
            if key not in self._kv:
                return -1
            if ttl_sec <= 0:
                self._expires.pop(key, None)
                return 0
            import time
            self._expires[key] = time.time() + ttl_sec
            return 1

    def incr(self, key: str, by: int = 1) -> int:
        with self._lock:
            self._sweep(key)
            cur = self._kv.get(key, 0)
            if not isinstance(cur, (int, float)):
                cur = 0
            v = int(cur) + by
            self._kv[key] = v
            return v

    def incr_with_ttl(self, key: str, ttl_sec: int) -> int:
        with self._lock:
            v = self.incr(key, 1)
            import time
            self._expires[key] = time.time() + ttl_sec
            return v

    def hset(self, key: str, field: str, value: Any) -> bool:
        with self._lock:
            if key not in self._hashes:
                self._hashes[key] = {}
            self._hashes[key][field] = value
            return True

    def hget(self, key: str, field: str) -> Any:
        with self._lock:
            if key not in self._hashes:
                return None
            return self._hashes[key].get(field)

    def hget_all(self, key: str) -> dict:
        with self._lock:
            if key not in self._hashes:
                return {}
            return dict(self._hashes[key])

    def hdel(self, key: str, field: str) -> int:
        with self._lock:
            if key not in self._hashes:
                return 0
            h = self._hashes[key]
            if field in h:
                del h[field]
                return 1
            return 0

    def sadd(self, key: str, member: str) -> int:
        with self._lock:
            if key not in self._sets:
                self._sets[key] = set()
            s = self._sets[key]
            if member in s:
                return 0
            s.add(member)
            return 1

    def srem(self, key: str, member: str) -> int:
        with self._lock:
            if key not in self._sets:
                return 0
            s = self._sets[key]
            if member in s:
                s.discard(member)
                return 1
            return 0

    def smembers(self, key: str) -> list:
        with self._lock:
            if key not in self._sets:
                return []
            return list(self._sets[key])

    def sismember(self, key: str, member: str) -> bool:
        with self._lock:
            if key not in self._sets:
                return False
            return member in self._sets[key]

    def lpush(self, key: str, value: Any) -> int:
        with self._lock:
            if key not in self._lists:
                self._lists[key] = []
            self._lists[key].insert(0, value)
            return len(self._lists[key])

    def rpush(self, key: str, value: Any) -> int:
        with self._lock:
            if key not in self._lists:
                self._lists[key] = []
            self._lists[key].append(value)
            return len(self._lists[key])

    def lpop(self, key: str) -> Any:
        with self._lock:
            if key not in self._lists:
                return None
            l = self._lists[key]
            if not l:
                return None
            return l.pop(0)

    def lrange(self, key: str, start: int, stop: int) -> list:
        with self._lock:
            if key not in self._lists:
                return []
            l = self._lists[key]
            lo = max(start, 0)
            if stop < 0:
                hi = len(l) - 1
            else:
                hi = min(stop, len(l) - 1)
            if lo > hi:
                return []
            return l[lo:hi + 1]

    def llen(self, key: str) -> int:
        with self._lock:
            if key not in self._lists:
                return 0
            return len(self._lists[key])

    def publish(self, channel: str, message: Any) -> int:
        with self._lock:
            subs = self._pubsub.get(channel, [])
            for q in subs:
                q.append(message)
            return len(subs)


# -- Redis backend (redis-py) ---------------------------------------------
# Lazy-imported so the module loads (and tests run) without redis installed.

class RedisBackend(CacheBackend):
    """Real Redis backend via redis-py. Installed in the Docker image."""

    def __init__(self) -> None:
        self._client = None
        self._dsn: str = ""

    def connect(self, config: dict) -> int:
        try:
            import redis  # type: ignore
        except ImportError:
            raise RuntimeError(
                "redis not installed; redis-bridge image must include it. "
                "Use the InMemory backend for local dev."
            )
        host = config.get("host", "redis")
        port = int(config.get("port", 6379))
        password = config.get("password", None)
        db = int(config.get("db", 0))
        self._dsn = "redis://%s:%d/%d" % (host, port, db)
        self._client = redis.Redis(
            host=host, port=port, password=password, db=db,
            decode_responses=True,
        )
        return 0

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None

    def healthy(self) -> bool:
        if self._client is None:
            return False
        try:
            return self._client.ping()
        except Exception:
            return False

    def get(self, key: str) -> Any:
        return self._client.get(key)

    def set(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        if ttl_sec > 0:
            return bool(self._client.set(key, value, ex=ttl_sec))
        return bool(self._client.set(key, value))

    def set_nx(self, key: str, value: Any, ttl_sec: int = 0) -> bool:
        kwargs = {"nx": True}
        if ttl_sec > 0:
            kwargs["ex"] = ttl_sec
        return bool(self._client.set(key, value, **kwargs))

    def delete(self, key: str) -> int:
        return int(self._client.delete(key))

    def exists(self, key: str) -> bool:
        return bool(self._client.exists(key))

    def expire(self, key: str, ttl_sec: int) -> int:
        return int(self._client.expire(key, ttl_sec))

    def incr(self, key: str, by: int = 1) -> int:
        return int(self._client.incrby(key, by))

    def incr_with_ttl(self, key: str, ttl_sec: int) -> int:
        # INCR + EXPIRE in one pipeline so the TTL is set even on a fresh key.
        pipe = self._client.pipeline()
        pipe.incrby(key, 1)
        pipe.expire(key, ttl_sec)
        pipe.execute()
        return int(self._client.get(key) or 0)

    def hset(self, key: str, field: str, value: Any) -> bool:
        return bool(self._client.hset(key, field, value))

    def hget(self, key: str, field: str) -> Any:
        return self._client.hget(key, field)

    def hget_all(self, key: str) -> dict:
        return self._client.hgetall(key)

    def hdel(self, key: str, field: str) -> int:
        return int(self._client.hdel(key, field))

    def sadd(self, key: str, member: str) -> int:
        return int(self._client.sadd(key, member))

    def srem(self, key: str, member: str) -> int:
        return int(self._client.srem(key, member))

    def smembers(self, key: str) -> list:
        return list(self._client.smembers(key))

    def sismember(self, key: str, member: str) -> bool:
        return bool(self._client.sismember(key, member))

    def lpush(self, key: str, value: Any) -> int:
        return int(self._client.lpush(key, value))

    def rpush(self, key: str, value: Any) -> int:
        return int(self._client.rpush(key, value))

    def lpop(self, key: str) -> Any:
        return self._client.lpop(key)

    def lrange(self, key: str, start: int, stop: int) -> list:
        return self._client.lrange(key, start, stop)

    def llen(self, key: str) -> int:
        return int(self._client.llen(key))

    def publish(self, channel: str, message: Any) -> int:
        return int(self._client.publish(channel, message))


def build_backend(backend_name: str = "inmemory", config: dict | None = None) -> CacheBackend:
    """Factory: 'inmemory' (default) or 'redis'."""
    if backend_name == "redis":
        b = RedisBackend()
    else:
        b = InMemoryBackend()
    b.connect(config or {})
    return b
