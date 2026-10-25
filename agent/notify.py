"""ntfy push to the user's phone, same pattern NOVA already uses. Free."""
from __future__ import annotations
import httpx

from .config import settings


async def ping(title: str, body: str) -> None:
    if not settings.ntfy_topic:
        return
    async with httpx.AsyncClient(timeout=15) as client:
        await client.post(
            f"https://ntfy.sh/{settings.ntfy_topic}",
            content=body,
            headers={"Title": title},
        )
