"""HTTP API the iPhone app talks to, reached only through the secure tunnel.

Every endpoint reads or writes real state in Memory. Where a capability is
not built yet, the API says so instead of pretending.
"""
from __future__ import annotations
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .brain import ProviderNotConfigured, QuotaSpent, think
from .config import settings
from .memory import Memory

app = FastAPI(title="mike", version="0.1.0")
# Created lazily: importing this module must not require a writable data dir.
memory: Memory | None = None


def mem() -> Memory:
    global memory
    if memory is None:
        memory = Memory(settings.db_path)
    return memory


class ChatIn(BaseModel):
    message: str


class FeedbackIn(BaseModel):
    text: str


class ApprovalDecision(BaseModel):
    approve: bool


@app.get("/status")
async def status():
    return {
        "providerConfigured": bool(settings.groq_api_key),
        # Honest null: per-day quota tracking is not implemented yet.
        "quotaRemainingToday": None,
        "paused": mem().is_paused(),
    }


@app.post("/chat")
async def chat(body: ChatIn):
    if mem().is_paused():
        return {"reply": "I'm paused. Start me again from the Activity tab and I'll pick this up."}
    memories = "\n".join(f"- {text}" for _, _, text in mem().recall())
    system = (
        f"You are {settings.agent_name}, the user's personal agent. "
        "Known about the user:\n" + (memories or "(nothing yet)")
    )
    try:
        reply = await think([
            {"role": "system", "content": system},
            {"role": "user", "content": body.message},
        ])
    except QuotaSpent:
        reply = "I'm out of free requests for today. I'll be back at full speed tomorrow."
    except ProviderNotConfigured:
        reply = "I don't have an approved model key yet. Ask me again once that's set up."
    mem().log_activity("chat", body.message[:140])
    return {"reply": reply}


@app.post("/feedback")
async def feedback(body: FeedbackIn):
    """How it learns: the user's correction becomes memory."""
    mem().remember("feedback", body.text)
    mem().log_activity("feedback", body.text[:140])
    return {"stored": True}


@app.get("/approvals/pending")
async def pending_approvals():
    return mem().pending_approvals()


@app.post("/approvals/{approval_id}")
async def decide_approval(approval_id: int, body: ApprovalDecision):
    if not mem().decide_approval(approval_id, body.approve):
        raise HTTPException(status_code=404, detail="no pending approval with that id")
    mem().log_activity(
        "approval",
        f"{'approved' if body.approve else 'denied'} approval #{approval_id}",
    )
    return {"ok": True}


@app.get("/activity")
async def activity():
    return mem().recent_activity()


@app.post("/stop")
async def stop():
    mem().set_paused(True)
    mem().log_activity("stop", "Mike paused by user")
    return {"paused": True}


@app.post("/start")
async def start():
    mem().set_paused(False)
    mem().log_activity("start", "Mike resumed by user")
    return {"paused": False}
