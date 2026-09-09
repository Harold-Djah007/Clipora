from pathlib import Path


def test_local_backend_test_doc_mentions_pytest():
    text = (Path(__file__).resolve().parents[1] / "docs" / "local-backend-test.md").read_text(encoding="utf-8")
    assert "pytest -q" in text
