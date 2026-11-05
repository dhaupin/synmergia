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


def _pg_convert_sql(sql: str, params: Sequence[Any] | None) -> tuple[str, list]:
    """Translate $N positional params to %s for psycopg3.

    psycopg3 speaks %s placeholders, not $N. Scan for $N tokens in order
    and rebuild the parameter list, duplicating a param when its $N repeats.
    Literal '%' in the SQL is escaped to '%%' because psycopg treats '%' as
    the placeholder introducer -- even when no params are supplied (a bare
    "LIKE 'tick:%'" would otherwise raise "only '%s', '%b', '%t' are
    allowed as placeholders").
    """
    import re

    if not params:
        return sql.replace("%", "%%"), []

    values = list(params)
    ordered: list = []
    out_parts: list[str] = []
    last = 0
    for m in re.finditer(r"\$(\d+)", sql):
        idx = int(m.group(1)) - 1
        out_parts.append(sql[last:m.start()].replace("%", "%%"))
        out_parts.append("%s")
        ordered.append(values[idx] if 0 <= idx < len(values) else None)
        last = m.end()
    out_parts.append(sql[last:].replace("%", "%%"))
    return "".join(out_parts), ordered


def _stmt_to_sql_params(stmt: Any) -> tuple[str, list]:
    """Normalize a batch statement: either a SQL string or {sql, params}."""
    if isinstance(stmt, dict):
        return stmt.get("sql", ""), list(stmt.get("params", []) or [])
    return str(stmt), []


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
                sql, params = _stmt_to_sql_params(stmt)
                if sql.strip():
                    s, p = _convert_sql(sql, params)
                    con.execute(s, p)
            return True
        except sqlite3.Error:
            return False


# ── Postgres backend (psycopg3) ──────────────────────────────────────────────
# Lazy-imported so the module loads (and tests run) without psycopg3 installed.

class PostgresBackend(Backend):
    """Real Postgres backend via psycopg3. Installed in the Docker image.

    Transaction model mirrors SQLiteBackend: one primary connection runs in
    autocommit mode, and an explicit transaction is opened with a literal
    BEGIN and closed with COMMIT/ROLLBACK. psycopg3 defaults to
    autocommit=False, which would leave every statement in an uncommitted
    implicit transaction; the bridge would then fail to start an explicit
    transaction ("can't change 'autocommit' now: connection in transaction
    status INTRANS") and poison the connection for every later call.
    """

    def __init__(self) -> None:
        self._con: Any = None
        self._tx_active: bool = False
        self._next_tx: int = 0
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
        self._con = psycopg.connect(self._dsn, autocommit=True)
        self._next_tx = 0
        self._tx_active = False
        return 0

    def close(self) -> None:
        if self._con is not None:
            if self._tx_active:
                try:
                    self._con.rollback()
                except Exception:
                    pass
            self._con.close()
        self._con = None
        self._tx_active = False

    def healthy(self) -> bool:
        if self._con is None:
            return False
        try:
            self._con.execute("SELECT 1")
            return True
        except Exception:
            return False

    def query(self, sql: str, params=None) -> list[dict]:
        s, p = _pg_convert_sql(sql, params)
        with self._con.cursor() as cur:
            cur.execute(s, p)
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def execute(self, sql: str, params=None) -> int:
        s, p = _pg_convert_sql(sql, params)
        with self._con.cursor() as cur:
            cur.execute(s, p)
            # psycopg3 reports rowcount -1 for statements with no row count
            # (DDL like CREATE TABLE). The store reads -1 as failure, so
            # normalize to 0 the way SQLiteBackend does.
            return cur.rowcount if cur.rowcount > 0 else 0

    def begin(self) -> int:
        if self._tx_active:
            raise RuntimeError("transaction already active")
        self._next_tx += 1
        # autocommit stays True; a literal BEGIN opens a server-side block
        # that the following statements join until COMMIT/ROLLBACK.
        self._con.execute("BEGIN")
        self._tx_active = True
        return self._next_tx

    def commit(self, tx_id: int) -> bool:
        if not self._tx_active:
            return False
        self._con.execute("COMMIT")
        self._tx_active = False
        return True

    def rollback(self, tx_id: int) -> bool:
        if not self._tx_active:
            return False
        try:
            self._con.execute("ROLLBACK")
        except Exception:
            pass
        self._tx_active = False
        return True

    def insert_many(self, table: str, rows, columns: list[str]) -> int:
        if not rows:
            return 0
        placeholders = ",".join(["%s"] * len(columns))
        cols = ",".join(columns)
        sql = "INSERT INTO %s (%s) VALUES (%s)" % (table, cols, placeholders)
        with self._con.cursor() as cur:
            cur.executemany(sql, [list(r[:len(columns)]) for r in rows])
            return cur.rowcount

    def execute_batch(self, statements: list[str]) -> bool:
        with self._con.cursor() as cur:
            for stmt in statements:
                sql, params = _stmt_to_sql_params(stmt)
                if sql.strip():
                    s, p = _pg_convert_sql(sql, params)
                    cur.execute(s, p)
            return True
