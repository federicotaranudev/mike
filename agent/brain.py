"""Model calls: one user-approved provider, fail closed.

Design contract: Mike may use exactly one inference provider, and only after
the user explicitly chooses and approves it. Until that approval and its key
exist, no provider is configured and every call raises ProviderNotConfigured.
When a free daily quota is spent, Mike says so and stops - it must never move
the user's data to a different provider on its own, and never falls back to
anything paid.

Reference numbers, checked 25 Oct 2026, Groq free tier: ~1,000 requests/day,
30/min, 200K tokens/day (console.groq.com/docs/rate-limits). Other providers
can be added later, each only after the user's explicit yes.
"""
from __future__ import annotations
import httpx

from .config import settings

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "openai/gpt-oss-120b"


class QuotaSpent(RuntimeError):
    """Today's free quota is gone. Say so, try again tomorrow."""


class ProviderNotConfigured(RuntimeError):
    """No approved key yet."""


async def think(messages: list[dict]) -> str:
    if not settings.groq_api_key:
        raise ProviderNotConfigured("no approved Groq key configured")
    async with httpx.AsyncClient(timeout=60) as client:
        r = await client.post(
            GROQ_URL,
            headers={"Authorization": f"Bearer {settings.groq_api_key}"},
            json={"model": GROQ_MODEL, "messages": messages},
        )
        if r.status_code in (402, 429):
            raise QuotaSpent("groq free tier limit reached")
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]
