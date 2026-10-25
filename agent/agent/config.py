"""Environment-driven configuration. Secrets come from .env, never from the repo."""
from __future__ import annotations
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    groq_api_key: str = os.getenv("GROQ_API_KEY", "")
    ntfy_topic: str = os.getenv("NTFY_TOPIC", "")
    agent_name: str = os.getenv("AGENT_NAME", "agent")
    approval_required: bool = os.getenv("APPROVAL_REQUIRED", "true").lower() == "true"
    db_path: str = os.getenv("DB_PATH", "/data/agent.db")
    host: str = os.getenv("HOST", "127.0.0.1")
    port: int = int(os.getenv("PORT", "8787"))


settings = Settings()
