"""What the agent learns: preferences, facts, feedback. Plain SQLite on the PC.

This is the honest version of 'self-improving': every correction and approval
becomes a row the agent reads back next time. No magic weight updates.
"""
from __future__ import annotations
import sqlite3
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
    action TEXT NOT NULL,        -- what the agent wanted to do
    approved INTEGER,            -- 1 yes, 0 no, NULL pending
    decided_at REAL
);
"""


class Memory:
    def __init__(self, path: str):
        self.db = sqlite3.connect(path)
        self.db.executescript(SCHEMA)

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
