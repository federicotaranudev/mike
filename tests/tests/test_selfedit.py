from agent.guardrails import PROTECTED_FILES


def test_guardrails_are_protected():
    assert "agent/guardrails.py" in PROTECTED_FILES
