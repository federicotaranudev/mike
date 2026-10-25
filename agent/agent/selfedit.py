"""The self-improvement loop, kept honest.

Flow: the agent drafts a change -> applies it on a git branch -> runs the
test suite in a networkless container -> shows the user the diff -> the user
approves -> merge. It can never touch guardrails.py and never merges itself.
"""
from __future__ import annotations
import subprocess

from .guardrails import PROTECTED_FILES


class ProtectedFileTouched(RuntimeError):
    pass


def changed_files(branch: str = "self-edit") -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", "main..." + branch],
        capture_output=True, text=True, check=True,
    )
    return [f for f in out.stdout.split() if f]


def check_allowed(branch: str = "self-edit") -> None:
    touched = set(changed_files(branch))
    bad = touched & PROTECTED_FILES
    if bad:
        raise ProtectedFileTouched(f"self-edit may not change: {sorted(bad)}")


def run_tests() -> bool:
    """Runs in the selfedit-runner container: no network, no host access."""
    result = subprocess.run(["python", "-m", "pytest", "-q"], capture_output=True)
    return result.returncode == 0


def diff_for_approval(branch: str = "self-edit") -> str:
    check_allowed(branch)
    out = subprocess.run(
        ["git", "diff", "main..." + branch], capture_output=True, text=True, check=True
    )
    return out.stdout
