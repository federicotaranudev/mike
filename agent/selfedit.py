"""The self-improvement loop, kept honest - currently DISABLED, fail closed.

Status: not wired into the API and not safe to run yet. There is no isolated
sandbox, so model-generated code must NEVER execute on the user's PC. The
test-runner below refuses to run unless it detects it is inside a throwaway
container (no such container exists yet), and nothing in the server calls
these functions. This is intentional containment, not a missing feature flag.

Future flow, once real isolation exists: draft change on a git branch -> run
tests inside a networkless container -> show the user the diff -> user
approves -> merge. It must never touch guardrails.py and never merge itself.
"""
from __future__ import annotations
import os
import subprocess

from .guardrails import PROTECTED_FILES


class ProtectedFileTouched(RuntimeError):
    pass


class SelfEditDisabled(RuntimeError):
    """Raised whenever anything tries to execute self-edit code without a
    verified isolated sandbox. Fail closed: no exception path runs the code."""


def changed_files(branch: str = "self-edit") -> list[str]:
    """Read-only: list files a branch touched."""
    out = subprocess.run(
        ["git", "diff", "--name-only", "main..." + branch],
        capture_output=True, text=True, check=True,
    )
    return [f for f in out.stdout.split() if f]


def check_allowed(branch: str = "self-edit") -> None:
    """Read-only: refuse branches that touch protected files."""
    touched = set(changed_files(branch))
    bad = touched & PROTECTED_FILES
    if bad:
        raise ProtectedFileTouched(f"self-edit may not change: {sorted(bad)}")


def run_tests() -> bool:
    """DISABLED. Running model-generated tests/code on the user's PC without
    an isolated sandbox would give generated code the server's network access
    and secrets. Only an actual throwaway container may set the marker below;
    since that container does not exist yet, this always raises."""
    if os.environ.get("MIKE_SELFEDIT_ISOLATED_CONTAINER") != "yes":
        raise SelfEditDisabled(
            "self-edit execution is disabled: no isolated sandbox exists. "
            "Model-generated code must not run on the user's PC."
        )
    raise SelfEditDisabled("unreachable: sandbox not implemented")  # pragma: no cover


def diff_for_approval(branch: str = "self-edit") -> str:
    """Read-only: produce the diff a user would review."""
    check_allowed(branch)
    out = subprocess.run(
        ["git", "diff", "main..." + branch], capture_output=True, text=True, check=True
    )
    return out.stdout
