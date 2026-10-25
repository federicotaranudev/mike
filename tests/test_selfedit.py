from agent.guardrails import PROTECTED_FILES


def test_guardrails_are_protected():
    assert "agent/guardrails.py" in PROTECTED_FILES


def test_run_tests_always_refuses(monkeypatch):
    """Fail closed: self-edit execution refuses even with any env marker set."""
    import pytest
    from agent import selfedit

    monkeypatch.setenv("MIKE_SELFEDIT_ISOLATED_CONTAINER", "yes")
    with pytest.raises(selfedit.SelfEditDisabled):
        selfedit.run_tests()
