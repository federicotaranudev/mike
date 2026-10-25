from agent.guardrails import needs_approval


def test_sensitive_actions_ask_first():
    assert needs_approval("send_message")
    assert needs_approval("spend")
    assert needs_approval("grant_permission")


def test_readonly_actions_are_free():
    assert not needs_approval("check_weather")
    assert not needs_approval("remember")
