from pathlib import Path


def test_versioning_doc_mentions_current_foundation():
    text = (Path(__file__).resolve().parents[1] / "docs" / "versioning.md").read_text(encoding="utf-8")
    assert "0.8.4-universal-foundation" in text
