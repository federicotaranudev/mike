"""The iPhone app's contract: these endpoints and shapes must stay real."""
import pytest
from fastapi.testclient import TestClient

from agent import api


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(api, "memory", api.Memory(str(tmp_path / "t.db")))
    return TestClient(api.app)


def test_status_shape(client):
    s = client.get("/status").json()
    assert set(s) == {"providerConfigured", "quotaRemainingToday", "paused"}
    assert s["paused"] is False


def test_approval_lifecycle(client):
    api.memory.request_approval("text Marco", "Mike wants to reply to Marco's message")
    pending = client.get("/approvals/pending").json()
    assert len(pending) == 1
    a = pending[0]
    assert set(a) == {"id", "summary", "detail", "createdAt", "status"}
    assert a["status"] == "pending"
    assert client.post(f"/approvals/{a['id']}", json={"approve": True}).json() == {"ok": True}
    assert client.get("/approvals/pending").json() == []
    # deciding twice is a real 404, not a fake ok
    assert client.post(f"/approvals/{a['id']}", json={"approve": True}).status_code == 404


def test_activity_records_real_events(client):
    api.memory.request_approval("spend 5 EUR", "buy a coffee")
    aid = client.get("/approvals/pending").json()[0]["id"]
    client.post(f"/approvals/{aid}", json={"approve": False})
    entries = client.get("/activity").json()
    assert any(e["kind"] == "approval" and "denied" in e["summary"] for e in entries)
    assert all(set(e) == {"id", "kind", "summary", "time"} for e in entries)


def test_stop_pauses_chat(client):
    client.post("/stop")
    assert client.get("/status").json()["paused"] is True
    reply = client.post("/chat", json={"message": "hi"}).json()["reply"]
    assert "paused" in reply.lower()
    client.post("/start")
    assert client.get("/status").json()["paused"] is False


def test_chat_without_key_fails_closed(client, monkeypatch):
    import dataclasses
    monkeypatch.setattr(api, "settings", dataclasses.replace(api.settings, groq_api_key=""))
    reply = client.post("/chat", json={"message": "hello"}).json()["reply"]
    assert "model key" in reply.lower()
