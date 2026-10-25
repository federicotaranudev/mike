from agent.memory import Memory


def test_remember_and_recall(tmp_path):
    m = Memory(str(tmp_path / "t.db"))
    m.remember("preference", "likes short answers")
    rows = m.recall()
    assert len(rows) == 1
    assert rows[0][2] == "likes short answers"


def test_correction_supersedes(tmp_path):
    m = Memory(str(tmp_path / "t.db"))
    old = m.remember("fact", " wakes at 8")
    m.correct(old, "wakes at 6:10")
    texts = [t for _, _, t in m.recall()]
    assert "wakes at 6:10" in texts
    assert all("8" not in t for t in texts)
