"""HTTP API the iPhone app talks to, reached only through the secure tunnel."""
from __future__ import annotations
from fastapi import FastAPI
from pydantic import BaseModel

from .brain import ProviderNotConfigured, QuotaSpent, think
from .config import settings
from .guardrails import needs_approval
from .memory import Memory

app = FastAPI(title="agent", version="0.1.0")
memory = Memory(settings.db_path)


class ChatIn(BaseModel):
    message: str


class ApprovalIn(BaseModel):
    action: str
    approved: bool


@app.get("/status")
async def status():
    return {"name": settings.agent_name, "memories": len(memory.recall(1000))}


@app.post("/chat")
async def chat(body: ChatIn):
    memories = "\n".join(f"- {text}" for _, _, text in memory.recall())
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
    return {"reply": reply}


@app.post("/feedback")
async def feedback(text: str):
    """How it learns: the user's correction becomes memory."""
    memory.remember("feedback", text)
    return {"stored": True}


@app.post("/approvals")
async def approve(body: ApprovalIn):
    if not needs_approval(body.action):
        return {"ok": False, "reason": "that action never needed approval"}
    memory.remember("feedback", f"user {'approved' if body.approved else 'denied'}: {body.action}")
    return {"ok": True}
