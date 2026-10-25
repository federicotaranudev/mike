"""Regression: a bare run (no DB_PATH env, no /data dir) must work.

The first live run on a real PC 500'd on /status because the default DB
path was /data/agent.db, which only exists inside the docker container.
"""
from agent.memory import Memory


def test_memory_creates_missing_parent_dir(tmp_path):
    p = tmp_path / "sub" / "dir" / "m.db"
    Memory(str(p))
    assert p.exists()


def test_default_db_path_is_repo_local():
    import os
    assert "DB_PATH" not in os.environ or os.environ["DB_PATH"] != "/data/agent.db"
    from agent.config import settings
    assert settings.db_path == os.getenv("DB_PATH", "mike.db")
    assert not settings.db_path.startswith("/data")
