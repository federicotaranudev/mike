"""Proactivity: jobs that run on their own and ping the user when something matters.

INCOMPLETE: no real proactive sources are implemented yet. The scheduler starts
but registers zero jobs, so Mike never sends unsolicited placeholder pings.
Add real jobs here only when they have something genuinely useful to say.
"""
from __future__ import annotations
from apscheduler.schedulers.asyncio import AsyncIOScheduler


def start() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler()
    # No jobs registered yet: goals/proactivity are not implemented (see README
    # "What Mike does not do yet"). Register real jobs here when they exist.
    scheduler.start()
    return scheduler
