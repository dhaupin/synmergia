"""
backends.py — Persistence backends for the pg-bridge sidecar.

pg-bridge is an HTTP-to-SQL bridge. It talks HTTP (Godot's PostgresStore
speaks HTTP) and SQL to a backend. Two backends:

  - SQLiteBackend : in-memory SQLite. Zero deps (stdlib sqlite3). Used
                    for local dev + unit tests + Dockerfile test mode.
  - PostgresBackend : psycopg3 -> real Postgres. Lazy-imported (psycopg3
                    only installed in the Docker image / prod).

Both expose the same interface so the HTTP layer is backend-agnostic.

Wire protocol is defined in game/adapters/persistence/postgres_store.gd
and labs/prd-db.md sec.7.1.
"""
from __future__ import annotations

import sqlite3
from abc import ABC, abstractmethod
from typing import Any, Sequence


class Backend(ABC):
    """Abstract SQL backend shared by SQLite and Postgres adapters."""

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
    def query(self, sql: str, params: Sequence[Any] | None = None) -> list[dict]:
        """Run a SELECT; return list of rows (dicts keyed by column name)."""

    @abstractmethod
    def execute(self, sql: str, params: Sequence[Any] | None = None) -> int:
        """Run INSERT/UPDATE/DELETE/CREATE/etc.; return rows affected."""

    @abstractmethod
    def begin(self) -> int:
        ...

    @abstractmethod
    def commit(self, tx_id: int) -> bool:
        ...

    @abstractmethod
    def rollback(self, tx_id: int) -> bool:
        ...

    @abstractmethod
    def insert_many(self, table: str, rows: list, columns: list[str]) -> int:
        ...

    @abstractmethod
    def execute_batch(self, statements: list[str]) -> bool:
        """Run a list of SQL statements, each in the same transaction."""


# ── SQLite backend (stdlib, in-memory) ─────────────────────────────────────

_SQLITE_PLACEHOLDER = "?"          # psycopg uses $1, $2; sqlite uses ?
_SQLITE_TYPES = (sqlite3.Connection, sqlite3.Row)


def _convert_sql(sql: str, params: Sequence[Any] | None) -> tuple[str, list]:
    """Translate $N positional params to ? for SQLite."""
    if not params:
        return sql, []
    out = sql
    for i in range(len(params), 0, -1):
        out = out.replace("$%d" % i, "?")
    return out, list(params)


class SQLiteBackend(Backend):
    """In-memory SQLite backend. Mirrors pg-bridge's SQL surface for dev/test."""

    def __init__(self) -> None:
        self._con: sqlite3.Connection | None = None
        self._tx: sqlite3.Connection | None = None  # active transaction conn
        self._next_tx: int = 0

    def connect(self, config: dict) -> int:
        self._con = sqlite3.connect(
            ":memory:", check_same_thread=False, isolation_level=None
        )
        self._con.row_factory = sqlite3.Row
        self._next_tx = 0
        return 0

    def close(self) -> None:
        if self._tx:
            self._tx.rollback()
            self._tx.close()
        self._tx = None
        if self._con:
            self._con.close()
        self._con = None

    def healthy(self) -> bool:
        if self._con is None:
            return False
        try:
            self._con.execute("SELECT 1")
            return True
        except sqlite3.Error:
            return False

    def query(self, sql: str, params: Sequence[Any] | None = None) -> list[dict]:
        s, p = _convert_sql(sql, params)
        con = self._tx if self._tx else self._con
        rows = con.execute(s, p).fetchall()
        return [dict(r) for r in rows]

    def execute(self, sql: str, params: Sequence[Any] | None = None) -> int:
        s, p = _convert_sql(sql, params)
        con = self._tx if self._tx else self._con
        cur = con.execute(s, p)
        return cur.rowcount if cur.rowcount > 0 else 0

    def begin(self) -> int:
        # SQLite: begin on a fresh cursor connection; autocommit off for tx.
        self._next_tx += 1
        self._tx = self._con
        self._tx.isolation_level = None  # manage manually
        self._tx.execute("BEGIN")
        return self._next_tx

    def commit(self, tx_id: int) -> bool:
        if self._tx is None:
            return False
        try:
            self._tx.execute("COMMIT")
        except sqlite3.Error:
            pass
        self._tx = None
        return True

    def rollback(self, tx_id: int) -> bool:
        if self._tx is None:
            return False
        try:
            self._tx.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        self._tx = None
        return True

    def insert_many(self, table: str, rows: list, columns: list[str]) -> int:
        if not rows:
            return 0
        placeholders = ",".join("?" * len(columns))
        cols = ",".join(columns)
        sql = "INSERT INTO %s (%s) VALUES (%s)" % (table, cols, placeholders)
        con = self._tx if self._tx else self._con
        cur = con.executemany(sql, [list(r[:len(columns)]) for r in rows])
        return cur.rowcount

    def execute_batch(self, statements: list[str]) -> bool:
        con = self._tx if self._tx else self._con
        try:
            for stmt in statements:
                if stmt.strip():
                    con.execute(stmt)
            return True
        except sqlite3.Error:
            return False


# ── Postgres backend (psycopg3) ──────────────────────────────────────────────
# Lazy-imported so the module loads (and tests run) without psycopg3 installed.

class PostgresBackend(Backend):
    """Real Postgres backend via psycopg3. Installed in the Docker image."""

    def __init__(self) -> None:
        self._pool: list = []
        self._tx_conns: dict[int, Any] = {}
        self._next_tx = 0
        self._dsn: str = ""

    def connect(self, config: dict) -> int:
        try:
            import psycopg  # type: ignore
        except ImportError:
            raise RuntimeError(
                "psycopg3 not installed; pg-bridge image must include it. "
                "Use the SQLite backend for local dev."
            )
        self._dsn = config.get(
            "dsn", "host=postgres port=5432 dbname=synmergia user=synmergia "
            "password=synmergia_dev_pass"
        )
        self._pool = [psycopg.connect(self._dsn) for _ in range(config.get("pool_size", 8))]
        self._next_tx = 0
        return 0

    def close(self) -> None:
        for c in self._tx_conns.values():
            c.close()
        self._tx_conns.clear()
        for c in self._pool:
            c.close()
        self._pool.clear()

    def healthy(self) -> bool:
        if not self._pool:
            return False
        try:
            self._pool[0].execute("SELECT 1")
            return True
        except Exception:
            return False

    def _conn(self):
        return self._pool[0]

    def query(self, sql: str, params=None) -> list[dict]:
        with self._conn().cursor() as cur:
            cur.execute(sql, params or [])
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def execute(self, sql: str, params=None) -> int:
        with self._conn().cursor() as cur:
            cur.execute(sql, params or [])
            return cur.rowcount

    def begin(self) -> int:
        import psycopg  # type: ignore
        self._next_tx += 1
        c = self._pool[0]
        c.autocommit = False
        c.execute("BEGIN")
        self._tx_conns[self._next_tx] = c
        return self._next_tx

    def commit(self, tx_id: int) -> bool:
        c = self._tx_conns.pop(tx_id, None)
        if c is None:
            return False
        try:
            c.execute("COMMIT")
        except Exception:
            pass
        c.autocommit = True
        return True

    def rollback(self, tx_id: int) -> bool:
        c = self._tx_conns.pop(tx_id, None)
        if c is None:
            return False
        try:
            c.execute("ROLLBACK")
        except Exception:
            pass
        c.autocommit = True
        return True

    def insert_many(self, table: str, rows, columns: list[str]) -> int:
        if not rows:
            return 0
        placeholders = ",".join(["%s"] * len(columns))
        cols = ",".join(columns)
        sql = "INSERT INTO %s (%s) VALUES (%s)" % (table, cols, placeholders)
        with self._conn().cursor() as cur:
            cur.executemany(sql, [list(r[:len(columns)]) for r in rows])
            return cur.rowcount

    def execute_batch(self, statements: list[str]) -> bool:
        with self._conn().cursor() as cur:
            for stmt in statements:
                if stmt.strip():
                    cur.execute(stmt)
            return True
