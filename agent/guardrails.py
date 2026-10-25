"""Rules the agent cannot break, in code the user owns.

Anything on ASK_FIRST needs an explicit yes through the approvals flow before
it runs. The agent cannot edit this file through its own self-edit loop
(see selfedit.py's PROTECTED list).
"""
from __future__ import annotations

ASK_FIRST = {
    "send_message",      # texting or emailing anyone as the user
    "spend",             # any payment, purchase, booking, credits
    "post_public",       # posting anything publicly
    "grant_permission",  # new accounts, new scopes, new access
    "delete_data",       # removing memories, files, messages
}

PROTECTED_FILES = {"agent/guardrails.py"}  # the self-edit loop may not touch these


def needs_approval(action: str) -> bool:
    return action in ASK_FIRST
