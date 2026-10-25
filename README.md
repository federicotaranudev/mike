<div align="center">

# Mike

<img src="mike-logo.png" alt="Mike logo" width="180">

**A personal AI agent that lives on your iPhone. Free, honest about what it does, and yours.**

![status](https://img.shields.io/badge/status-v0.2%20early-orange)
![license](https://img.shields.io/badge/license-MIT-lightgrey)
![cost](https://img.shields.io/badge/cost-0%E2%82%AC%20free%20forever-brightgreen)

</div>

---

Mike is an iPhone app plus an optional agent core. On first launch it asks one
question: **where should Mike's thinking happen?** You pick, and you can change
your mind later in Settings - your chats and memory stay, and Mike never
switches on its own.

| Mode | What it means | Status in v0.2 |
| --- | --- | --- |
| **Groq API** | Fast cloud replies on Groq's free tier. You paste your own key into the app, privately. | **Works.** The key is stored in the iPhone Keychain and only ever sent to api.groq.com. |
| **Your own backend** | Connect to a Mike agent core you run yourself (HTTPS URL + access token). | **Works.** HTTPS is enforced; the token is stored in the Keychain. |
| **On this iPhone** | A small on-device model (candidate: Gemma 4 E2B, which has documented tool calling). | **Not yet.** The runtime is still being integrated. If you pick it, Mike says so honestly instead of faking replies. No download starts before you see its exact size. |

Mike itself is free, forever. No subscriptions, no paid APIs.
Free tiers from third parties can change their limits - if they do, Mike says
so and stops. It never falls back to anything paid on its own.

## What Mike can and cannot do on a phone

Honest limits, from how iOS works today:

- **Chat, memory and approvals** work whenever you open the app.
- **Scheduled reminders** can be delivered by the system even when the app is closed.
- **Background checks** happen in short windows when iOS decides to grant them - opportunistic, not on a fixed schedule.
- **Not possible today:** an always-running agent. If you force-quit the app, it does nothing until you open it again. An on-device model does not change this - it changes where thinking happens, not when iOS allows it.

## Install the iPhone app

No App Store, no paid Apple account:

1. Download `Mike-iPhone.ipa` from the [latest release](https://github.com/federicotaranudev/mike/releases/latest).
2. Sideload it with a tool like SideInstaller, Sideloadly or AltStore.
3. With a free Apple ID the signature expires after 7 days - re-sign weekly (Apple's rule, not ours).

## The agent core (optional backend)

The core adds memory, scheduled jobs, model routing and a guarded
self-improvement loop. Run it on any machine you own (Linux, Python 3.10+):

```bash
git clone https://github.com/federicotaranudev/mike.git
cd mike
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # set MIKE_TOKEN now; GROQ_API_KEY later, once approved
python3 -m pytest tests
DB_PATH=./mike.db uvicorn agent.api:app --host 127.0.0.1 --port 8787
```

This binds to 127.0.0.1 only. Every endpoint requires
`Authorization: Bearer $MIKE_TOKEN` once the token is set - set it BEFORE any
tunnel or port forward exposes the core. Then point the app's "Your own
backend" mode at its HTTPS URL.

## What "self-improving" means here

No unbounded robot intelligence. Three real mechanisms:

1. **It learns you.** Your corrections and approvals become memory rows it reads back next time.
2. **It will propose improvements to its own code - once it is safe.** Planned: draft a change on a git branch, run tests inside a networkless throwaway container, show you the diff, apply only with your yes. Until that isolated container exists, self-edit execution is DISABLED on purpose: model-generated code never runs.
3. **It stays in its lane.** Messaging anyone, spending, posting, or new permissions always require your approval. Those rules live in `agent/guardrails.py`, which the self-edit loop is forbidden to touch.

## Privacy

- Keys and tokens live in the iPhone Keychain. They are never written to logs,
  UserDefaults, the repo, or a chat.
- No analytics, no tracking, no third-party servers except the provider you
  chose yourself.
- Gemini's free tier is deliberately not used: Google uses free-tier prompts
  and responses to improve its products.

## Screenshots

Automated simulator captures of the current UI (evidence, not marketing -
fresh-install states, no backend connected):

- [Setup screen](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/ONBOARDING.png)
- [Chat (Groq mode)](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/CHAT.png)
- [Chat with on-device mode selected, honestly unavailable](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/LOCALCHAT.png)
- [Settings](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/SETTINGS.png)
- [Approvals](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/APPROVALS.png)
- [Activity](https://github.com/federicotaranudev/mike/releases/download/sim-evidence/ACTIVITY.png)

## License

MIT. See [LICENSE](LICENSE).
