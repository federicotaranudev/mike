<div align="center">

# Mike

<img src="mike-logo.png" alt="Mike logo" width="180">

**A personal AI agent that lives on your iPhone. Free, honest about what it does, and yours.**

![status](https://img.shields.io/badge/status-v0.2%20early-orange)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
![cost](https://img.shields.io/badge/app-0%E2%82%AC%20free%20forever-brightgreen)

</div>

---

Mike is an iPhone app, plus an optional agent core you can run yourself.
On first launch it asks one question: **where should Mike's thinking happen?**
You pick, and you can change your mind later in Settings - your chats and
settings stay, and Mike never switches on its own.

| Mode | What it means | Status in v0.2 |
| --- | --- | --- |
| **Groq API** | Chat replies from Groq's API, direct from the phone. You paste your own key into the app, privately. | **Chat works.** The key is stored in the iPhone Keychain and used only in requests the app makes to api.groq.com. If Groq returns an error (for example a spent quota) Mike shows it - it never switches providers on its own. Memory, tools and approvals are not wired in this mode yet. |
| **Your own backend** | Connect to a Mike core you run yourself (HTTPS URL + access token). | **Works.** HTTPS is required; the token is stored in the Keychain. Approvals and Activity screens read from your core. |
| **On this iPhone** | A small on-device model (candidate: Gemma 4 E2B, which has documented tool calling). | **Not yet.** The runtime is still being integrated. If you pick it, Mike says so honestly instead of faking replies, and nothing downloads before you see its exact size. |

The app is free, forever. If you use a third-party provider key, that
account's terms and any costs are between you and them - Mike never changes
providers, upgrades plans, or spends anything on its own.

## What iOS does and doesn't allow

Design boundaries Mike is built around - these are platform rules, and most
of them are **planned work, not shipped features**:

- Chat works whenever you open the app (Groq or your backend).
- iOS can deliver **scheduled local notifications** when the app is closed; Mike's use of them is planned, not in this build.
- iOS grants **short background windows** at times the system chooses; using them for checks is planned, not in this build.
- **Not possible:** an always-running agent. If you force-quit the app, it does nothing until you open it again. An on-device model changes where thinking happens, not when iOS allows it.

## Install the iPhone app

No App Store, no paid Apple account:

1. Download `Mike-iPhone.ipa` from [Releases](https://github.com/federicotaranudev/mike/releases).
2. Sideload it with a tool like SideInstaller, Sideloadly or AltStore.
3. With a free Apple ID the signature expires after 7 days - re-sign weekly (Apple's rule, not ours).

## The agent core (optional backend)

What exists today: a FastAPI core with a chat endpoint, an approvals queue,
an activity log, SQLite memory, a test suite, and guardrails
(`agent/guardrails.py`).

Planned, not built yet: scheduled jobs, and the self-improvement loop below.

```bash
set -euo pipefail
git clone https://github.com/federicotaranudev/mike.git
cd mike
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
[ -f .env ] || cp .env.example .env   # existing .env is never overwritten
# set MIKE_TOKEN in .env now; GROQ_API_KEY later, once approved
python3 -m pytest tests
DB_PATH=./mike.db uvicorn agent.api:app --host 127.0.0.1 --port 8787
```

This binds to 127.0.0.1 only. Every endpoint requires
`Authorization: Bearer $MIKE_TOKEN` once the token is set - set it BEFORE any
tunnel or port forward exposes the core. Then point the app's "Your own
backend" mode at its HTTPS URL.

## What "self-improving" means here (planned)

1. **It learns you.** Corrections and approvals become memory rows it reads back next time. (Exists in the core.)
2. **It will propose improvements to its own code - once it is safe.** The plan: draft a change on a git branch, run tests inside a networkless throwaway container, show you the diff, apply only with your yes. Until that isolated container exists, self-edit execution is DISABLED on purpose: model-generated code never runs.
3. **It stays in its lane.** Messaging anyone, spending, posting, or new permissions always require your approval. Guardrails live in `agent/guardrails.py`, which the self-edit loop is forbidden to touch.

## Privacy

- Keys and tokens live in the iPhone Keychain, not in logs, the repo, or chats. Builds before v0.2 kept the backend token in UserDefaults; v0.2 moves it to the Keychain and deletes the old copy on first launch.
- No analytics, no tracking, no third-party servers except the provider you chose yourself.

## Screenshots

Automated simulator captures of the v0.2 UI (fresh-install states, no backend
connected, no key entered):

- [Setup screen](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/ONBOARDING.png)
- [Chat (Groq mode selected)](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/CHAT.png)
- [Chat with on-device mode selected, honestly unavailable](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/LOCALCHAT.png)
- [Settings](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/SETTINGS.png)
- [Approvals](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/APPROVALS.png)
- [Activity](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/ACTIVITY.png)

## License

MIT. See [LICENSE](LICENSE).
