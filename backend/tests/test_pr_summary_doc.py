from pathlib import Path


def test_pr_summary_doc_mentions_universal_resolver():
    text = (Path(__file__).resolve().parents[1] / "docs" / "pr-summary.md").read_text(encoding="utf-8")
    assert "universal resolver" in text.lower()
