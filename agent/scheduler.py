"""Proactivity: jobs that run on their own and ping the user when something matters."""
from __future__ import annotations
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from .notify import ping


async def morning_check() -> None:
    # Placeholder job: v1 will fill this with real sources the user picks.
    await ping("agent", "Morning check ran. Nothing needed you.")


def start() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler()
    scheduler.add_job(morning_check, "cron", hour=6, minute=30)
    scheduler.start()
    return scheduler
