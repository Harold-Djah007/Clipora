from pathlib import Path


def test_current_branch_doc_mentions_branch_name():
    text = (Path(__file__).resolve().parents[1] / "docs" / "current-branch.md").read_text(encoding="utf-8")
    assert "feature/universal-resolver-foundation" in text
