"""What the agent learns: preferences, facts, feedback. Plain SQLite on the PC.

This is the honest version of 'self-improving': every correction and approval
becomes a row the agent reads back next time. No magic weight updates.
Also stores the approval queue, the activity log and the paused flag, so the
iPhone app always reads real state, never a simulation.
"""
from __future__ import annotations
import sqlite3
from pathlib import Path
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,          -- preference | fact | feedback
    text TEXT NOT NULL,
    created_at REAL NOT NULL,
    superseded_by INTEGER        -- set when a newer memory replaces this one
);
CREATE TABLE IF NOT EXISTS approvals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    summary TEXT NOT NULL,       -- one-line what Mike wants to do
    detail TEXT NOT NULL,        -- full context the user reviews
    created_at REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'   -- pending | approved | denied
);
CREATE TABLE IF NOT EXISTS activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,          -- chat | approval | feedback | stop | selfedit | ...
    summary TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS kv (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


class Memory:
    def __init__(self, path: str):
        if path != ":memory:":
            parent = Path(path).expanduser().parent
            if str(parent) not in ("", "."):
                parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.executescript(SCHEMA)

    # ---- memories: how it learns -------------------------------------
    def remember(self, kind: str, text: str) -> int:
        cur = self.db.execute(
            "INSERT INTO memories (kind, text, created_at) VALUES (?, ?, ?)",
            (kind, text, time.time()),
        )
        self.db.commit()
        return cur.lastrowid

    def recall(self, limit: int = 50) -> list[tuple[int, str, str]]:
        rows = self.db.execute(
            "SELECT id, kind, text FROM memories "
            "WHERE superseded_by IS NULL ORDER BY created_at DESC LIMIT ?",
            (limit,),
        )
        return rows.fetchall()

    def correct(self, old_id: int, new_text: str) -> int:
        """User corrected something: keep history, point old at new."""
        new_id = self.remember("preference", new_text)
        self.db.execute("UPDATE memories SET superseded_by=? WHERE id=?", (new_id, old_id))
        self.db.commit()
        return new_id

    # ---- approval queue ----------------------------------------------
    def request_approval(self, summary: str, detail: str) -> int:
        cur = self.db.execute(
            "INSERT INTO approvals (summary, detail, created_at) VALUES (?, ?, ?)",
            (summary, detail, time.time()),
        )
        self.db.commit()
        return cur.lastrowid

    def pending_approvals(self) -> list[dict]:
        rows = self.db.execute(
            "SELECT id, summary, detail, created_at FROM approvals "
            "WHERE status='pending' ORDER BY created_at ASC"
        ).fetchall()
        return [
            {"id": str(r[0]), "summary": r[1], "detail": r[2],
             "createdAt": r[3], "status": "pending"}
            for r in rows
        ]

    def decide_approval(self, approval_id: int, approved: bool) -> bool:
        """Returns False when no such pending approval exists."""
        cur = self.db.execute(
            "UPDATE approvals SET status=? WHERE id=? AND status='pending'",
            ("approved" if approved else "denied", approval_id),
        )
        self.db.commit()
        return cur.rowcount == 1

    # ---- activity log --------------------------------------------------
    def log_activity(self, kind: str, summary: str) -> int:
        cur = self.db.execute(
            "INSERT INTO activity (kind, summary, created_at) VALUES (?, ?, ?)",
            (kind, summary, time.time()),
        )
        self.db.commit()
        return cur.lastrowid

    def recent_activity(self, limit: int = 100) -> list[dict]:
        rows = self.db.execute(
            "SELECT id, kind, summary, created_at FROM activity "
            "ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [
            {"id": str(r[0]), "kind": r[1], "summary": r[2], "time": r[3]}
            for r in rows
        ]

    # ---- paused flag ----------------------------------------------------
    def set_paused(self, paused: bool) -> None:
        self.db.execute(
            "INSERT INTO kv (key, value) VALUES ('paused', ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            ("1" if paused else "0",),
        )
        self.db.commit()

    def is_paused(self) -> bool:
        row = self.db.execute("SELECT value FROM kv WHERE key='paused'").fetchone()
        return bool(row and row[0] == "1")
